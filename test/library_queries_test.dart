import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/data/library_queries.dart';
import 'package:shengtushu/services/library_activity.dart';

void main() {
  test('轻量目录与独立聚合：阅读进度和正文改动不重复发送计数', () async {
    final db = AppDatabase.forTest(NativeDatabase.memory());
    addTearDown(db.close);
    final book = await db.into(db.books).insert(BooksCompanion.insert(title: '测试', format: 'txt'));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
      bookId: book, idx: 1, title: '第二章', content: '乙',
    ));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
      bookId: book, idx: 0, title: '第一章', content: '甲',
    ));
    final queries = LibraryQueries(db);
    expect((await queries.chapterIndex(book)).map((c) => c.title), ['第一章', '第二章']);
    final received = <Map<int, int>>[];
    final ready = Completer<void>();
    final next = Completer<void>();
    final sub = queries.watchChapterCounts().listen((counts) {
      received.add(counts);
      if (!ready.isCompleted) ready.complete();
      if (counts[book] == 3 && !next.isCompleted) next.complete();
    });
    addTearDown(sub.cancel);
    await ready.future.timeout(const Duration(seconds: 3));
    await (db.update(db.books)..where((t) => t.id.equals(book)))
        .write(const BooksCompanion(lastParagraph: Value(4)));
    await db.update(db.chapters).write(const ChaptersCompanion(content: Value('新正文')));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(received, [{book: 2}]);
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
      bookId: book, idx: 2, title: '第三章', content: '',
    ));
    await next.future.timeout(const Duration(seconds: 3));
    expect(received, [{book: 2}, {book: 3}]);
  });

  test('书库传输互斥：等待写入结束，取消或失败后释放', () async {
    final activity = LibraryActivity.instance;
    final pending = Completer<void>();
    final writing = activity.write(() => pending.future);
    await expectLater(activity.transfer(() async {}), throwsA(isA<LibraryBusyException>()));
    pending.complete();
    await writing;
    await activity.transfer(() async {
      expect(activity.isTransferring, isTrue);
      await expectLater(activity.write(() async {}), throwsA(isA<LibraryBusyException>()));
    });
    await expectLater(activity.transfer(() async => throw StateError('failure')), throwsStateError);
    expect(activity.isTransferring, isFalse);
    expect(await activity.write(() async => 4), 4);
  });
}
