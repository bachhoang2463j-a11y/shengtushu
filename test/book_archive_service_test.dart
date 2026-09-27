// BookArchiveService 集成测试：内存 Drift + 临时目录，不触碰真实书库
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/services/book_archive_service.dart';

void main() {
  late AppDatabase db;
  late Directory imagesRoot;
  late Directory tempRoot;
  late BookArchiveService service;

  setUp(() async {
    db = AppDatabase.forTest(NativeDatabase.memory());
    imagesRoot = await Directory.systemTemp.createTemp('bt_images_');
    tempRoot = await Directory.systemTemp.createTemp('bt_temp_');
    service = BookArchiveService(db, imagesRoot: imagesRoot, temporaryRoot: tempRoot);
  });

  tearDown(() async {
    await db.close();
    if (await imagesRoot.exists()) await imagesRoot.delete(recursive: true);
    if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
  });

  // ---------- 夹具 ----------

  /// 建书：2 章（含空章），1 张当前图 + 2 张历史图
  Future<int> seedBook() async {
    final bookId = await db.into(db.books).insert(BooksCompanion.insert(
          title: '测试之书',
          author: const Value('作者甲'),
          format: 'txt',
          lore: const Value('世界观设定文本'),
          lastChapter: const Value(1),
          lastParagraph: const Value(3),
        ));
    final c0 = await db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: bookId,
          idx: 0,
          title: '第一章',
          content: '　　第一段正文。\n　　第二段正文。',
        ));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: bookId,
          idx: 1,
          title: '第二章',
          content: '',
        ));
    final imgDir = Directory(p.join(imagesRoot.path, '$bookId'));
    await imgDir.create(recursive: true);
    final cur = File(p.join(imgDir.path, 'a_cur.png'));
    await cur.writeAsBytes(_fakePng(1));
    final h0 = File(p.join(imgDir.path, 'a_h0.png'));
    await h0.writeAsBytes(_fakePng(2));
    final h1 = File(p.join(imgDir.path, 'a_h1.png'));
    await h1.writeAsBytes(_fakePng(3));
    await db.into(db.illustrations).insert(IllustrationsCompanion.insert(
          bookId: bookId,
          chapterId: c0,
          afterParagraph: 2,
          anchorHash: 'hash-1',
          prompt: '一个测试提示词',
          imagePath: Value(cur.path),
          status: const Value('done'),
          imgWidth: const Value(640),
          imgHeight: const Value(480),
          history: Value(jsonEncode([h0.path, h1.path])),
        ));
    return bookId;
  }

  Future<(Uint8List, CompressionType)> readZipEntry(File zip, String name) async {
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final entry = archive.find(name);
      expect(entry, isNotNull, reason: 'ZIP 内缺少 $name');
      return (entry!.readBytes()!, entry.compression ?? CompressionType.deflate);
    } finally {
      input.closeSync();
    }
  }
  Future<int> maxBookId() async {
    final rows = await db.select(db.books).get();
    return rows.isEmpty ? 0 : rows.map((b) => b.id).reduce((a, b) => a > b ? a : b);
  }

  test('TXT 导出：UTF-8、按章节顺序、逐字一致、不覆盖已有文件', () async {
    final bookId = await seedBook();
    final f1 = await service.exportText(bookId);
    expect(f1.parent.path, startsWith(tempRoot.path));
    final text = utf8.decode(f1.readAsBytesSync());
    expect(text, contains('第一章'));
    expect(text, contains('　　第一段正文。\n　　第二段正文。'));
    expect(text, contains('第二章')); // 空章也输出标题

    final f2 = await service.exportText(bookId);
    expect(f2.path, isNot(f1.path), reason: '第二次导出不覆盖第一次的文件');
    expect(f1.existsSync(), isTrue);
  });

  test('单书归档往返：正文/元数据/锚点/当前图+全部历史/图片字节逐字一致', () async {
    final bookId = await seedBook();
    final zip = await service.exportArchive(bookId: bookId);

    final (manifestBytes, _) = await readZipEntry(zip, 'manifest.json');
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    expect(manifest['kind'], 'shengtushu_archive');
    expect(manifest['formatVersion'], 1);
    expect(manifest['scope'], 'book');
    expect((manifest['books'] as List).length, 1);

    final origIll = await (db.select(db.illustrations)
          ..where((i) => i.bookId.equals(bookId)))
        .getSingle();
    final origBytes = await File(origIll.imagePath!).readAsBytes();
    final origHistory = (jsonDecode(origIll.history) as List).cast<String>();

    final result = await service.importArchive(zip);
    expect(result.bookCount, 1);
    expect(result.imageCount, 3); // 当前图 + 2 历史图

    final newBook = await (db.select(db.books)
          ..where((b) => b.id.equals(result.bookIds.first)))
        .getSingle();
    expect(newBook.id, isNot(bookId));
    expect(newBook.title, '测试之书');
    expect(newBook.author, '作者甲');
    expect(newBook.format, 'txt');
    expect(newBook.lore, '世界观设定文本');
    expect(newBook.lastChapter, 1);
    expect(newBook.lastParagraph, 3);
    expect(newBook.sourcePath, ''); // 不恢复旧设备路径

    final chapters = await (db.select(db.chapters)
          ..where((c) => c.bookId.equals(newBook.id))
          ..orderBy([(c) => OrderingTerm.asc(c.idx)]))
        .get();
    expect(chapters.length, 2);
    expect(chapters[0].title, '第一章');
    expect(chapters[0].content, '　　第一段正文。\n　　第二段正文。');
    expect(chapters[1].title, '第二章');
    expect(chapters[1].content, ''); // 空章保留

    final ill = await (db.select(db.illustrations)
          ..where((i) => i.bookId.equals(newBook.id)))
        .getSingle();
    expect(ill.prompt, '一个测试提示词');
    expect(ill.anchorHash, 'hash-1');
    expect(ill.afterParagraph, 2);
    expect(ill.status, 'done');
    expect(ill.imgWidth, 640);
    expect(ill.imgHeight, 480);
    expect(await File(ill.imagePath!).readAsBytes(), origBytes);
    expect(p.dirname(ill.imagePath!), p.join(imagesRoot.path, '${newBook.id}'));
    final history = (jsonDecode(ill.history) as List).cast<String>();
    expect(history.length, 2);
    expect(await File(history[0]).readAsBytes(), await File(origHistory[0]).readAsBytes());
    expect(await File(history[1]).readAsBytes(), await File(origHistory[1]).readAsBytes());
    expect(history[0], isNot(origHistory[0]), reason: '全新文件名');
  });

  test('图片以 store（不压缩）方式入包', () async {
    final bookId = await seedBook();
    final zip = await service.exportArchive(bookId: bookId);
    final input = InputFileStream(zip.path);
    try {
      final archive = ZipDecoder().decodeStream(input);
      final imageEntries = archive.files
          .where((e) => e.isFile && e.name.contains('/images/'))
          .toList();
      expect(imageEntries, isNotEmpty);
      for (final e in imageEntries) {
        expect(e.compression, CompressionType.none, reason: '${e.name} 应为 store');
      }
      final bookJson = archive.find('books/$bookId/book.json')!;
      expect(bookJson.compression, isNot(CompressionType.none), reason: 'JSON 可压缩');
    } finally {
      input.closeSync();
    }
  });

  test('整库归档往返：多本书、与单书同格式、原书库保留', () async {
    await seedBook();
    await seedBook();
    final zip = await service.exportArchive();
    final (manifestBytes, _) = await readZipEntry(zip, 'manifest.json');
    final manifest = jsonDecode(utf8.decode(manifestBytes)) as Map<String, dynamic>;
    expect(manifest['scope'], 'full');
    expect((manifest['books'] as List).length, 2);

    final result = await service.importArchive(zip);
    expect(result.bookCount, 2);
    expect(await db.select(db.books).get().then((v) => v.length), 4, reason: '原书库保留');
    expect((await db.select(db.chapters).get()).length, 8);
  });

  test('无图 + 空正文书籍可往返', () async {
    final bookId = await db.into(db.books).insert(BooksCompanion.insert(
          title: '无图书',
          format: 'docx',
        ));
    await db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: bookId,
          idx: 0,
          title: '正文',
          content: '',
        ));
    final zip = await service.exportArchive(bookId: bookId);
    final result = await service.importArchive(zip);
    expect(result.imageCount, 0);
    final newBook = await (db.select(db.books)
          ..where((b) => b.id.equals(result.bookIds.single)))
        .getSingle();
    expect(newBook.title, '无图书');
    expect(newBook.format, 'docx');
  });

  test('缺图：导出时报清楚错误，不静默跳过，导出目录清理', () async {
    final bookId = await seedBook();
    final ill = await (db.select(db.illustrations)
          ..where((i) => i.bookId.equals(bookId)))
        .getSingle();
    await File(ill.imagePath!).delete();

    await expectLater(
      service.exportArchive(bookId: bookId),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('缺少图片文件'),
      )),
    );
    expect(tempRoot.listSync(), isEmpty, reason: '失败后导出目录清理');
  });

  test('重复导入：不覆盖已有书，每次分配全新 id 与图片文件名', () async {
    final bookId = await seedBook();
    final zip = await service.exportArchive(bookId: bookId);
    final r1 = await service.importArchive(zip);
    final r2 = await service.importArchive(zip);
    expect(r1.bookIds.single, isNot(bookId));
    expect(r2.bookIds.single, isNot(bookId));
    expect(r2.bookIds.single, isNot(r1.bookIds.single));
    final ills = await db.select(db.illustrations).get();
    expect(ills.length, 3);
    expect(ills.map((i) => i.imagePath).toSet().length, 3);
  });

  test('running 状态导入后归一化为 pending', () async {
    final bookId = await db.into(db.books).insert(BooksCompanion.insert(
          title: '运行中书',
          format: 'txt',
        ));
    final c0 = await db.into(db.chapters).insert(ChaptersCompanion.insert(
          bookId: bookId,
          idx: 0,
          title: '正文',
          content: '文本',
        ));
    await db.into(db.illustrations).insert(IllustrationsCompanion.insert(
          bookId: bookId,
          chapterId: c0,
          afterParagraph: 0,
          anchorHash: 'h',
          prompt: '',
          status: const Value('running'),
        ));
    final zip = await service.exportArchive(bookId: bookId);
    await service.importArchive(zip);
    final imported = await (db.select(db.illustrations)
          ..where((i) => i.bookId.isNotIn([bookId])))
        .getSingle();
    expect(imported.status, 'pending');
  });

  test('损坏 ZIP：导入报格式错误，数据库与临时目录干净', () async {
    await seedBook();
    final bad = File(p.join(tempRoot.path, 'bad.zip'));
    await bad.writeAsBytes(List<int>.generate(1024, (i) => i % 251));
    await expectLater(service.importArchive(bad), throwsA(isA<ArchiveFormatException>()));
    expect((await db.select(db.books).get()).length, 1);
    expect(tempRoot.listSync().whereType<Directory>(), isEmpty);
  });

  test('目录穿越条目被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(_minimalBookJson(illImage: '../../evil.txt')),
        '../evil.txt': [1, 2, 3],
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('穿越'),
      )),
    );
  });

  test('绝对路径条目被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(_minimalBookJson(illImage: '/abs/img.png')),
        'abs/img.png': [1],
      }),
      throwsA(isA<ArchiveFormatException>()),
    );
  });

  test('重复条目被拒绝', () async {
    final f = await _newTempZipFile(tempRoot, 'dup.zip');
    final out = OutputFileStream.toRamFile(RamFileHandle.asWritableRamBuffer());
    final encoder = ZipEncoder();
    encoder.startEncode(out);
    encoder.add(ArchiveFile.string('manifest.json', _manifestFor([])));
    encoder.add(ArchiveFile.string('dup.txt', 'a'));
    encoder.add(ArchiveFile.string('dup.txt', 'b'));
    encoder.endEncode();
    final bytes = out.getBytes();
    out.closeSync();
    await f.writeAsBytes(bytes);

    await expectLater(
      service.importArchive(f),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('重复条目'),
      )),
    );
  });

  test('别名路径（归一化后重名）被拒绝', () async {
    final f = await _newTempZipFile(tempRoot, 'alias.zip');
    final out = OutputFileStream.toRamFile(RamFileHandle.asWritableRamBuffer());
    final encoder = ZipEncoder();
    encoder.startEncode(out);
    encoder.add(ArchiveFile.string('manifest.json', _manifestFor(['books/1/book.json'])));
    encoder.add(ArchiveFile.string('books/1/book.json', jsonEncode(_minimalBookJson())));
    encoder.add(ArchiveFile.bytes('books/1/x.png', [9]));
    encoder.add(ArchiveFile.bytes('books/1/./x.png', [9]));
    encoder.endEncode();
    final bytes = out.getBytes();
    out.closeSync();
    await f.writeAsBytes(bytes);

    await expectLater(
      service.importArchive(f),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('重复条目'),
      )),
    );
  });

  test('manifest 引用的图片在包内缺失被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(_minimalBookJson(illImage: 'books/1/images/1_cur.png')),
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('缺失'),
      )),
    );
  });

  test('引用路径越出本书前缀被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(_minimalBookJson(illImage: 'books/2/images/x.png')),
        'books/2/images/x.png': [9],
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('越出本书'),
      )),
    );
  });

  test('book.json 章节 id 重复被拒绝', () async {
    final book = _minimalBookJson();
    (book['chapters'] as List).add({
      'id': 1, 'idx': 1, 'title': '重复章', 'content': 'x',
    });
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(book),
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('章节 id 重复'),
      )),
    );
  });

  test('未被 manifest 引用的多余文件被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': _manifestFor(['books/1/book.json']),
        'books/1/book.json': jsonEncode(_minimalBookJson()),
        'books/1/images/stowaway.png': [9, 9, 9],
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('未被 manifest 引用'),
      )),
    );
  });

  test('formatVersion 不符被拒绝', () async {
    await expectLater(
      _importRawZip(service, {
        'manifest.json': jsonEncode({
          'kind': 'shengtushu_archive',
          'formatVersion': 999,
          'books': [],
        }),
      }),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('不支持的归档版本'),
      )),
    );
  });

  test('导入中途失败（插图引用不存在的章节）回滚，原库保留', () async {
    await seedBook();
    final badBook = _minimalBookJson();
    badBook['illustrations'] = [
      {'id': 1, 'chapterId': 999, 'afterParagraph': 0, 'anchorOffset': -1,
       'anchorHash': 'h', 'prompt': '', 'status': 'done', 'error': '',
       'imgWidth': 10, 'imgHeight': 10, 'historyFiles': []},
    ];
    final f = await _writeRawZip(tempRoot, {
      'manifest.json': _manifestFor(['books/1/book.json']),
      'books/1/book.json': jsonEncode(badBook),
    });
    await expectLater(service.importArchive(f), throwsA(isA<ArchiveFormatException>()));
    expect((await db.select(db.books).get()).length, 1);
    expect(tempRoot.listSync().whereType<Directory>(), isEmpty);
  });

  test('导入目标图片目录已存在时报冲突，不接管不删除', () async {
    final bookId = await seedBook();
    final zip = await service.exportArchive(bookId: bookId);
    final nextId = await maxBookId() + 1;
    final existing = Directory(p.join(imagesRoot.path, '$nextId'));
    await existing.create(recursive: true);
    final marker = File(p.join(existing.path, 'keep.txt'));
    await marker.writeAsString('keep');

    await expectLater(
      service.importArchive(zip),
      throwsA(isA<ArchiveFormatException>().having(
        (e) => e.message, 'message', contains('已存在'),
      )),
    );
    expect(await marker.readAsString(), 'keep', reason: '已存在目录不被接管/删除');
    expect((await db.select(db.books).get()).length, 1, reason: '原库保留');
  });

  test('取消：写库阶段取消回滚，不产生图片目录，临时目录清理', () async {
    final bookId = await seedBook();
    final zip = await service.exportArchive(bookId: bookId);
    addTearDown(() => zip.parent.delete(recursive: true));

    var sawWrite = false;
    await expectLater(
      service.importArchive(
        zip,
        onProgress: (pr) {
          if (pr.message.startsWith('写入书籍')) sawWrite = true;
        },
        isCancelled: () => sawWrite,
      ),
      throwsA(isA<ArchiveCancelledException>()),
    );
    expect((await db.select(db.books).get()).length, 1);
    expect(imagesRoot.listSync().whereType<Directory>().length, 1, reason: '只有原书的图片目录');
    expect(
      tempRoot.listSync().whereType<Directory>().where((d) => p.basename(d.path).startsWith('import_')),
      isEmpty,
      reason: '导入暂存目录清理',
    );
  });

  test('首次使用自动创建临时目录，TXT 导出读取最新正文', () async {
    final bookId = await seedBook();
    await (db.update(db.chapters)..where((c) => c.bookId.equals(bookId) & c.idx.equals(0)))
        .write(const ChaptersCompanion(content: Value('更新后的正文\n\n保留空段')));
    final nested = Directory(p.join(tempRoot.path, 'new', 'transfer'));
    final firstUse = BookArchiveService(db, imagesRoot: imagesRoot, temporaryRoot: nested);
    final file = await firstUse.exportText(bookId);
    expect(await file.readAsString(), contains('更新后的正文\n\n保留空段'));
    final zip = await firstUse.exportArchive(bookId: bookId);
    expect((await firstUse.importArchive(zip)).bookCount, 1);
  });

  test('manifest 重复书籍 id 必须拒绝，不重复导入', () async {
    await expectLater(_importRawZip(service, {
      'manifest.json': jsonEncode({
        'kind': kArchiveKind, 'formatVersion': 1,
        'books': [for (var i = 0; i < 2; i++) {'id': 1, 'bookPath': 'books/1/book.json'}],
      }),
      'books/1/book.json': jsonEncode(_minimalBookJson()),
    }), throwsA(isA<ArchiveFormatException>().having((e) => e.message, 'message', contains('id 重复'))));
    expect(await db.select(db.books).get(), isEmpty);
  });

  test('绝对路径别名不能被归一化为合法图片引用', () async {
    await expectLater(_importRawZip(service, {
      'manifest.json': _manifestFor(['books/1/book.json']),
      'books/1/book.json': jsonEncode(_minimalBookJson(illImage: '/books/1/images/image.png')),
      'books/1/images/image.png': [1, 2],
    }), throwsA(isA<ArchiveFormatException>().having((e) => e.message, 'message', contains('绝对路径'))));
  });

  test('图片历史字段含非字符串不能静默丢弃', () async {
    final bookId = await seedBook();
    await db.update(db.illustrations).write(const IllustrationsCompanion(history: Value('[1]')));
    await expectLater(service.exportArchive(bookId: bookId), throwsA(isA<ArchiveFormatException>()));
  });

  test('取消：导出取消后清理导出目录', () async {
    await seedBook();
    var cancelled = false;
    await expectLater(
      service.exportArchive(
        isCancelled: () {
          final c = cancelled;
          cancelled = true;
          return c;
        },
      ),
      throwsA(isA<ArchiveCancelledException>()),
    );
    expect(tempRoot.listSync().whereType<Directory>(), isEmpty);
  });
}

