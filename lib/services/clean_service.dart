// 文本清洗落库：预览命中 → 逐章重写 → 重锚定插图 → 删除被清空的章节
import 'package:drift/drift.dart' show OrderingTerm, Value;

import '../data/database.dart';
import 'chapter_editor.dart';
import 'text_cleaner.dart';

/// 单章清洗统计
class ChapterCleanStat {
  final int chapterId;
  final String title;
  final int index; // 章序号（0 基，按 idx 排序）
  final int hits; // 规则命中次数
  final int removed; // 删除字符数（含乱码与规则删除）
  final bool emptied; // 清洗后整章为空 → 将被删除

  const ChapterCleanStat({
    required this.chapterId,
    required this.title,
    required this.index,
    required this.hits,
    required this.removed,
    required this.emptied,
  });
}

class CleanPreview {
  final List<ChapterCleanStat> chapters;
  final int totalChars; // 全书正文字符数（占比警示用）
  final List<String> samples; // 规则命中片段（最多 3 条，供确认框展示）

  const CleanPreview({
    required this.chapters,
    required this.totalChars,
    this.samples = const [],
  });

  int get hits => chapters.fold(0, (a, b) => a + b.hits);
  int get removed => chapters.fold(0, (a, b) => a + b.removed);

  /// 受影响的章节
  List<ChapterCleanStat> get touched =>
      [for (final c in chapters) if (c.removed > 0 || c.emptied) c];

  /// 会被删除的空章节
  List<ChapterCleanStat> get emptiedChapters => [for (final c in chapters) if (c.emptied) c];

  /// 删除量占全书三成以上：预览里给红色警示
  bool get risky => totalChars > 0 && removed > totalChars * 0.3;

  /// 规则会把整本书清空（危险，禁止执行）
  bool get wipesBook => chapters.isNotEmpty && emptiedChapters.length == chapters.length;
}

class CleanApplyResult {
  final int changed; // 被重写的章节数
  final int removed; // 删除字符数
  final int deleted; // 删除的空章节数
  const CleanApplyResult({required this.changed, required this.removed, required this.deleted});

  bool get any => changed > 0 || deleted > 0;
}

class CleanService {
  CleanService(this.db);
  final AppDatabase db;

  Future<List<Chapter>> _chaptersOf(int bookId) {
    return (db.select(db.chapters)
          ..where((c) => c.bookId.equals(bookId))
          ..orderBy([(c) => OrderingTerm.asc(c.idx)]))
        .get();
  }

  Future<CleanPreview> preview(int bookId, CleanOptions o) async {
    final chapters = await _chaptersOf(bookId);
    final stats = <ChapterCleanStat>[];
    final samples = <String>[];
    final enabled = [for (final r in o.rules) if (r.enabled && r.pattern.trim().isNotEmpty) r];
    var total = 0;
    for (var i = 0; i < chapters.length; i++) {
      final c = chapters[i];
      total += c.content.length;
      final after = TextCleaner.cleanChapterContent(c.content, o);
      final delta = c.content.length - after.length;
      stats.add(ChapterCleanStat(
        chapterId: c.id,
        title: c.title,
        index: i,
        hits: TextCleaner.countHits(c.content, o.rules),
        removed: delta > 0 ? delta : 0,
        emptied: after.trim().isEmpty && c.content.trim().isNotEmpty,
      ));
      if (samples.length < 3) {
        for (final r in enabled) {
          samples.addAll(TextCleaner.previewRule(c.content, r.pattern).samples);
          if (samples.length >= 3) break;
        }
      }
    }
    return CleanPreview(
      chapters: stats,
      totalChars: total,
      samples: samples.length > 3 ? samples.sublist(0, 3) : samples,
    );
  }

  /// 执行清洗：逐章重写（插图按段落哈希重锚定），被整体清空的章节连插图一并删除。
  /// 图片文件不删（留在本书 images/ 目录，删书时统一清理），避免不可逆的文件删除。
  Future<CleanApplyResult> apply(int bookId, CleanOptions o) async {
    final chapters = await _chaptersOf(bookId);
    if (chapters.isEmpty) return const CleanApplyResult(changed: 0, removed: 0, deleted: 0);

    final cleaned = <int, String>{};
    var emptiedCount = 0;
    for (final c in chapters) {
      final after = TextCleaner.cleanChapterContent(c.content, o);
      cleaned[c.id] = after;
      if (after.trim().isEmpty && c.content.trim().isNotEmpty) emptiedCount++;
    }
    if (emptiedCount == chapters.length) {
      throw StateError('该规则会清空整本书，已中止');
    }

    var changed = 0;
    var removed = 0;
    var deleted = 0;
    await db.transaction(() async {
      var idx = 0;
      for (final c in chapters) {
        final after = cleaned[c.id]!;
        if (after.trim().isEmpty && c.content.trim().isNotEmpty) {
          await (db.delete(db.illustrations)..where((t) => t.chapterId.equals(c.id))).go();
          await (db.delete(db.chapters)..where((t) => t.id.equals(c.id))).go();
          deleted++;
          continue;
        }
        if (after != c.content) {
          await ChapterEditor.rewriteContent(db, c.id, after);
          changed++;
          final delta = c.content.length - after.length;
          if (delta > 0) removed += delta;
        }
        if (c.idx != idx) {
          await (db.update(db.chapters)..where((t) => t.id.equals(c.id)))
              .write(ChaptersCompanion(idx: Value(idx)));
        }
        idx++;
      }
      final book = await (db.select(db.books)..where((t) => t.id.equals(bookId))).getSingle();
      if (book.lastChapter > idx - 1) {
        await (db.update(db.books)..where((t) => t.id.equals(bookId)))
            .write(BooksCompanion(lastChapter: Value(idx - 1 < 0 ? 0 : idx - 1)));
      }
    });
    return CleanApplyResult(changed: changed, removed: removed, deleted: deleted);
  }
}
