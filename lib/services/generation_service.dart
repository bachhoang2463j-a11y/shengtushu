// 生图管线编排器：LLM 提炼 → insertions 入库（占位符）→ 顺序队列 → ComfyUI → 回填
// 流程移植自「生图助手 v45.3.1」独立生词流程（顺序队列 / 重试 / 占位符替换）。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/drift.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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
  String promptPreview;
  String status; // queued | running | done | failed
  double progress; // 0..1
  String error;
  bool useSecond; // 该任务用第二工作流生成（图片 ↻2 重生成分流）
  GenTaskView({
    required this.illustrationId,
    required this.promptPreview,
    this.status = 'queued',
    this.progress = 0,
    this.error = '',
    this.useSecond = false,
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

  /// illustrations.history 列是 JSON 数组字符串（旧→新），这里统一编解码
  static List<String> decodeHistory(String raw) {
    try {
      final l = jsonDecode(raw);
      return [if (l is List) for (final e in l) if (e is String) e];
    } catch (_) {
      return const [];
    }
  }

  static String encodeHistory(List<String> list) => jsonEncode(list);

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
    int anchorOffset = -1, // 插图锚点：段内字符偏移（-1 = 段末）
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
      await _createIllustration(book, chapter, globalIdx, ins.prompt, anchorOffset: anchorOffset);
      created++;
    }
    if (created == 0) {
      throw const GenerationException('LLM 未返回有效插图位置');
    }
    return created;
  }

  /// 定位选区末尾（忽略空白差异）：返回 (段落序号, 段内字符偏移)。
  /// 偏移含义：插图插在该段第 offset 个字符之后；找不到返回 (-1, -1)。
  /// [hintParagraph]：当前阅读位置附近的段落序号——短选区（如单字）可能命中多个段落，
  /// 从视口附近向两侧扩散搜索。跨段选区的尾部可能横跨段落边界，尾部逐步截短重试。
  static (int, int) locateSelectionEnd(List<String> paras, String selection, {int hintParagraph = 0}) {
    String strip(String s) => s.replaceAll(RegExp(r'\s+'), '');
    final target = strip(selection);
    if (target.isEmpty || paras.isEmpty) return (-1, -1);
    final clampedHint = hintParagraph.clamp(0, paras.length - 1);
    var maxTail = target.length < 16 ? target.length : 16;
    for (var l = maxTail; l >= 1; l--) {
      final t = target.substring(target.length - l);
      for (var dist = 0; dist < paras.length; dist++) {
        for (final i in {clampedHint - dist, clampedHint + dist}) {
          if (i < 0 || i >= paras.length) continue;
          final idx = strip(paras[i]).indexOf(t);
          if (idx >= 0) return (i, _mapStrippedToOriginal(paras[i], idx + t.length));
        }
      }
    }
    return (-1, -1);
  }

  /// 把「去空白后的字符序号」映射回原文字符偏移
  static int _mapStrippedToOriginal(String original, int strippedEnd) {
    var count = 0;
    for (var i = 0; i < original.length; i++) {
      if (RegExp(r'\s').hasMatch(original[i])) continue;
      count++;
      if (count == strippedEnd) return i + 1;
    }
    return original.length;
  }

  /// 选中文段生图：只把所选文字发给 LLM，插图精确插在选区末尾（支持段中）。
  /// [endParagraphIndex] / [endCharOffset] 来自 locateSelectionEnd。
  Future<int> generateSelection({
    required Book book,
    required Chapter chapter,
    required String selectionText,
    required int endParagraphIndex,
    required int endCharOffset,
    required List<String> history,
  }) async {
    final paras = chapter.content.split('\n');
    if (endParagraphIndex < 0 || endParagraphIndex >= paras.length) {
      throw const GenerationException('插入位置越界');
    }
    final trimmed = selectionText.trim();
    if (trimmed.isEmpty) {
      throw const GenerationException('选中文本为空');
    }
    return generateBatch(
      book: book,
      chapter: chapter,
      pageParagraphs: [trimmed],
      firstParagraphIndex: endParagraphIndex,
      history: history,
      anchorOffset: endCharOffset,
    );
  }

  /// 单段生图：锚定在该段末尾（等效于选中整段）
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

  Future<int> _createIllustration(Book book, Chapter chapter, int globalIdx, String prompt,
      {int anchorOffset = -1}) async {
    final db = _requireDb();
    final paras = chapter.content.split('\n');
    final hash = _hash(paras[globalIdx]);
    // 去重：同章同段同位置（±10 字符）已有占位符 → 复用并更新提示词，防止重复生图
    final existing = await (db.select(db.illustrations)
          ..where((t) => t.chapterId.equals(chapter.id))
          ..where((t) => t.afterParagraph.equals(globalIdx)))
        .get();
    for (final e in existing) {
      final sameSpot = (e.anchorOffset < 0 && anchorOffset < 0) ||
          (e.anchorOffset >= 0 &&
              anchorOffset >= 0 &&
              (e.anchorOffset - anchorOffset).abs() <= 10);
      if (sameSpot) {
        debugPrint('[生图] 第 ${globalIdx + 1} 段已有占位符 #${e.id}，复用并更新提示词');
        await (db.update(db.illustrations)..where((t) => t.id.equals(e.id))).write(
          IllustrationsCompanion(
            prompt: Value(prompt),
            status: const Value('pending'),
            error: const Value(''),
          ),
        );
        _ensureQueued(e.id, promptPreview: _preview(prompt));
        notifyListeners();
        if (!_running) _drain();
        return e.id;
      }
    }
    final id = await db.into(db.illustrations).insert(IllustrationsCompanion.insert(
      bookId: book.id,
      chapterId: chapter.id,
      afterParagraph: globalIdx,
      anchorHash: hash,
      prompt: prompt,
      anchorOffset: Value(anchorOffset),
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

    // 第二工作流重生成：任务级分流。未设置时直接失败，不走重试（配置问题重试无意义）
    Workflow? wfOverride;
    if (task.useSecond) {
      final secondRows = await (db.select(db.workflows)..where((t) => t.isSecond.equals(true))).get();
      if (secondRows.isEmpty) {
        const msg = '未设置第二工作流：请到 设置 → 工作流管理，点击某个工作流的「第二」按钮';
        debugPrint('[生图] $msg');
        task.status = 'failed';
        task.error = msg;
        await (db.update(db.illustrations)..where((t) => t.id.equals(task.illustrationId)))
            .write(const IllustrationsCompanion(status: Value('failed'), error: Value(msg)));
        notifyListeners();
        return;
      }
      wfOverride = secondRows.first;
    }

    for (var attempt = 0; attempt <= settings.genRetry; attempt++) {
      try {
        final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(task.illustrationId))).getSingle();
        final Workflow wf;
        if (wfOverride != null) {
          wf = wfOverride;
        } else {
          final wfRows = await (db.select(db.workflows)..where((t) => t.isActive.equals(true))).get();
          if (wfRows.isEmpty) {
            throw const GenerationException('没有启用的 ComfyUI 工作流，请到设置里导入并启用');
          }
          wf = wfRows.first;
        }
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

        // 本地用唯一文件名保存：避免沿用 ComfyUI 端同名输出覆盖旧图文件，
        // 否则历史版本里记录的旧路径会全部指向「最后一张」的内容
        final savePath = await ImageStore.instance.newPath(ill.bookId, 'png');
        var path = await _comfy.generate(
          baseUrl: settings.comfyUrl,
          workflow: workflowJson,
          mapping: mapping,
          positive: ill.prompt,
          width: ill.imgWidth,
          height: ill.imgHeight,
          batch: 1,
          autoRandomSeed: settings.autoRandomSeed,
          saveDir: savePath.substring(0, savePath.lastIndexOf(Platform.pathSeparator)),
          saveFile: savePath,
          onProgress: (p) {
            if (p.ratio != null) task.progress = p.ratio!;
            notifyListeners();
          },
        );

        // 读实际尺寸回填，并转码为 WebP（q90 视觉无损，体积约为 PNG 的 1/5）
        int w = ill.imgWidth, h = ill.imgHeight;
        try {
          final raw = await File(path).readAsBytes();
          final codec = await ui.instantiateImageCodec(raw);
          final frame = await codec.getNextFrame();
          w = frame.image.width;
          h = frame.image.height;
          frame.image.dispose();
          codec.dispose();
          final webp = await FlutterImageCompress.compressWithList(
            raw,
            quality: 90,
            format: CompressFormat.webp,
            minWidth: w,
            minHeight: h,
          );
          if (webp.isNotEmpty && webp.length < raw.length) {
            final webpPath = await ImageStore.instance.newPath(ill.bookId, 'webp');
            await File(webpPath).writeAsBytes(webp);
            try {
              await File(path).delete();
            } catch (_) {}
            path = webpPath;
            debugPrint('[生图] 已转码 WebP：${raw.length ~/ 1024}KB → ${webp.length ~/ 1024}KB');
          }
        } catch (_) {}

        // 旧图不删，移入历史版本；新图成为当前展示图（每次生成必记录一张）
        final old = ill.imagePath;
        final hist = [...decodeHistory(ill.history)];
        if (old != null && old.isNotEmpty && old != path) hist.add(old);
        await (db.update(db.illustrations)..where((t) => t.id.equals(task.illustrationId))).write(
          IllustrationsCompanion(
            status: const Value('done'),
            imagePath: Value(path),
            history: Value(encodeHistory(hist)),
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

  /// 重试单个失败插图（按数据库 id）；[useSecond] 为 true 时用第二工作流
  Future<void> retryOne(int illustrationId, {bool useSecond = false}) async {
    final db = _requireDb();
    await (db.update(db.illustrations)..where((t) => t.id.equals(illustrationId)))
        .write(const IllustrationsCompanion(status: Value('pending'), error: Value('')));
    _ensureQueued(illustrationId, useSecond: useSecond);
    notifyListeners();
    if (!_running) _drain();
  }

  /// 修改提示词并重新生图
  Future<void> updatePromptAndRegenerate(int illustrationId, String prompt) async {
    final db = _requireDb();
    await (db.update(db.illustrations)..where((t) => t.id.equals(illustrationId))).write(
      IllustrationsCompanion(
        prompt: Value(prompt.trim()),
        status: const Value('pending'),
        error: const Value(''),
      ),
    );
    _ensureQueued(illustrationId, promptPreview: _preview(prompt));
    notifyListeners();
    if (!_running) _drain();
  }

  /// 仅重新生图（保持原提示词）；[useSecond] 为 true 时用第二工作流（图片 ↻2 入口）
  Future<void> regenerate(int illustrationId, {bool useSecond = false}) =>
      retryOne(illustrationId, useSecond: useSecond);

  /// 删除插图（含当前图与全部历史版本图片）
  Future<void> deleteIllustration(int illustrationId) async {
    final db = _requireDb();
    final rows = await (db.select(db.illustrations)..where((t) => t.id.equals(illustrationId))).get();
    for (final ill in rows) {
      final files = [
        if (ill.imagePath != null && ill.imagePath!.isNotEmpty) ill.imagePath!,
        ...decodeHistory(ill.history),
      ];
      for (final p in files) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    await (db.delete(db.illustrations)..where((t) => t.id.equals(illustrationId))).go();
    queue.removeWhere((t) => t.illustrationId == illustrationId);
    notifyListeners();
  }

  /// 批量删除指定插图的若干张图片（当前图或历史图），用于图片管理的多选删除。
  /// 当前图被删时提升最近一张历史为当前图；没有历史则回到「待生成」。
  Future<void> deleteIllustrationImages(Map<int, List<String>> byIll) async {
    final db = _requireDb();
    for (final entry in byIll.entries) {
      final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(entry.key)))
          .getSingleOrNull();
      if (ill == null) continue;
      final paths = entry.value.toSet();
      for (final p in paths) {
        try {
          final f = File(p);
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
      final hist = decodeHistory(ill.history)..removeWhere(paths.contains);
      if (ill.imagePath != null && paths.contains(ill.imagePath)) {
        if (hist.isNotEmpty) {
          final last = hist.removeLast();
          await (db.update(db.illustrations)..where((t) => t.id.equals(entry.key))).write(
            IllustrationsCompanion(imagePath: Value(last), history: Value(encodeHistory(hist))),
          );
        } else {
          await (db.update(db.illustrations)..where((t) => t.id.equals(entry.key))).write(
            const IllustrationsCompanion(
              imagePath: Value(null),
              status: Value('pending'),
              history: Value('[]'),
              error: Value(''),
            ),
          );
        }
      } else {
        await (db.update(db.illustrations)..where((t) => t.id.equals(entry.key)))
            .write(IllustrationsCompanion(history: Value(encodeHistory(hist))));
      }
    }
    notifyListeners();
  }

  /// 压缩一本书全部插图中的 PNG 为 WebP（当前图与历史版本一起处理）。
  /// 返回节省的总字节数；单张失败自动跳过保留原样。
  Future<int> compressBookImages(int bookId) async {
    final db = _requireDb();
    final rows = await (db.select(db.illustrations)..where((t) => t.bookId.equals(bookId))).get();
    var saved = 0;
    for (final ill in rows) {
      final hist = decodeHistory(ill.history);
      final newHist = <String>[];
      var changed = false;
      for (final p in hist) {
        final r = await _compressOnePng(p);
        if (r != null) {
          newHist.add(r.$1);
          saved += r.$2;
          changed = true;
        } else {
          newHist.add(p);
        }
      }
      String? newCur;
      if (ill.imagePath != null && ill.imagePath!.isNotEmpty) {
        final r = await _compressOnePng(ill.imagePath!);
        if (r != null) {
          newCur = r.$1;
          saved += r.$2;
          changed = true;
        }
      }
      if (changed) {
        await (db.update(db.illustrations)..where((t) => t.id.equals(ill.id))).write(
          IllustrationsCompanion(
            imagePath: newCur == null ? const Value.absent() : Value(newCur),
            history: Value(encodeHistory(newHist)),
          ),
        );
      }
    }
    notifyListeners();
    return saved;
  }

  /// 单张 PNG → WebP；成功返回 (新路径, 节省字节)，失败/不划算返回 null
  Future<(String, int)?> _compressOnePng(String p) async {
    if (!p.toLowerCase().endsWith('.png')) return null;
    try {
      final f = File(p);
      if (!await f.exists()) return null;
      final raw = await f.readAsBytes();
      final codec = await ui.instantiateImageCodec(raw);
      final frame = await codec.getNextFrame();
      final w = frame.image.width;
      final h = frame.image.height;
      frame.image.dispose();
      codec.dispose();
      final webp = await FlutterImageCompress.compressWithList(
        raw,
        quality: 90,
        format: CompressFormat.webp,
        minWidth: w,
        minHeight: h,
      );
      if (webp.isEmpty || webp.length >= raw.length) return null;
      final np = '${p.substring(0, p.lastIndexOf('.'))}.webp';
      await File(np).writeAsBytes(webp);
      await f.delete();
      return (np, raw.length - webp.length);
    } catch (_) {
      return null;
    }
  }

  void _ensureQueued(int illustrationId, {String? promptPreview, bool useSecond = false}) {
    if (queue.any((t) => t.illustrationId == illustrationId)) {
      for (final t in queue) {
        if (t.illustrationId == illustrationId) {
          t.status = 'queued';
          t.progress = 0;
          t.error = '';
          t.useSecond = useSecond;
          if (promptPreview != null) t.promptPreview = promptPreview;
        }
      }
      return;
    }
    queue.add(GenTaskView(
      illustrationId: illustrationId,
      promptPreview: promptPreview ?? '',
      status: 'queued',
      useSecond: useSecond,
    ));
    // 没有 preview 时从库里补一条
    if (promptPreview == null) {
      final db = _requireDb();
      (db.select(db.illustrations)..where((t) => t.id.equals(illustrationId))).getSingle().then((ill) {
        for (final t in queue) {
          if (t.illustrationId == illustrationId) t.promptPreview = _preview(ill.prompt);
        }
        notifyListeners();
      });
    }
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