// ---------- 原始 zip 构造工具（恶意/畸形包测试） ----------

Map<String, dynamic> _minimalBookJson({String? illImage}) => {
      'title': '书',
      'author': '',
      'format': 'txt',
      'lore': '',
      'createdAt': '2026-01-01T00:00:00.000',
      'lastChapter': 0,
      'lastParagraph': 0,
      'chapters': [
        {'id': 1, 'idx': 0, 'title': '正文', 'content': '内容'},
      ],
      'illustrations': [
        if (illImage != null)
          {
            'id': 1,
            'chapterId': 1,
            'afterParagraph': 0,
            'anchorOffset': -1,
            'anchorHash': 'h',
            'prompt': '',
            'status': 'done',
            'error': '',
            'imgWidth': 10,
            'imgHeight': 10,
            'historyFiles': [],
            'imageFile': illImage,
          },
      ],
    };

String _manifestFor(List<String> bookPaths) => jsonEncode({
      'kind': 'shengtushu_archive',
      'formatVersion': 1,
      'scope': 'full',
      'books': [
        for (var i = 0; i < bookPaths.length; i++)
          {'id': i + 1, 'bookPath': bookPaths[i]},
      ],
    });

Future<File> _newTempZipFile(Directory dir, String name) async {
  final f = File(p.join(dir.path, '${name}_${DateTime.now().microsecondsSinceEpoch}.zip'));
  await f.create(recursive: true);
  return f;
}

Future<File> _writeRawZip(Directory dir, Map<String, Object> files) async {
  final out = OutputFileStream.toRamFile(RamFileHandle.asWritableRamBuffer());
  final encoder = ZipEncoder();
  encoder.startEncode(out);
  for (final e in files.entries) {
    final data = e.value is String
        ? utf8.encode(e.value as String)
        : Uint8List.fromList((e.value as List<int>).toList());
    encoder.add(ArchiveFile.bytes(e.key, data));
  }
  encoder.endEncode();
  final bytes = out.getBytes();
  out.closeSync();
  final f = File(
      p.join(dir.path, 'raw_${files.length}_${DateTime.now().microsecondsSinceEpoch}.zip'));
  await f.writeAsBytes(bytes);
  return f;
}

Future<Object> _importRawZip(BookArchiveService service, Map<String, Object> files) async {
  final dir = await Directory.systemTemp.createTemp('bt_rawzip_');
  try {
    final f = await _writeRawZip(dir, files);
    return await service.importArchive(f); // 必须 await，防止 finally 提前删源
  } finally {
    await dir.delete(recursive: true);
  }
}

Uint8List _fakePng(int seed) {
  return Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, seed, seed, seed, 0x0A]);
}
