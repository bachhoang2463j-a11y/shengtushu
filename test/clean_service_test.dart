// CleanService 集成测试：内存 Drift，验证清洗落库、插图重锚定与空章删除
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/services/chapter_editor.dart';
import 'package:shengtushu/services/clean_service.dart';
import 'package:shengtushu/services/text_cleaner.dart';

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTest(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<int> insertBook({int lastChapter = 0}) => db.into(db.books).insert(
      BooksCompanion.insert(title: '测试之书', format: 'txt', lastChapter: Value(lastChapter)));

  Future<int> insertChapter(int bookId, int idx, String title, String content) =>
      db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: bookId, idx: idx, title: title, content: content));

  Future<int> insertIll(int bookId, int chapterId, int para, String paraText) =>
      db.into(db.illustrations).insert(IllustrationsCompanion.insert(
            bookId: bookId,
            chapterId: chapterId,
            afterParagraph: para,
            anchorHash: ChapterEditor.hash(paraText),
            prompt: 'p',
          ));

  final junkRule = CleanRule(name: '签名', pattern: r'^\s*签名[\s\S]*?回复倒序\s*$');

  test('规则命中：删掉整块并重锚定其后段落的插图', () async {
    final bookId = await insertBook();
    final chId = await insertChapter(
        bookId, 0, '第一章', '　　A段。\n　　签名\n　　广告词\n　　回复倒序\n　　B段。');
    final illId = await insertIll(bookId, chId, 4, '　　B段。');

    final svc = CleanService(db);
    final o = CleanOptions(stripNoise: false, stripMojibake: false, rules: [junkRule]);
    final preview = await svc.preview(bookId, o);
    expect(preview.hits, 1);
    expect(preview.touched.length, 1);
    expect(preview.emptiedChapters, isEmpty);

    final r = await svc.apply(bookId, o);
    expect(r.changed, 1);
    expect(r.deleted, 0);

    final ch = await (db.select(db.chapters)..where((t) => t.id.equals(chId))).getSingle();
    expect(ch.content, '　　A段。\n　　B段。');
    final ill = await (db.select(db.illustrations)..where((t) => t.id.equals(illId))).getSingle();
    expect(ill.afterParagraph, 1);
  });

  test('整章清空：章节与插图记录被删除，idx 重排，lastChapter 夹紧', () async {
    final bookId = await insertBook(lastChapter: 2);
    await insertChapter(bookId, 0, '正文', '　　A段。');
    final junkChId = await insertChapter(bookId, 1, '广告页', '　　签名\n　　广告词\n　　回复倒序');
    await insertIll(bookId, junkChId, 0, '　　签名');
    await insertChapter(bookId, 2, '后记', '　　C段。');

    final svc = CleanService(db);
    final o = CleanOptions(stripNoise: false, stripMojibake: false, rules: [junkRule]);
    final preview = await svc.preview(bookId, o);
    expect(preview.emptiedChapters.length, 1);

    final r = await svc.apply(bookId, o);
    expect(r.deleted, 1);

    final chapters = await (db.select(db.chapters)
          ..where((t) => t.bookId.equals(bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
        .get();
    expect(chapters.length, 2);
    expect([for (final c in chapters) c.idx], [0, 1]);
    expect([for (final c in chapters) c.title], ['正文', '后记']);
    final ills = await (db.select(db.illustrations)..where((t) => t.bookId.equals(bookId))).get();
    expect(ills, isEmpty);
    final book = await (db.select(db.books)..where((t) => t.id.equals(bookId))).getSingle();
    expect(book.lastChapter, 1);
  });

  test('规则会清空整本书：拒绝执行且不改动数据', () async {
    final bookId = await insertBook();
    final chId = await insertChapter(bookId, 0, '第一章', '　　签名\n　　广告词\n　　回复倒序');

    final svc = CleanService(db);
    final o = CleanOptions(stripNoise: false, stripMojibake: false, rules: [junkRule]);
    expect((await svc.preview(bookId, o)).wipesBook, isTrue);
    await expectLater(svc.apply(bookId, o), throwsStateError);

    final ch = await (db.select(db.chapters)..where((t) => t.id.equals(chId))).getSingle();
    expect(ch.content, '　　签名\n　　广告词\n　　回复倒序');
  });

  test('去乱码：碎片段被删除，正常段落保留', () async {
    final bookId = await insertBook();
    final chId = await insertChapter(
        bookId, 0, '第一章', '　　z u E w9 c w I8 a\n　　张三走进房间锟斤拷。');

    final svc = CleanService(db);
    final r = await svc.apply(bookId, const CleanOptions());
    expect(r.changed, 1);
    final ch = await (db.select(db.chapters)..where((t) => t.id.equals(chId))).getSingle();
    expect(ch.content, '　　张三走进房间。');
  });
}
