import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/services/generation_service.dart';
import 'package:shengtushu/services/settings_service.dart';
import 'package:shengtushu/ui/bookshelf_screen.dart';
import 'package:shengtushu/ui/reader_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('固定书库：书架、首批正文、排版和翻页性能', (tester) async {
    SharedPreferences.setMockInitialValues({'demoLayoutV1': true});
    await SettingsService.instance.init();
    final loader = FontLoader(kReaderFontFamily)
      ..addFont(rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf'));
    await loader.load();
    final db = AppDatabase.forTest(NativeDatabase.memory());
    GenerationService.instance.attachDb(db);
    final paragraphs = [
      for (var i = 0; i < 240; i++)
        '　　第$i段基准正文。${List.filled(8, '长河落日，山间微风吹过松林。少年翻开书页，继续阅读这段旅程。').join()}',
    ];
    await db.transaction(() async {
      for (var b = 0; b < 6; b++) {
        final id = await db.into(db.books).insert(
          BooksCompanion.insert(title: '基准书籍$b', format: 'txt'),
        );
        await db.batch((batch) {
          batch.insertAll(db.chapters, [
            for (var c = 0; c < 24; c++)
              ChaptersCompanion.insert(
                bookId: id, idx: c, title: '第$c章基准', content: paragraphs.join('\n'),
              ),
          ]);
        });
      }
    });
    final metrics = <String, Object>{'fixture': '6books-24chapters-240paragraphs-v1'};
    final clock = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(home: BookshelfScreen(db: db)));
    for (var i = 0; i < 1200; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (find.text('基准书籍0').evaluate().isNotEmpty &&
          find.text('第 1 章 · 4%').evaluate().isNotEmpty) {
        break;
      }
      await binding.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    }
    expect(find.text('基准书籍0'), findsOneWidget);
    metrics['bookshelfMs'] = clock.elapsedMilliseconds;
    metrics['rssAfterShelf'] = ProcessInfo.currentRss;
    clock.reset();
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: 1)));
    var firstReadable = -1;
    for (var i = 0; i < 2400; i++) {
      await tester.pump(const Duration(milliseconds: 10));
      if (firstReadable < 0 && find.byType(PageView).evaluate().isNotEmpty) {
        firstReadable = clock.elapsedMilliseconds;
      }
      if (firstReadable >= 0 && find.text('排版中…').evaluate().isEmpty) break;
      await binding.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 1)));
    }
    expect(find.byType(PageView), findsOneWidget);
    expect(find.text('排版中…'), findsNothing);
    metrics['firstReadableMs'] = firstReadable;
    metrics['layoutCompleteMs'] = clock.elapsedMilliseconds;
    metrics['rssAfterReader'] = ProcessInfo.currentRss;
    metrics['imageCacheBytes'] = PaintingBinding.instance.imageCache.currentSizeBytes;
    await binding.watchPerformance(() async {
      for (var i = 0; i < 12; i++) {
        await tester.drag(find.byType(PageView), const Offset(-350, 0));
        await tester.pump(const Duration(milliseconds: 350));
      }
    }, reportKey: 'pageTurns');
    debugPrint('PERF_RESULT ${jsonEncode(metrics)}');
    binding.reportData ??= {};
    binding.reportData!['readerMetrics'] = metrics;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await db.close();
  });
}
