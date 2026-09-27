// 书库数据出口：TXT 导出 / 书库 ZIP 归档导出与导入
//
// 包结构（manifest 独立 formatVersion）：
//   manifest.json
//   books/<bookId>/book.json
//   books/<bookId>/images/<illId>_cur<ext> / <illId>_h<n><ext>
//
// 约定：不读 path_provider/settings、不加全局锁、不负责 share（调用方保证互斥）。
// 导出逐章流式写盘，图片以 store（不压缩）方式入包；导入逐文件有限内存解压校验，
// 先临时校验再事务建行，失败只清理本次新建内容。
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../data/database.dart';

const int kArchiveFormatVersion = 1;
const String kArchiveKind = 'shengtushu_archive';

class ArchiveProgress {
  final String message;
  final int completed;
  final int total;
  final int bytes;
  const ArchiveProgress({
    required this.message,
    required this.completed,
    required this.total,
    required this.bytes,
  });
}

class ArchiveImportResult {
  final List<int> bookIds;
  final int imageCount;
  const ArchiveImportResult({required this.bookIds, required this.imageCount});
  int get bookCount => bookIds.length;
}

class ArchiveCancelledException implements Exception {
  const ArchiveCancelledException();
  @override
  String toString() => 'ArchiveCancelledException';
}

class ArchiveFormatException implements Exception {
  final String message;
  const ArchiveFormatException(this.message);
  @override
  String toString() => 'ArchiveFormatException: $message';
}

class BookArchiveService {
  final AppDatabase db;
  final Directory imagesRoot;
  final Directory temporaryRoot;

  static const int _maxEntries = 50000;
  static const int _maxJsonBytes = 32 << 20; // 单个 JSON 上限
  static const int _maxTotalBytes = 4 << 30; // 解压总体积上限
  static const int _chunk = 1 << 20;

  BookArchiveService(this.db, {required this.imagesRoot, required this.temporaryRoot});

  // ---------------------------------------------------------------------------
  // TXT 导出
  // ---------------------------------------------------------------------------

