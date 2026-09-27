// 书籍封面：把已生成的插图复制一份作为封面（复制而非引用，源图被删后封面仍在）
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:path/path.dart' as p;

import '../data/database.dart';
import 'image_store.dart';

class CoverService {
  CoverService(this.db);
  final AppDatabase db;

  /// 把 [srcPath] 复制为 [bookId] 的封面，返回新封面路径
  Future<String> setCover(int bookId, String srcPath) async {
    final src = File(srcPath);
    if (!await src.exists()) {
      throw StateError('图片文件不存在');
    }
    final ext = p.extension(srcPath).toLowerCase();
    final dst = await ImageStore.instance.newCoverPath(bookId, ext.isEmpty ? '.png' : ext);
    await src.copy(dst);
    final old = await coverOf(bookId);
    await (db.update(db.books)..where((t) => t.id.equals(bookId)))
        .write(BooksCompanion(coverPath: Value(dst)));
    await _deleteCoverFile(old, bookId: bookId, keep: dst);
    return dst;
  }

  Future<void> clearCover(int bookId) async {
    final old = await coverOf(bookId);
    await (db.update(db.books)..where((t) => t.id.equals(bookId)))
        .write(const BooksCompanion(coverPath: Value('')));
    await _deleteCoverFile(old, bookId: bookId);
  }

  Future<String> coverOf(int bookId) async {
    final row = await (db.selectOnly(db.books)
          ..addColumns([db.books.coverPath])
          ..where(db.books.id.equals(bookId))
          ..orderBy([OrderingTerm.asc(db.books.id)]))
        .getSingleOrNull();
    return row?.read(db.books.coverPath) ?? '';
  }

  /// 只删本书 images/ 目录下 cover_ 前缀的旧封面，绝不碰插图文件
  Future<void> _deleteCoverFile(String old, {required int bookId, String? keep}) async {
    if (old.isEmpty || old == keep) return;
    if (!p.basename(old).startsWith('cover_')) return;
    final dir = await ImageStore.instance.dirForBook(bookId);
    if (!p.isWithin(p.normalize(dir), p.normalize(old))) return;
    try {
      final f = File(old);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // 删旧封面失败不影响主流程
    }
  }
}
