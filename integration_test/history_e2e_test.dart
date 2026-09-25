// 端到端回归（跑在模拟器/真机上）：生图管线全链路——LLM 提炼 → 占位符 → 队列 → ComfyUI → 回写。
// 验证用户反馈的核心问题：每次重新生图都必须在 history 里记录一张新图（逐张记录、不互相覆盖）。
// 依赖：本文件内嵌的 mini mock（LLM + ComfyUI，随机端口），数据库用内存库，不触碰真实数据。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/ui/image_viewer_screen.dart';
import 'package:shengtushu/ui/reader_screen.dart';
import 'package:shengtushu/services/default_workflow.dart';
import 'package:shengtushu/services/generation_service.dart';
import 'package:shengtushu/services/settings_service.dart';

/// mini mock：OpenAI 兼容 LLM + ComfyUI；每次生成返回不同字节（编号染色）
class MiniMock {
  HttpServer? _server;
  final List<int> seeds = [];
  final List<String> prompts = [];
  int _pid = 0;

  String get base => 'http://127.0.0.1:${_server!.port}';

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen(_handle);
  }

  Future<void> stop() async => _server?.close(force: true);

  Future<void> _handle(HttpRequest req) async {
    final path = req.uri.path;
    try {
      if (req.method == 'GET' && path == '/system_stats') {
        return _json(req, {'system': {'comfyui_version': 'mock'}});
      }
      if (req.method == 'GET' && path.startsWith('/history/')) {
        final pid = path.split('/').last;
        return _json(req, {
          pid: {
            'status': {'status_str': 'success', 'completed': true},
            'outputs': {'18': {'images': [
              {'filename': 'mock_$pid.png', 'subfolder': '', 'type': 'output'},
            ]}},
          },
        });
      }
      if (req.method == 'GET' && path.startsWith('/view')) {
        // 文件名含任务号 → 每次任务内容不同（便于断言互异）
        final n = int.tryParse(req.uri.queryParameters['filename']?.replaceAll(RegExp(r'\D'), '') ?? '') ?? 0;
        req.response.headers.contentType = ContentType.binary;
        await req.response.addStream(Stream.value(utf8.encode('fake-image-bytes-$n')));
        await req.response.close();
        return;
      }
      if (req.method == 'POST' && path == '/prompt') {
        final body = jsonDecode(await utf8.decodeStream(req)) as Map<String, dynamic>;
        final wf = (body['prompt'] ?? body) as Map<String, dynamic>;
        // 抓取 KSampler 种子，供断言「每次随机」
        outer:
        for (final node in wf.values) {
          if (node is Map && node['class_type'].toString().toLowerCase().contains('sampler')) {
            final inputs = node['inputs'];
            if (inputs is Map && inputs['seed'] != null) {
              seeds.add((inputs['seed'] as num).toInt());
              break outer;
            }
          }
        }
        _pid++;
        return _json(req, {'prompt_id': 'mock-$_pid', 'node_errors': null});
      }
      if (req.method == 'POST' && path.endsWith('/chat/completions')) {
        return _json(req, {'choices': [
          {'message': {'role': 'assistant', 'content':
              '分析：测试\n```json\n{"insertions": [{"after_paragraph": 1, '
              '"prompt": "mock prompt"}]}\n```'},
          }],
        });
      }
      req.response.statusCode = 404;
      await req.response.close();
    } catch (_) {
      try {
        req.response.statusCode = 500;
        await req.response.close();
      } catch (_) {}
    }
  }

  void _json(HttpRequest req, Object obj) {
    req.response.headers.contentType = ContentType.json;
    req.response.write(jsonEncode(obj));
    req.response.close();
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late MiniMock mock;
  late Book book;
  late Chapter chapter;
  Map<String, Object>? savedPrefs;
  String? savedPageMode;

  Future<void> waitUntilIdle({int timeoutSec = 30}) async {
    final gen = GenerationService.instance;
    final deadline = DateTime.now().add(Duration(seconds: timeoutSec));
    while (gen.isBusy && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // 驱动测试环境的事件循环，让 socket/IO futures 走完
      await binding.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 50)));
    }
    expect(gen.isBusy, isFalse, reason: '生成队列在 ${timeoutSec}s 内未排空');
  }

  setUpAll(() async {
    mock = MiniMock();
    await mock.start();
    // 保存用户设置，测试结束后恢复（integration 跑在真实沙盒里）
    await SettingsService.instance.init();
    savedPrefs = {
      'llm': SettingsService.instance.llm.toJson(),
      'comfyUrl': SettingsService.instance.comfyUrl,
    };
    savedPageMode = SettingsService.instance.pageMode;
    final llm = SettingsService.instance.llm..baseUrl = '${mock.base}/v1';
    await SettingsService.instance.setLlm(llm);
    await SettingsService.instance.setComfyUrl(mock.base);
  });

  tearDownAll(() async {
    // 恢复用户设置
    if (savedPrefs != null) {
      final llm = LlmConfig.fromJson(savedPrefs!['llm'] as Map<String, dynamic>);
      await SettingsService.instance.setLlm(llm);
      await SettingsService.instance.setComfyUrl(savedPrefs!['comfyUrl'] as String);
      await SettingsService.instance.setPageMode(savedPageMode!);
    }
    await mock.stop();
    await db.close();
  });

  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    GenerationService.instance.attachDb(db);
    GenerationService.instance.queue.clear();
    await loadDefaultWorkflow(db);
    final id = await db.into(db.books).insert(BooksCompanion.insert(
          title: 'e2e-history',
          format: 'txt',
        ));
    book = await (db.select(db.books)..where((t) => t.id.equals(id))).getSingle();
    final chapterId = await db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: id,
          idx: 0,
          title: '第一章',
          content: [for (var i = 0; i < 20; i++) '　　第 $i 段测试正文。'].join('\n'),
        ));
    chapter = await (db.select(db.chapters)..where((t) => t.id.equals(chapterId))).getSingle();
  });

  test('重新生图 3 次：history 逐张记录、路径与内容互异、当前图为最新', () async {
    final gen = GenerationService.instance;
    final created = await gen.generateSelection(
      book: book,
      chapter: chapter,
      selectionText: '　　第 1 段测试正文。',
      endParagraphIndex: 1,
      endCharOffset: -1,
      history: const [],
    );
    expect(created, 1);
    await waitUntilIdle();

    final ids = await db.select(db.illustrations).get();
    expect(ids, hasLength(1));
    final ill0 = ids.single;
    expect(ill0.status, 'done');
    expect(ill0.imagePath, isNotNull);
    final firstBytes = await File(ill0.imagePath!).readAsBytes();

    // 重新生图 ×2（用户操作：长按 → 仅重新生图）
    await gen.regenerate(ill0.id);
    await waitUntilIdle();
    await gen.regenerate(ill0.id);
    await waitUntilIdle();

    final after = await (db.select(db.illustrations)..where((t) => t.id.equals(ill0.id))).getSingle();
    expect(after.status, 'done');
    // 当前图 + 2 张历史 = 3 张路径
    final hist = GenerationService.decodeHistory(after.history);
    expect(hist, hasLength(2), reason: '重新生图 2 次，历史必须逐张记录 2 张');
    final paths = [...hist, after.imagePath!];
    expect(paths.toSet(), hasLength(3), reason: '三条路径必须互不相同（不能同名覆盖）');
    for (final p in paths) {
      expect(File(p).existsSync(), isTrue, reason: '文件必须真实存在：$p');
    }
    // 当前图必须是最新生成的那张（不在历史里）
    expect(hist.contains(after.imagePath), isFalse);
    // 三份文件内容互异（mock 按任务编号染色）
    final b2 = await File(paths[0]).readAsBytes();
    final b3 = await File(paths[1]).readAsBytes();
    final b1new = await File(after.imagePath!).readAsBytes();
    expect(b2, isNot(equals(b3)));
    expect(b2, isNot(equals(b1new)));
    // 第一次生成的旧图内容应已归档进历史（路径[0] 内容 == 首图内容）
    expect(b2, equals(firstBytes), reason: '历史[0] 应是第一次生成的旧图');
    // 每次生成种子必须不同
    expect(mock.seeds, hasLength(3));
    expect(mock.seeds.toSet(), hasLength(3), reason: '种子必须每次随机');
  });

  testWidgets('阅读器渲染层：左右点按切换历史版本时显示的图片真实变化', (tester) async {
    final gen = GenerationService.instance;
    await gen.generateSelection(
      book: book,
      chapter: chapter,
      selectionText: '　　第 1 段测试正文。',
      endParagraphIndex: 1,
      endCharOffset: -1,
      history: const [],
    );
    await waitUntilIdle();
    await gen.regenerate(1);
    await waitUntilIdle();
    final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(1))).getSingle();
    final hist = GenerationService.decodeHistory(ill.history);
    expect(hist, hasLength(1));
    final paths = [...hist, ill.imagePath!];

    // 固定滚动模式：page 模式下测试表面首屏恰好无插图，无法断言
    await SettingsService.instance.setPageMode('scroll');
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: book.id)));
    Image imageOf() => tester.widget<Image>(find.byType(Image).first);
    // 等流式排版与图片 widget 出现
    for (var i = 0; i < 30; i++) {
      await binding.runAsync(() async => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      if (find.byType(Image).evaluate().isNotEmpty) break;
    }
    expect(find.byType(Image), findsOneWidget);
    // 初始显示最新一张
    expect((imageOf().image as FileImage).file.path, paths[1]);

    final gestureFinder = find.byKey(const ValueKey('ill-gesture-1'));
    expect(gestureFinder, findsOneWidget);
    final bounds = tester.getRect(gestureFinder);

    // 左 10% 点按 → 切到更旧的历史图
    await tester.tapAt(bounds.centerLeft + Offset(bounds.width * 0.1, 0));
    await tester.pump();
    expect((imageOf().image as FileImage).file.path, paths[0], reason: '左点应显示历史图');

    // 右 10% 点按 → 切回最新
    await tester.tapAt(bounds.centerRight - Offset(bounds.width * 0.1, 0));
    await tester.pump();
    expect((imageOf().image as FileImage).file.path, paths[1], reason: '右点应切回最新图');

    // 中间点按 → 打开大图查看器
    await tester.tap(find.byKey(const ValueKey('ill-gesture-1')));
    await tester.pumpAndSettle();
    expect(find.byType(ImageViewerScreen), findsOneWidget);
    expect(find.text('插图'), findsOneWidget);
  });

  test('多选删除：删历史图与当前图，当前图被删时提升最近历史', () async {
    final gen = GenerationService.instance;
    await gen.generateSelection(
      book: book,
      chapter: chapter,
      selectionText: '　　第 1 段测试正文。',
      endParagraphIndex: 1,
      endCharOffset: -1,
      history: const [],
    );
    await waitUntilIdle();
    var ill = (await db.select(db.illustrations).get()).single;
    await gen.regenerate(ill.id);
    await waitUntilIdle();
    await gen.regenerate(ill.id);
    await waitUntilIdle();
    ill = await (db.select(db.illustrations)..where((t) => t.id.equals(ill.id))).getSingle();
    final hist = GenerationService.decodeHistory(ill.history);
    expect(hist, hasLength(2));

    // 删一张历史图：文件消失、历史减一
    await gen.deleteIllustrationImages({ill.id: [hist.first]});
    expect(File(hist.first).existsSync(), isFalse);
    ill = await (db.select(db.illustrations)..where((t) => t.id.equals(ill.id))).getSingle();
    expect(GenerationService.decodeHistory(ill.history), hasLength(1));
    expect(ill.imagePath, isNotNull);

    // 删当前图：最近一张历史提升为当前图
    final promoted = GenerationService.decodeHistory(ill.history).single;
    await gen.deleteIllustrationImages({ill.id: [ill.imagePath!]});
    ill = await (db.select(db.illustrations)..where((t) => t.id.equals(ill.id))).getSingle();
    expect(ill.imagePath, promoted);
    expect(File(ill.imagePath!).existsSync(), isTrue);
    expect(GenerationService.decodeHistory(ill.history), isEmpty);

    // 再删当前图（无历史）：回到待生成
    await gen.deleteIllustrationImages({ill.id: [ill.imagePath!]});
    ill = await (db.select(db.illustrations)..where((t) => t.id.equals(ill.id))).getSingle();
    expect(ill.imagePath, isNull);
    expect(ill.status, 'pending');
  });
}
