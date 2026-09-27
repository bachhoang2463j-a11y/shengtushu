import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show mapEquals;

import 'database.dart';

typedef ChapterEntry = ({int id, int idx, String title});

class LibraryQueries {
  final AppDatabase db;
  LibraryQueries(this.db);

  Future<List<ChapterEntry>> chapterIndex(int bookId) async {
    final t = db.chapters;
    final rows = await (db.selectOnly(t)
          ..addColumns([t.id, t.idx, t.title])
          ..where(t.bookId.equals(bookId))
          ..orderBy([OrderingTerm.asc(t.idx)]))
        .get();
    return [
      for (final row in rows)
        (id: row.read(t.id)!, idx: row.read(t.idx)!, title: row.read(t.title)!),
    ];
  }

  Stream<Map<int, int>> watchChapterCounts() {
    final t = db.chapters;
    final count = t.id.count();
    return (db.selectOnly(t)
          ..addColumns([t.bookId, count])
          ..groupBy([t.bookId]))
        .watch()
        .map((rows) => {for (final row in rows) row.read(t.bookId)!: row.read(count)!})
        .distinct(mapEquals);
  }

  Stream<Map<int, int>> watchIllustrationCounts() {
    final t = db.illustrations;
    final count = t.id.count();
    return (db.selectOnly(t)
          ..addColumns([t.bookId, count])
          ..groupBy([t.bookId]))
        .watch()
        .map((rows) => {for (final row in rows) row.read(t.bookId)!: row.read(count)!})
        .distinct(mapEquals);
  }
}