  Future<File> exportText(
    int bookId, {
    void Function(ArchiveProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (book == null) throw StateError('书籍不存在: $bookId');
    final chapterCount = await _chapterCount(bookId);

    await temporaryRoot.create(recursive: true);
    final outDir = await temporaryRoot.createTemp('export_');
    final file = File(p.join(outDir.path, '${_sanitize(book.title)}.txt'));
    final sink = file.openWrite(encoding: utf8);
    var bytes = 0;
    var done = 0;
    try {
      await for (final page in _chapterPages(bookId, 64)) {
        for (final ch in page) {
          _checkCancelled(isCancelled);
          final b = utf8.encode('${ch.title}\n\n${ch.content}\n\n');
          sink.add(b);
          bytes += b.length;
          done++;
          onProgress?.call(ArchiveProgress(
            message: '导出 ${ch.title}',
            completed: done,
            total: chapterCount,
            bytes: bytes,
          ));
          await sink.flush();
          await Future<void>.delayed(Duration.zero);
        }
      }
      _checkCancelled(isCancelled);
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      await _deleteQuietly(outDir);
      rethrow;
    }
    return file;
  }

  // ---------------------------------------------------------------------------
  // 归档导出
  // ---------------------------------------------------------------------------

  Future<File> exportArchive({
    int? bookId,
    void Function(ArchiveProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    await temporaryRoot.create(recursive: true);
    final outDir = await temporaryRoot.createTemp('export_');
    try {
      final zipFile = await db.transaction(() async {
        final books = await (db.select(db.books)
              ..where((b) => bookId == null ? const Constant(true) : b.id.equals(bookId)))
            .get();

        var total = 1;
        if (bookId != null && books.isEmpty) throw StateError('书籍不存在: $bookId');
        for (final b in books) {
          total += 1 + await _imageCount(b.id);
        }
        var completed = 0;
        var bytes = 0;
        void step(String message) {
          completed++;
          onProgress?.call(ArchiveProgress(
            message: message,
            completed: completed,
            total: total,
            bytes: bytes,
          ));
        }

        final zipPath = p.join(outDir.path, 'shengtushu.zip');
        final output = OutputFileStream(zipPath);
        final encoder = ZipEncoder();
        var finished = false;
        try {
          encoder.startEncode(output);

          final manifest = {
            'kind': kArchiveKind,
            'formatVersion': kArchiveFormatVersion,
            'scope': bookId == null ? 'full' : 'book',
            'exportedAt': DateTime.now().toIso8601String(),
            'books': [for (final b in books) {'id': b.id, 'bookPath': 'books/${b.id}/book.json'}],
          };
          final manifestJson = jsonEncode(manifest);
          encoder.add(ArchiveFile.string('manifest.json', manifestJson));
          bytes += utf8.encode(manifestJson).length;
          step('写入 manifest');
          _checkCancelled(isCancelled);

          final stagingDir = Directory(p.join(outDir.path, '_staging'));
          await stagingDir.create();
          try {
            for (final b in books) {
              final jsonFile = File(p.join(stagingDir.path, 'book_${b.id}.json'));
              await _writeBookJson(b, jsonFile, isCancelled);
              if (await jsonFile.length() > _maxJsonBytes) {
                throw const ArchiveFormatException('单本书的结构化正文超过 32 MB，请分书备份');
              }
              final input = InputFileStream(jsonFile.path, bufferSize: _chunk);
              try {
                encoder.add(ArchiveFile.stream('books/${b.id}/book.json', input));
              } finally {
                input.closeSync();
              }
              bytes += await jsonFile.length();
              step('写入书籍 ${b.title}');
              _checkCancelled(isCancelled);

              for (final img in await _bookImages(b.id)) {
                final f = File(img.sourcePath);
                if (!await f.exists()) {
                  throw ArchiveFormatException(
                      '缺少图片文件: ${img.sourcePath}（书籍「${b.title}」插图 ${img.illId}）');
                }
                final input = InputFileStream(img.sourcePath, bufferSize: _chunk);
                try {
                  // 图片以 store 方式入包，不再 deflate
                  encoder.add(ArchiveFile.stream(img.zipPath, input)
                    ..compression = CompressionType.none);
                } finally {
                  input.closeSync();
                }
                bytes += await f.length();
                step('写入图片 ${p.basename(img.zipPath)}');
                await Future<void>.delayed(Duration.zero);
                _checkCancelled(isCancelled);
              }
              await Future<void>.delayed(Duration.zero);
              _checkCancelled(isCancelled);
            }
          } finally {
            await _deleteQuietly(stagingDir);
          }

          encoder.endEncode();
          finished = true;
          return File(zipPath);
        } finally {
          if (output.isOpen) output.closeSync();
          if (!finished) {
            await _deleteQuietly(outDir);
          }
        }
      });

      await _verifyZip(zipFile, isCancelled);
      return zipFile;
    } on ArchiveCancelledException {
      await _deleteQuietly(outDir);
      rethrow;
    } on ArchiveFormatException {
      await _deleteQuietly(outDir);
      rethrow;
    } catch (e) {
      await _deleteQuietly(outDir);
      throw ArchiveFormatException('写入归档失败: $e');
    }
  }

  /// 逐书把 book.json 流式写到 [jsonFile]（章节分批查询，正文不全量进内存）。
  Future<void> _writeBookJson(Book b, File jsonFile, bool Function()? isCancelled) async {
    final ills = await (db.select(db.illustrations)
          ..where((i) => i.bookId.equals(b.id))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();

    final sink = jsonFile.openWrite(encoding: utf8);
    try {
      sink.write('{"title":${jsonEncode(b.title)}');
      sink.write(',"author":${jsonEncode(b.author)}');
      sink.write(',"format":${jsonEncode(b.format)}');
      sink.write(',"lore":${jsonEncode(b.lore)}');
      sink.write(',"createdAt":${jsonEncode(b.createdAt.toIso8601String())}');
      sink.write(',"lastChapter":${b.lastChapter}');
      sink.write(',"lastParagraph":${b.lastParagraph}');
      sink.write(',"chapters":[');
      var first = true;
      await for (final page in _chapterPages(b.id, 64)) {
        for (final c in page) {
          _checkCancelled(isCancelled);
          if (!first) sink.write(',');
          first = false;
          sink.write(jsonEncode({'id': c.id, 'idx': c.idx, 'title': c.title, 'content': c.content}));
          await sink.flush();
          await Future<void>.delayed(Duration.zero);
        }
      }
      sink.write('],"illustrations":[');
      first = true;
      for (final ill in ills) {
        _checkCancelled(isCancelled);
        if (!first) sink.write(',');
        first = false;
        final history = _decodeHistory(ill, b.title);
        final curZip = (ill.imagePath?.isNotEmpty ?? false)
            ? 'books/${b.id}/images/${ill.id}_cur${_ext(ill.imagePath!)}'
            : null;
        sink.write(jsonEncode({
          'id': ill.id,
          'chapterId': ill.chapterId,
          'afterParagraph': ill.afterParagraph,
          'anchorOffset': ill.anchorOffset,
          'anchorHash': ill.anchorHash,
          'prompt': ill.prompt,
          'status': ill.status,
          'error': ill.error,
          'imgWidth': ill.imgWidth,
          'imgHeight': ill.imgHeight,
          'createdAt': ill.createdAt.toIso8601String(),
          'imageFile': curZip,
          'historyFiles': [
            for (var i = 0; i < history.length; i++)
              'books/${b.id}/images/${ill.id}_h$i${_ext(history[i])}'
          ],
        }));
      }
      sink.write(']}');
      await sink.flush();
      await sink.close();
    } catch (_) {
      await sink.close().catchError((_) {});
      rethrow;
    }
  }

  Future<void> _verifyZip(File zipFile, bool Function()? isCancelled) async {
    final input = InputFileStream(zipFile.path, bufferSize: _chunk);
    try {
      final archive = ZipDecoder().decodeStream(input);
      for (final entry in archive) {
        _checkCancelled(isCancelled);
        if (entry.isDirectory) continue;
        int crc;
        if (entry.compression == CompressionType.none) {
          // store 条目：分块校验，不整载内存
          crc = 0;
          final s = entry.rawContent!.getStream(decompress: false)..setPosition(0);
          while (!s.isEOS) {
            _checkCancelled(isCancelled);
            crc = getCrc32(s.readBytes(_chunk).toUint8List(), crc);
            await Future<void>.delayed(Duration.zero);
          }
        } else {
          // book.json（deflate）：体积受控后整载校验
          if (entry.size > _maxJsonBytes) {
            throw ArchiveFormatException('条目过大: ${entry.name}');
          }
          _readJson(entry, entry.name);
          continue;
        }
        if (entry.crc32 != null && crc != entry.crc32) {
          throw ArchiveFormatException('导出后校验失败（CRC 不符）: ${entry.name}');
        }
      }
    } finally {
      input.closeSync();
    }
  }

  // ---------------------------------------------------------------------------
  // 导入
  // ---------------------------------------------------------------------------

  Future<ArchiveImportResult> importArchive(
    File source, {
    void Function(ArchiveProgress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!await source.exists()) throw ArchiveFormatException('归档文件不存在: ${source.path}');
    await imagesRoot.create(recursive: true);

    await temporaryRoot.create(recursive: true);
    final workDir = await temporaryRoot.createTemp('import_');
    final createdImageDirs = <Directory>[];
    var committed = false;
    InputFileStream? zipInput;
    try {
      final input = InputFileStream(source.path, bufferSize: _chunk);
      zipInput = input;
      final decoder = ZipDecoder();
      late final Archive archive;
      try {
        archive = decoder.decodeStream(input);
      } catch (e) {
        throw ArchiveFormatException('无法读取 ZIP 文件: $e');
      }

      // 条目名归一化 + 去重（含别名路径）；总体积上限
      final seen = <String>{};
      var totalSize = 0;
      for (final h in decoder.directory.fileHeaders) {
        final raw = h.filename;
        _validateName(raw);
        final name = _normalize(raw);
        if (raw.endsWith('/') || raw.endsWith('\\')) continue; // 目录项
        if (h.file == null) continue;
        if (!seen.add(name)) throw ArchiveFormatException('归档内存在重复条目: $name');
        _validateName(name);
        totalSize += h.uncompressedSize;
      }
      for (final entry in archive) {
        if (entry.isSymbolicLink) throw ArchiveFormatException('归档包含符号链接: ${entry.name}');
        if (entry.compression != CompressionType.none && entry.compression != CompressionType.deflate) {
          throw ArchiveFormatException('不支持的压缩方式: ${entry.name}');
        }
      }
      if (decoder.directory.fileHeaders.length > _maxEntries) {
        throw ArchiveFormatException('归档条目数超上限（${archive.length}）');
      }
      if (totalSize > _maxTotalBytes) {
        throw ArchiveFormatException('归档解压总体积超上限（$totalSize 字节）');
      }
      _checkCancelled(isCancelled);

      // manifest
      final manifestEntry = archive.find('manifest.json');
      if (manifestEntry == null) throw ArchiveFormatException('缺少 manifest.json');
      if (manifestEntry.size > _maxJsonBytes) throw ArchiveFormatException('manifest.json 过大');
      final manifest = _parseManifest(_readJson(manifestEntry, 'manifest.json'));

      // 校验各 book.json
      final referenced = <String>{'manifest.json'};
      for (final ref in manifest) {
        if (!ref.bookPath.startsWith('books/${ref.origId}/')) {
          throw ArchiveFormatException('bookPath 与书籍 id 不符: ${ref.bookPath}');
        }
        final entry = archive.find(ref.bookPath);
        if (entry == null) throw ArchiveFormatException('manifest 引用的文件不存在: ${ref.bookPath}');
        if (entry.size > _maxJsonBytes) throw ArchiveFormatException('book.json 过大: ${ref.bookPath}');
        final decoded = _readJson(entry, ref.bookPath);
        if (decoded is! Map<String, dynamic>) throw ArchiveFormatException('book.json 顶层不是对象: ${ref.bookPath}');
        _parseBook(decoded, ref, archive, referenced);
        _checkCancelled(isCancelled);
      }
      for (final name in seen) {
        if (!referenced.contains(name)) {
          throw ArchiveFormatException('归档内存在未被 manifest 引用的文件: $name');
        }
      }

      // 进度：文件校验 + 每本书
      var completed = 0;
      final total = referenced.length + manifest.length;
      var bytesDone = 0;
      void step(String message, [int byteDelta = 0]) {
        completed++;
        bytesDone += byteDelta;
        onProgress?.call(ArchiveProgress(
          message: message,
          completed: completed,
          total: total,
          bytes: bytesDone,
        ));
      }

      // 逐文件解压到临时目录（有限内存），校验 CRC
      final extracted = <String, File>{};
      final extractDir = Directory(p.join(workDir.path, 'extracted'));
      for (final name in referenced) {
        _checkCancelled(isCancelled);
        final entry = archive.find(name)!;
        final dest = File(p.join(extractDir.path, name));
        await dest.parent.create(recursive: true);
        final bytes = await _extractEntry(entry, dest, isCancelled);
        if (entry.size >= 0 && bytes != entry.size) {
          throw ArchiveFormatException('条目解压体积不符: $name（$bytes != ${entry.size}）');
        }
        extracted[name] = dest;
        bytesDone += bytes;
        step('校验 $name');
      }

      // 事务建行 + 复制图片
      final newBookIds = <int>[];
      var imageCount = 0;
      final imageBase = DateTime.now().millisecondsSinceEpoch;
      await db.transaction(() async {
        for (var bi = 0; bi < manifest.length; bi++) {
          final ref = manifest[bi];
          final json = jsonDecode(await extracted[ref.bookPath]!.readAsString()) as Map<String, dynamic>;
          final book = _parseBook(json, ref, archive, <String>{'manifest.json'});
          step('写入书籍 ${book.title}（${bi + 1}/${manifest.length}）');
          _checkCancelled(isCancelled);

          final newBookId = await db.into(db.books).insert(BooksCompanion.insert(
                title: book.title,
                author: Value(book.author),
                format: book.format,
                sourcePath: const Value(''), // 不恢复旧设备路径
                createdAt: Value(book.createdAt),
                lastChapter: Value(book.lastChapter),
                lastParagraph: Value(book.lastParagraph),
                lore: Value(book.lore),
              ));
          newBookIds.add(newBookId);

          final chapterIdMap = <int, int>{};
          for (var i = 0; i < book.chapters.length; i++) {
            _checkCancelled(isCancelled);
            final c = book.chapters[i];
            chapterIdMap[c.origId] = await db.into(db.chapters).insert(ChaptersCompanion.insert(
                  bookId: newBookId,
                  idx: i,
                  title: c.title,
                  content: c.content,
                ));
          }

          final imgDir = Directory(p.join(imagesRoot.path, '$newBookId'));
          if (await imgDir.exists()) {
            throw ArchiveFormatException('导入目标图片目录已存在，疑似 id 冲突: ${imgDir.path}');
          }
          await imgDir.create(recursive: true);
          createdImageDirs.add(imgDir);

          for (final ill in book.illustrations) {
            _checkCancelled(isCancelled);
            final newChapterId = chapterIdMap[ill.chapterId];
            if (newChapterId == null) {
              throw ArchiveFormatException('插图 ${ill.origId} 引用了不存在的章节 id ${ill.chapterId}');
            }
            String? newImagePath;
            if (ill.imageFile != null) {
              newImagePath = await _copyImage(
                extracted[ill.imageFile!]!, imgDir, imageBase, imageCount++,
              );
            }
            final newHistory = <String>[];
            for (final h in ill.historyFiles) {
              _checkCancelled(isCancelled);
              newHistory.add(await _copyImage(extracted[h]!, imgDir, imageBase, imageCount++));
            }

            await db.into(db.illustrations).insert(IllustrationsCompanion.insert(
                  bookId: newBookId,
                  chapterId: newChapterId,
                  afterParagraph: ill.afterParagraph,
                  anchorOffset: Value(ill.anchorOffset),
                  anchorHash: ill.anchorHash,
                  prompt: ill.prompt,
                  imagePath: Value(newImagePath),
                  status: Value(ill.status),
                  error: Value(ill.error),
                  imgWidth: Value(ill.imgWidth),
                  imgHeight: Value(ill.imgHeight),
                  history: Value(jsonEncode(newHistory)),
                  createdAt: Value(ill.createdAt),
                ));
          }
        }
        // commit 前最后取消检查
        _checkCancelled(isCancelled);
      });

      committed = true;
      return ArchiveImportResult(bookIds: newBookIds, imageCount: imageCount);
    } catch (_) {
      if (!committed) {
        for (final d in createdImageDirs) {
          await _deleteQuietly(d);
        }
      }
      rethrow;
    } finally {
      zipInput?.closeSync();
      await _deleteQuietly(workDir);
    }
  }

  Future<String> _copyImage(File src, Directory imgDir, int base, int seq) async {
    final dst = File(p.join(imgDir.path, '${base}_$seq${p.extension(src.path)}'));
    await src.copy(dst.path);
    return dst.path;
  }

  /// 有限内存解压单条目到 [dest]，返回解压字节数。store 条目分块拷贝并算 CRC；
  /// deflate 条目流式解压到文件后，再从文件分块校验 CRC。
  Future<int> _extractEntry(ArchiveFile entry, File dest, bool Function()? isCancelled) async {
    final raw = entry.rawContent;
    if (raw == null) throw ArchiveFormatException('条目无内容: ${entry.name}');
    final output = OutputFileStream(dest.path);
    final out = _LimitedOutput(output, entry.size);
    try {
      if (entry.compression == CompressionType.none) {
        final s = raw.getStream(decompress: false)..setPosition(0);
        var crc = 0;
        var count = 0;
        while (!s.isEOS) {
          _checkCancelled(isCancelled);
          final chunk = s.readBytes(_chunk).toUint8List();
          out.writeBytes(chunk);
          crc = getCrc32(chunk, crc);
          count += chunk.length;
          await Future<void>.delayed(Duration.zero);
        }
        _verifyCrc(entry, crc);
        return count;
      }
      final compressed = raw.getStream(decompress: false)..setPosition(0);
      ZLibDecoder().decodeStream(compressed, out, raw: true);
    } finally {
      output.closeSync();
    }
    final written = await dest.length();
    final crc = await _fileCrc(dest, isCancelled);
    _verifyCrc(entry, crc);
    return written;
  }

  void _verifyCrc(ArchiveFile entry, int crc) {
    if (entry.crc32 != null && crc != entry.crc32) {
      throw ArchiveFormatException('CRC 校验失败: ${entry.name}');
    }
  }

  Future<int> _fileCrc(File f, bool Function()? isCancelled) async {
    var crc = 0;
    await for (final bytes in f.openRead()) {
      _checkCancelled(isCancelled);
      crc = getCrc32(bytes, crc);
    }
    return crc;
  }

  // ---------------------------------------------------------------------------
  // book.json 解析校验
  // ---------------------------------------------------------------------------

  dynamic _readJson(ArchiveFile entry, String name) {
    if (entry.size < 0 || entry.size > _maxJsonBytes || !entry.isFile) {
      throw ArchiveFormatException('JSON 条目过大或无效: $name');
    }
    final raw = entry.rawContent;
    if (raw == null) throw ArchiveFormatException('无法读取: $name');
    final memory = OutputMemoryStream();
    final output = _LimitedOutput(memory, entry.size);
    final source = raw.getStream(decompress: false)..setPosition(0);
    if (entry.compression == CompressionType.none) {
      output.writeStream(source);
    } else {
      ZLibDecoder().decodeStream(source, output, raw: true);
    }
    source.setPosition(0);
    final bytes = memory.getBytes();
    if (bytes.length != entry.size) throw ArchiveFormatException('JSON 条目体积不符: $name');
    _verifyCrc(entry, getCrc32(bytes));
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (e) {
      throw ArchiveFormatException('$name 不是合法 JSON: $e');
    }
  }

  List<_BookRef> _parseManifest(dynamic raw) {
    if (raw is! Map<String, dynamic>) throw ArchiveFormatException('manifest.json 顶层不是对象');
    if (raw['kind'] != kArchiveKind) throw ArchiveFormatException('不是生图书归档（kind 不符）');
    if (raw['formatVersion'] is! int) throw ArchiveFormatException('manifest 缺少 formatVersion');
    if (raw['formatVersion'] != kArchiveFormatVersion) {
      throw ArchiveFormatException('不支持的归档版本: ${raw['formatVersion']}（当前支持 $kArchiveFormatVersion）');
    }
    if (raw['books'] is! List) throw ArchiveFormatException('manifest.books 不是数组');
    final books = <_BookRef>[];
    final ids = <int>{};
    for (final item in raw['books'] as List) {
      if (item is! Map<String, dynamic>) throw ArchiveFormatException('manifest.books 元素不是对象');
      final id = item['id'];
      final bookPath = item['bookPath'];
      if (id is! int || id <= 0) throw ArchiveFormatException('manifest book.id 不是有效整数');
      if (!ids.add(id)) throw ArchiveFormatException('manifest 书籍 id 重复: $id');
      if (bookPath is! String) throw ArchiveFormatException('manifest book.bookPath 不是字符串');
      _validateName(bookPath);
      final normalizedPath = _normalize(bookPath);
      if (normalizedPath != 'books/$id/book.json') throw ArchiveFormatException('bookPath 与书籍 id 不符: $bookPath');
      books.add(_BookRef(origId: id, bookPath: normalizedPath));
    }
    return books;
  }

  _BookData _parseBook(
    Map<String, dynamic> json,
    _BookRef ref,
    Archive archive,
    Set<String> referenced,
  ) {
    final ctx = ref.bookPath;
    final title = json['title'];
    if (title is! String || title.isEmpty) throw ArchiveFormatException('book.json 缺少有效 title: $ctx');
    final chaptersRaw = json['chapters'];
    if (chaptersRaw is! List) throw ArchiveFormatException('book.json chapters 不是数组: $ctx');
    final illsRaw = json['illustrations'];
    if (illsRaw is! List) throw ArchiveFormatException('book.json illustrations 不是数组: $ctx');

    final chapters = <_ChapterData>[];
    final chapterIds = <int>{};
    final chapterIndexes = <int>{};
    for (final c in chaptersRaw) {
      if (c is! Map<String, dynamic>) throw ArchiveFormatException('chapter 不是对象: $ctx');
      final id = c['id'];
      final idx = c['idx'];
      final chTitle = c['title'];
      final content = c['content'];
      if (id is! int || idx is! int || chTitle is! String || content is! String) {
        throw ArchiveFormatException('chapter 字段类型不符: $ctx');
      }
      if (!chapterIds.add(id)) throw ArchiveFormatException('章节 id 重复: $id（$ctx）');
      if (idx < 0 || !chapterIndexes.add(idx)) throw ArchiveFormatException('章节顺序无效或重复: $idx（$ctx）');
      chapters.add(_ChapterData(origId: id, idx: idx, title: chTitle, content: content));
    }
    chapters.sort((a, b) => a.idx.compareTo(b.idx));

    final ills = <_IllData>[];
    final illIds = <int>{};
    for (final i in illsRaw) {
      if (i is! Map<String, dynamic>) throw ArchiveFormatException('illustration 不是对象: $ctx');
      final id = i['id'];
      final chapterId = i['chapterId'];
      if (id is! int || chapterId is! int) {
        throw ArchiveFormatException('illustration 字段类型不符: $ctx');
      }
      if (!illIds.add(id)) throw ArchiveFormatException('插图 id 重复: $id（$ctx）');
      if (!chapters.any((c) => c.origId == chapterId)) {
        throw ArchiveFormatException('插图 $id 引用了不存在的章节 id $chapterId（书籍「$title」）');
      }
      final afterParagraph = _asInt(i['afterParagraph'], 0);
      final anchorOffset = _asInt(i['anchorOffset'], -1, min: -1);
      var status = i['status'] is String ? i['status'] as String : 'pending';
      if (status == 'running') status = 'pending'; // 运行态跨设备不可延续
      if (!const {'pending', 'done', 'failed'}.contains(status)) status = 'pending';
      final imgPrefix = 'books/${ref.origId}/images/';

      String? imageFile;
      final rawImageFile = i['imageFile'];
      if (rawImageFile != null) {
        if (rawImageFile is! String) throw ArchiveFormatException('illustration.imageFile 不是字符串: $ctx');
        imageFile = _requireRef(rawImageFile, imgPrefix, archive, referenced, ctx);
      }
      final historyRaw = i['historyFiles'];
      if (historyRaw is! List) throw ArchiveFormatException('illustration.historyFiles 不是数组: $ctx');
      final historyFiles = <String>[];
      for (final h in historyRaw) {
        if (h is! String) throw ArchiveFormatException('historyFiles 元素不是字符串: $ctx');
        historyFiles.add(_requireRef(h, imgPrefix, archive, referenced, ctx));
      }

      ills.add(_IllData(
        origId: id,
        chapterId: chapterId,
        afterParagraph: afterParagraph,
        anchorOffset: anchorOffset,
        anchorHash: i['anchorHash'] is String ? i['anchorHash'] as String : '',
        prompt: i['prompt'] is String ? i['prompt'] as String : '',
        status: status,
        error: i['error'] is String ? i['error'] as String : '',
        imgWidth: _asInt(i['imgWidth'], 1280, min: 1),
        imgHeight: _asInt(i['imgHeight'], 720, min: 1),
        createdAt: i['createdAt'] is String
            ? (DateTime.tryParse(i['createdAt'] as String) ?? DateTime.now())
            : DateTime.now(),
        imageFile: imageFile,
        historyFiles: historyFiles,
      ));
    }

    referenced.add(ref.bookPath);

    var createdAt = DateTime.now();
    if (json['createdAt'] is String) {
      createdAt = DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now();
    }
    return _BookData(
      title: title,
      author: _asStr(json['author']),
      format: _asStr(json['format']),
      lore: _asStr(json['lore']),
      createdAt: createdAt,
      lastChapter: _asInt(json['lastChapter'], 0),
      lastParagraph: _asInt(json['lastParagraph'], 0),
      chapters: chapters,
      illustrations: ills,
    );
  }

  String _requireRef(String name, String prefix, Archive archive, Set<String> referenced, String ctx) {
    _validateName(name);
    final n = _normalize(name);
    _validateName(n);
    if (!n.startsWith(prefix)) {
      throw ArchiveFormatException('引用路径越出本书范围: $n（$ctx）');
    }
    final entry = archive.find(n);
    if (entry == null || !entry.isFile) {
      throw ArchiveFormatException('引用的文件在包内缺失: $n');
    }
    if (!referenced.add(n)) throw ArchiveFormatException('图片引用重复: $n');
    return n;
  }

  // ---------------------------------------------------------------------------
  // 查询工具
  // ---------------------------------------------------------------------------

  Stream<List<Chapter>> _chapterPages(int bookId, int pageSize) async* {
    var cursor = -1;
    while (true) {
      final page = await (db.select(db.chapters)
            ..where((c) => c.bookId.equals(bookId) & c.idx.isBiggerThanValue(cursor))
            ..orderBy([(c) => OrderingTerm.asc(c.idx)])
            ..limit(pageSize))
          .get();
      if (page.isEmpty) return;
      yield page;
      cursor = page.last.idx;
      if (page.length < pageSize) return;
    }
  }

  Future<int> _chapterCount(int bookId) async {
    final cnt = db.chapters.id.count(filter: db.chapters.bookId.equals(bookId));
    final q = db.selectOnly(db.chapters)..addColumns([cnt]);
    return await q.map((row) => row.read(cnt) ?? 0).getSingle();
  }

  Future<int> _imageCount(int bookId) async {
    final ills = await (db.select(db.illustrations)..where((i) => i.bookId.equals(bookId))).get();
    var n = 0;
    for (final i in ills) {
      if (i.imagePath?.isNotEmpty ?? false) n++;
      n += _decodeHistory(i, '').length;
    }
    return n;
  }

  /// 每本书的导出图片（当前图 + 历史，按插图 id 排序）
  Future<List<_ImageRef>> _bookImages(int bookId) async {
    final ills = await (db.select(db.illustrations)
          ..where((i) => i.bookId.equals(bookId))
          ..orderBy([(i) => OrderingTerm.asc(i.id)]))
        .get();
    final result = <_ImageRef>[];
    for (final ill in ills) {
      if (ill.imagePath?.isNotEmpty ?? false) {
        result.add(_ImageRef(
          illId: ill.id,
          sourcePath: ill.imagePath!,
          zipPath: 'books/$bookId/images/${ill.id}_cur${_ext(ill.imagePath!)}',
        ));
      }
      final history = _decodeHistory(ill, '');
      for (var i = 0; i < history.length; i++) {
        result.add(_ImageRef(
          illId: ill.id,
          sourcePath: history[i],
          zipPath: 'books/$bookId/images/${ill.id}_h$i${_ext(history[i])}',
        ));
      }
    }
    return result;
  }

  List<String> _decodeHistory(Illustration ill, String bookTitle) {
    try {
      final decoded = jsonDecode(ill.history);
      if (decoded is List && decoded.every((h) => h is String && h.isNotEmpty)) {
        return decoded.cast<String>();
      }
      throw const FormatException();
    } catch (_) {
      throw ArchiveFormatException('插图 ${ill.id} 的 history 字段不是合法 JSON 数组');
    }
  }

  // ---------------------------------------------------------------------------
  // 小工具
  // ---------------------------------------------------------------------------

  /// '\'→'/'，去空段与 '.' 段（把 'a/./b'、'a//b' 归一化，别名路径从而暴露为重复）
  String _normalize(String name) =>
      name.replaceAll('\\', '/').split('/').where((s) => s.isNotEmpty && s != '.').join('/');

  void _validateName(String name) {
    if (name.isEmpty) throw ArchiveFormatException('归档内存在空条目名');
    if (name.startsWith('/') || name.startsWith('\\')) throw ArchiveFormatException('归档内存在绝对路径: $name');
    if (name.contains(':') || name.contains('\u0000')) throw ArchiveFormatException('归档内存在非法路径: $name');
    for (final s in name.replaceAll('\\', '/').split('/')) {
      if (s == '..') throw ArchiveFormatException('归档内存在目录穿越条目: $name');
    }
  }

  void _checkCancelled(bool Function()? isCancelled) {
    if (isCancelled != null && isCancelled()) throw const ArchiveCancelledException();
  }

  Future<void> _deleteQuietly(FileSystemEntity e) async {
    try {
      if (await e.exists()) await e.delete(recursive: true);
    } catch (_) {}
  }

  String _ext(String path) {
    final e = p.extension(path);
    return e.isEmpty ? '.img' : e.toLowerCase();
  }

  String _sanitize(String name) {
    final cleaned = name
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? 'export' : cleaned;
  }

  String _asStr(dynamic v) => v is String ? v : '';
  int _asInt(dynamic v, int def, {int min = 0}) {
    if (v is! int) return def;
    return v < min ? min : v;
  }
}

class _LimitedOutput extends OutputStream {
  final OutputStream output;
  final int limit;
  _LimitedOutput(this.output, this.limit) : super(byteOrder: output.byteOrder);

  @override
  int get length => output.length;
  void _check(int additional) {
    if (additional < 0 || length + additional > limit) {
      throw const ArchiveFormatException('条目实际解压体积超过声明值');
    }
  }
  @override
  void writeByte(int value) {
    _check(1);
    output.writeByte(value);
  }
  @override
  void writeBytes(List<int> bytes, {int? length}) {
    _check(length ?? bytes.length);
    output.writeBytes(bytes, length: length);
  }
  @override
  void writeStream(InputStream stream) {
    _check(stream.length);
    output.writeStream(stream);
  }
  @override
  Uint8List subset(int start, [int? end]) => output.subset(start, end);
  @override
  void flush() => output.flush();
  @override
  void clear() => output.clear();
}

class _BookRef {
  final int origId;
  final String bookPath;
  const _BookRef({required this.origId, required this.bookPath});
}

class _ChapterData {
  final int origId;
  final int idx;
  final String title;
  final String content;
  const _ChapterData({required this.origId, required this.idx, required this.title, required this.content});
}

class _IllData {
  final int origId;
  final int chapterId;
  final int afterParagraph;
  final int anchorOffset;
  final String anchorHash;
  final String prompt;
  final String status;
  final String error;
  final int imgWidth;
  final int imgHeight;
  final DateTime createdAt;
  final String? imageFile;
  final List<String> historyFiles;
  const _IllData({
    required this.origId,
    required this.chapterId,
    required this.afterParagraph,
    required this.anchorOffset,
    required this.anchorHash,
    required this.prompt,
    required this.status,
    required this.error,
    required this.imgWidth,
    required this.imgHeight,
    required this.createdAt,
    required this.imageFile,
    required this.historyFiles,
  });
}

class _BookData {
  final String title;
  final String author;
  final String format;
  final String lore;
  final DateTime createdAt;
  final int lastChapter;
  final int lastParagraph;
  final List<_ChapterData> chapters;
  final List<_IllData> illustrations;
  const _BookData({
    required this.title,
    required this.author,
    required this.format,
    required this.lore,
    required this.createdAt,
    required this.lastChapter,
    required this.lastParagraph,
    required this.chapters,
    required this.illustrations,
  });
}

class _ImageRef {
  final int illId;
  final String sourcePath;
  final String zipPath;
  const _ImageRef({required this.illId, required this.sourcePath, required this.zipPath});
}
