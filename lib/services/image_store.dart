// 图片存储：应用沙盒 images/{bookId}/ 目录
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class ImageStore {
  ImageStore._();
  static final ImageStore instance = ImageStore._();

  Directory? _base;

  Future<Directory> baseDir() async {
    if (_base != null) return _base!;
    final docs = await getApplicationDocumentsDirectory();
    _base = Directory(p.join(docs.path, 'images'));
    if (!await _base!.exists()) await _base!.create(recursive: true);
    return _base!;
  }

  Future<String> dirForBook(int bookId) async {
    final base = await baseDir();
    final d = Directory(p.join(base.path, '$bookId'));
    if (!await d.exists()) await d.create(recursive: true);
    return d.path;
  }

  Future<String> newPath(int bookId, String ext) async {
    final dir = await dirForBook(bookId);
    final name = '${DateTime.now().millisecondsSinceEpoch}_$ext';
    return p.join(dir, name);
  }

  /// 封面路径：带时间戳，避免 Flutter 按路径缓存旧封面
  Future<String> newCoverPath(int bookId, String ext) async {
    final dir = await dirForBook(bookId);
    return p.join(dir, 'cover_${DateTime.now().millisecondsSinceEpoch}$ext');
  }

  Future<void> deleteBookImages(int bookId) async {
    final base = await baseDir();
    final d = Directory(p.join(base.path, '$bookId'));
    if (await d.exists()) await d.delete(recursive: true);
  }
}
