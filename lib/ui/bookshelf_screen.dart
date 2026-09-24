// 书架：导入 TXT/DOCX、阅读、设定说明、导出 PDF、删除
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/import/book_importer.dart';
import '../services/image_store.dart';
import '../services/settings_service.dart';
import 'pdf_export_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';
import 'widgets.dart';

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  bool _importing = false;

  Stream<List<Book>> _watchBooks() {
    return (widget.db.select(widget.db.books)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  Future<void> _import() async {
    if (_importing) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'docx'],
    );
    if (files.isEmpty || files.first.path == null) return;
    final f = files.first;
    final path = f.path!;
    setState(() => _importing = true);
    try {
      final chapters =
          importBookFile(path, chapterRegex: SettingsService.instance.chapterRegex);
      if (chapters.isEmpty) {
        throw const FormatException('未解析出任何内容');
      }
      final title = f.name.replaceAll(RegExp(r'\.(txt|docx)$', caseSensitive: false), '');
      await widget.db.transaction(() async {
        final bookId = await widget.db.into(widget.db.books).insert(BooksCompanion.insert(
              title: title,
              format: path.toLowerCase().endsWith('.docx') ? 'docx' : 'txt',
              sourcePath: Value(path),
            ));
        for (var i = 0; i < chapters.length; i++) {
          await widget.db.into(widget.db.chapters).insert(ChaptersCompanion.insert(
                bookId: bookId,
                idx: i,
                title: chapters[i].title,
                content: chapters[i].content,
              ));
        }
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入完成：$title，共 ${chapters.length} 章')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _delete(Book book) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除书籍'),
        content: Text('《${book.title}》及其全部插图缓存将被删除，确定？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.db.transaction(() async {
      await (widget.db.delete(widget.db.illustrations)..where((t) => t.bookId.equals(book.id))).go();
      await (widget.db.delete(widget.db.chapters)..where((t) => t.bookId.equals(book.id))).go();
      await (widget.db.delete(widget.db.books)..where((t) => t.id.equals(book.id))).go();
    });
    await ImageStore.instance.deleteBookImages(book.id);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('生图书'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => buildSettingsScreen(widget.db))),
          ),
        ],
      ),
      floatingActionButton: _importing
          ? const FloatingActionButton(onPressed: null, child: SizedBox(
              width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))
          : FloatingActionButton.extended(
              onPressed: _import,
              icon: const Icon(Icons.upload_file),
              label: const Text('导入 TXT / DOCX'),
            ),
      body: StreamBuilder<List<Book>>(
        stream: _watchBooks(),
        builder: (context, snap) {
          final books = snap.data ?? const <Book>[];
          if (books.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.auto_stories_outlined, size: 72, color: Colors.grey.shade400),
                  const SizedBox(height: 12),
                  Text('书架空空如也', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  const Text('点击右下角导入本地 TXT / DOCX 小说', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: books.length,
            itemBuilder: (context, i) {
              final book = books[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colorFor(book.id),
                    child: Text(book.title.isEmpty ? '书' : book.title.characters.first,
                        style: const TextStyle(color: Colors.white)),
                  ),
                  title: Text(book.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text('进度 第${book.lastChapter + 1}章'),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => ReaderScreen(db: widget.db, bookId: book.id))),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) {
                      switch (v) {
                        case 'lore':
                          _editLore(book);
                          break;
                        case 'pdf':
                          Navigator.push(context, MaterialPageRoute(
                              builder: (_) => PdfExportScreen(db: widget.db, book: book)));
                          break;
                        case 'delete':
                          _delete(book);
                          break;
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'lore', child: Text('设定说明（生图参考）')),
                      PopupMenuItem(value: 'pdf', child: Text('导出 PDF')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _editLore(Book book) async {
    final ctrl = TextEditingController(text: book.lore);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('设定说明（生图参考）'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: ctrl,
            maxLines: 8,
            decoration: const InputDecoration(
              hintText: '人物外貌、服饰、世界观等固定设定。\n注入模板的 <!--设定说明--> 占位符，仅作参考不会被插图。',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true) {
      await (widget.db.update(widget.db.books)..where((t) => t.id.equals(book.id)))
          .write(BooksCompanion(lore: Value(ctrl.text.trim())));
    }
  }
}
