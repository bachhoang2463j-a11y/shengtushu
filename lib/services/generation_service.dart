// 生图管线编排器：LLM 提炼 → insertions 入库（占位符）→ 顺序队列 → ComfyUI → 回填
// 流程移植自「生图助手 v45.3.1」独立生词流程（顺序队列 / 重试 / 占位符替换）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../data/database.dart';
import 'comfyui_client.dart';
import 'image_store.dart';
import 'llm_client.dart';
import 'prompt_service.dart';
import 'settings_service.dart';

/// 队列条目的展示状态
class GenTaskView {
  final int illustrationId;
  final String promptPreview;
  String status; // queued | running | done | failed
  double progress; // 0..1
  String error;
  GenTaskView({
    required this.illustrationId,
    required this.promptPreview,
    this.status = 'queued',
    this.progress = 0,
    this.error = '',
  });
}

class GenerationException implements Exception {
  final String message;
  const GenerationException(this.message);
  @override
  String toString() => message;
}

class GenerationService extends ChangeNotifier {
  GenerationService._();
  static final GenerationService instance = GenerationService._();

  final _llm = LlmClient();
  final _prompt = PromptService();
  final _comfy = ComfyUIClient();
  final _settings = SettingsService.instance;

  AppDatabase? _db;
  void attachDb(AppDatabase db) => _db = db;

  final List<GenTaskView> queue = [];
  bool _running = false;

  bool get isBusy => _running || queue.any((t) => t.status == 'queued' || t.status == 'running');

  // ---------- 第一步：LLM 提炼并创建占位符 ----------

  /// 批量：当前页段落 → LLM → 占位符入库 → 入队
  Future<int> generateBatch({
    required Book book,
    required Chapter chapter,
    required List<String> pageParagraphs, // 当前页可见段落
    required int firstParagraphIndex, // 页首段落在本章中的序号（0-based）
    required List<String> history, // 前 N 段
  }) async {
    // ---- 预校验：任何一步不满足立即抛明确错误，不让用户面对"无反应" ----
    await _precheck();

    final cfg = _settings.llm;
    final messages = _prompt.buildMessages(
      template: _settings.indepTemplate,
      paragraphs: pageParagraphs,
      history: history,
      lore: book.lore,
      styleText: _settings.styleText,
      personas: _settings.personas,
    );

    debugPrint('[生图] 调用 LLM 提炼提示词（${pageParagraphs.length} 段）…');
    final raw = await _llm.chat(cfg, messages);
    debugPrint('[生图] LLM 返回 ${raw.length} 字符，解析 insertions…');
    final insertions = _prompt.parseInsertions(raw, maxParagraph: pageParagraphs.length);
    debugPrint('[生图] 解析出 ${insertions.length} 个插图位置');

    var created = 0;
    for (final ins in insertions) {
      final globalIdx = firstParagraphIndex + ins.afterParagraph - 1;
      if (globalIdx < 0 || globalIdx >= chapter.content.split('\n').length) continue;
      await _createIllustration(book, chapter, globalIdx, ins.prompt);
      created++;
    }
    if (created == 0) {
      throw const GenerationException('LLM 未返回有效插图位置');
    }
    return created;
  }

  /// 单段：长按某段落，仅对该段走同一条 LLM 管线
  Future<int> generateSingle({
    required Book book,
    required Chapter chapter,
    required int paragraphIndex,
    required List<String> history,
  }) async {
    final paras = chapter.content.split('\n');
    if (paragraphIndex < 0 || paragraphIndex >= paras.length) {
      throw const GenerationException('段落索引越界');
    }
    return generateBatch(
      book: book,
      chapter: chapter,
      pageParagraphs: [paras[paragraphIndex]],
      firstParagraphIndex: paragraphIndex,
      history: history,
    );
  }

