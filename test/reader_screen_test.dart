import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/services/generation_service.dart';
import 'package:shengtushu/services/settings_service.dart';
import 'package:shengtushu/ui/reader_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'demoLayoutV1': true});
    await SettingsService.instance.init();
    db = AppDatabase.forTest(NativeDatabase.memory());
    GenerationService.instance.attachDb(db);
  });

  tearDown(() async => db.close());

  Future<int> seed({int count = 100, int lastParagraph = 0}) async {
    final id = await db.into(db.books).insert(BooksCompanion.insert(
      title: '测试书籍', format: 'txt', lastParagraph: Value(lastParagraph),
    ));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
      bookId: id, idx: 0, title: '第一章',
      content: [for (var i = 0; i < count; i++) '第$i段，这是用于排版测试的正文。'].join('\n'),
    ));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
      bookId: id, idx: 1, title: '第二章', content: '第二章正文',
    ));
    return id;
  }

  Future<void> waitForReader(WidgetTester tester) async {
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(PageView).evaluate().isNotEmpty &&
          find.text('排版中…').evaluate().isEmpty) {
        return;
      }
    }
    fail('阅读器未完成排版');
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('首批页面先显示，剩余分页继续；同长度正文更新可见', (tester) async {
    final id = await seed(count: 240);
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: id)));
    var early = false;
    for (var i = 0; i < 200; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(PageView).evaluate().isNotEmpty) {
        early = find.text('排版中…').evaluate().isNotEmpty;
        break;
      }
    }
    expect(early, isTrue);
    await waitForReader(tester);
    expect(tester.takeException(), isNull);
    final ch = await (db.select(db.chapters)..where((t) => t.idx.equals(0))).getSingle();
    await (db.update(db.chapters)..where((t) => t.id.equals(ch.id)))
        .write(ChaptersCompanion(content: Value(ch.content.replaceFirst('第0段', '新0段'))));
    await tester.pump();
    await waitForReader(tester);
    expect(find.textContaining('新0段'), findsWidgets);
    expect(find.textContaining('第0段'), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('长章恢复保持目标段落，切到下一章不保留旧文', (tester) async {
    final id = await seed(count: 240, lastParagraph: 150);
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: id)));
    await waitForReader(tester);
    final view = tester.widget<PageView>(find.byType(PageView));
    expect(view.controller!.page, greaterThan(0));
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('第一章').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('第二章'));
    await tester.pumpAndSettle();
    await waitForReader(tester);
    expect(find.text('第二章正文'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('滚动模式长章恢复在增量排版后保持目标位置', (tester) async {
    final id = await seed(count: 240, lastParagraph: 150);
    await SettingsService.instance.setPageMode('scroll');
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: id)));
    for (var i = 0; i < 400; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(ListView).evaluate().isNotEmpty &&
          find.text('排版中…').evaluate().isEmpty) {
        break;
      }
    }
    expect(find.text('排版中…'), findsNothing);
    await tester.pump(const Duration(milliseconds: 16));
    final target = find.text('第150段，这是用于排版测试的正文。');
    expect(target, findsOneWidget);
    final viewportTop = tester.getTopLeft(find.byType(ListView)).dy;
    expect(tester.getTopLeft(target).dy - viewportTop, lessThan(50));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('滚动模式复用流高度，空正文正常显示', (tester) async {
    final id = await seed(count: 0);
    await SettingsService.instance.setPageMode('scroll');
    await tester.pumpWidget(MaterialApp(home: ReaderScreen(db: db, bookId: id)));
    for (var i = 0; i < 80; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.byType(ListView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