  Future<int> _createIllustration(Book book, Chapter chapter, int globalIdx, String prompt) async {
    final db = _requireDb();
    final paras = chapter.content.split('\n');
    final hash = _hash(paras[globalIdx]);
    final id = await db.into(db.illustrations).insert(IllustrationsCompanion.insert(
      bookId: book.id,
      chapterId: chapter.id,
      afterParagraph: globalIdx,
      anchorHash: hash,
      prompt: prompt,
      imgWidth: Value(_settings.genWidth),
      imgHeight: Value(_settings.genHeight),
    ));
    queue.add(GenTaskView(illustrationId: id, promptPreview: _preview(prompt)));
    notifyListeners();
    if (!_running) _drain();
    return id;
  }

  /// 生图前快速校验：工作流已启用且可提交、LLM 已配置、ComfyUI 可达
  Future<void> _precheck() async {
    final db = _requireDb();
    final wfRows = await (db.select(db.workflows)..where((t) => t.isActive.equals(true))).get();
    if (wfRows.isEmpty) {
      throw const GenerationException(
          '没有启用的 ComfyUI 工作流。\n\n请到 设置 → 工作流管理 载入内置 Z-Image 工作流或导入 API 格式 JSON。');
    }
    final mapping = WorkflowMapping.fromJson(wfRows.first.mapping);
    final hasVar = wfRows.first.apiJson.contains('%prompt%');
    if (mapping.positive == null && !hasVar) {
      throw const GenerationException(
          '工作流既没有映射「正向提示词」节点，也不含 %prompt% 变量。\n\n请到 设置 → 工作流管理 点击该工作流完成映射。');
    }
    final llm = _settings.llm;
    if (llm.baseUrl.trim().isEmpty) {
      throw const GenerationException('LLM API 地址未配置。\n\n请到 设置 → LLM 填写 API 地址与 Key。');
    }
    final (ok, detail) = await _comfy.testConnection(_settings.comfyUrl);
    if (!ok) {
      throw GenerationException(
          '无法连接 ComfyUI：$detail\n\n检查：①手机与电脑同一局域网 ②ComfyUI 已启动且监听端口正确 ③电脑防火墙放行 8188 入站');
    }
    debugPrint('[生图] 预校验通过：workflow=${wfRows.first.name}，comfy=${_settings.comfyUrl}');
  }

  // ---------- 第二步：顺序队列 ----------

  Future<void> _drain() async {
    if (_running) return;
    _running = true;
    try {
      while (true) {
        final next = queue.indexWhere((t) => t.status == 'queued');
        if (next < 0) break;
        final task = queue[next];
        await _runTask(task);
      }
    } finally {
      _running = false;
      notifyListeners();
    }
  }

  Future<void> _runTask(GenTaskView task) async {
    final db = _requireDb();
    final settings = _settings;

    for (var attempt = 0; attempt <= settings.genRetry; attempt++) {
      try {
        final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(task.illustrationId))).getSingle();
        final wfRows = await (db.select(db.workflows)..where((t) => t.isActive.equals(true))).get();
        if (wfRows.isEmpty) {
          throw const GenerationException('没有启用的 ComfyUI 工作流，请到设置里导入并启用');
        }
        final wf = wfRows.first;
        final mapping = WorkflowMapping.fromJson(wf.mapping);
        if (mapping.positive == null) {
          throw const GenerationException('工作流未映射「正向提示词」节点');
        }
        final workflowJson = jsonDecode(wf.apiJson) as Map<String, dynamic>;

        task.status = 'running';
        task.progress = 0;
        await (db.update(db.illustrations)..where((t) => t.id.equals(task.illustrationId)))
            .write(const IllustrationsCompanion(status: Value('running'), error: Value(''))); // 阅读器监听 DB 自动刷新占位符
        notifyListeners();

        final savePath = await ImageStore.instance.newPath(ill.bookId, 'png');
        final path = await _comfy.generate(
          baseUrl: settings.comfyUrl,
          workflow: workflowJson,
          mapping: mapping,
          positive: ill.prompt,
          width: ill.imgWidth,
          height: ill.imgHeight,
          batch: 1,
          autoRandomSeed: settings.autoRandomSeed,
          saveDir: savePath.substring(0, savePath.lastIndexOf(Platform.pathSeparator)),
          onProgress: (p) {
            if (p.ratio != null) task.progress = p.ratio!;
            notifyListeners();
          },
        );

        // 读实际尺寸回填
        int w = ill.imgWidth, h = ill.imgHeight;
        try {
          final bytes = await File(path).readAsBytes();
          final codec = await ui.instantiateImageCodec(bytes);
          final frame = await codec.getNextFrame();
          w = frame.image.width;
          h = frame.image.height;
          frame.image.dispose();
          codec.dispose();
        } catch (_) {}

        await (db.update(db.illustrations)..where((t) => t.id.equals(task.illustrationId))).write(
          IllustrationsCompanion(
            status: const Value('done'),
            imagePath: Value(path),
            imgWidth: Value(w),
            imgHeight: Value(h),
            error: const Value(''),
          ),
        );
        task.status = 'done';
        task.progress = 1;
        notifyListeners();
        return;
      } catch (e) {
        final msg = e is GenerationException ? e.message : e.toString();
        debugPrint('[生图] 任务 ${task.illustrationId} 第 ${attempt + 1} 次尝试失败：$msg');
        if (attempt >= settings.genRetry) {
          task.status = 'failed';
          task.error = msg;
          await (db.update(db.illustrations)..where((t) => t.id.equals(task.illustrationId)))
              .write(IllustrationsCompanion(status: const Value('failed'), error: Value(msg)));
          notifyListeners();
          return;
        }
        task.error = '第 ${attempt + 1} 次尝试失败：$msg';
        notifyListeners();
        await Future<void>.delayed(Duration(seconds: 2 * (attempt + 1)));
      }
    }
  }

  /// 清空已完成的队列条目；[includingPending] 同时取消未开始的任务
  void clearQueue({bool includingPending = false}) {
    queue.removeWhere((t) =>
        t.status == 'done' || t.status == 'failed' || (includingPending && t.status == 'queued'));
    notifyListeners();
  }

  /// 手动重试失败任务
  void retryFailed() {
    var any = false;
    for (final t in queue) {
      if (t.status == 'failed') {
        t.status = 'queued';
        t.progress = 0;
        t.error = '';
        any = true;
      }
    }
    if (any) {
      notifyListeners();
      if (!_running) _drain();
    }
  }

  /// 重试单个失败插图（按数据库 id）
  Future<void> retryOne(int illustrationId) async {
    final db = _requireDb();
    await (db.update(db.illustrations)..where((t) => t.id.equals(illustrationId)))
        .write(const IllustrationsCompanion(status: Value('pending'), error: Value('')));
    // 队列里可能没有该条目（历史遗留），补一条
    if (!queue.any((t) => t.illustrationId == illustrationId)) {
      final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(illustrationId))).getSingle();
      queue.add(GenTaskView(illustrationId: illustrationId, promptPreview: _preview(ill.prompt)));
    } else {
      for (final t in queue) {
        if (t.illustrationId == illustrationId && t.status == 'failed') {
          t.status = 'queued';
          t.progress = 0;
          t.error = '';
        }
      }
    }
    notifyListeners();
    if (!_running) _drain();
  }

  AppDatabase _requireDb() {
    final db = _db;
    if (db == null) {
      throw const GenerationException('数据库未初始化');
    }
    return db;
  }

  String _preview(String s) {
    final t = s.replaceAll('\n', ' ').trim();
    return t.length <= 48 ? t : '${t.substring(0, 48)}…';
  }

  String _hash(String s) {
    // FNV-1a 32bit：够用于锚点比对，避免引入 crypto 依赖
    var h = 0x811c9dc5;
    for (final code in s.runes) {
      h ^= code & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= (code >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
