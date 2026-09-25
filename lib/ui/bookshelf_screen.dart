// 书架：导入 TXT/DOCX、阅读、设定说明、导出 PDF、删除；支持系统「打开方式」导入
import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../data/import/book_importer.dart';
import '../services/image_store.dart';
import '../services/settings_service.dart';
import 'pdf_export_screen.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

/// 系统「打开方式」VIEW intent 通道（MainActivity 侧把 content:// 复制进缓存后给路径）
const MethodChannel kViewIntentChannel = MethodChannel('shengtushu/view_intent');

/// demo 原型四组渐变封面（按 book.id 轮换）
const List<List<Color>> _coverGradients = [
  [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
  [Color(0xFF10B981), Color(0xFF047857)],
  [Color(0xFFF59E0B), Color(0xFFB45309)],
  [Color(0xFFF43F5E), Color(0xFFBE123C)],
];

class BookshelfScreen extends StatefulWidget {
  const BookshelfScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<BookshelfScreen> createState() => _BookshelfScreenState();
}

class _BookshelfScreenState extends State<BookshelfScreen> {
  bool _importing = false;
  // 书架统计缓存（章节数 / 插图数），同一份 books 快照只查一次
  List<Book>? _statsBooks;
  Future<Map<int, (int, int)>>? _statsFuture;

  /// isolate 入口：文件解析（纯计算，不碰 UI）
  static List<ImportedChapter> _importTask((String, String) args) {
    return importBookFile(args.$1, chapterRegex: args.$2);
  }

  Stream<List<Book>> _watchBooks() {
    return (widget.db.select(widget.db.books)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  @override
  void initState() {
    super.initState();
    kViewIntentChannel.setMethodCallHandler((call) async {
      if (call.method == 'onViewIntent') await _importFromViewIntent();
    });
    // 冷启动：onCreate 里的 VIEW intent 不会有推送，主动拉取
    _importFromViewIntent();
  }

  /// 文件管理器「打开方式」导入，完成后直接打开书
  Future<void> _importFromViewIntent() async {
    if (_importing) return;
    try {
      final data = await kViewIntentChannel.invokeMethod<Map<dynamic, dynamic>>('takeViewFile');
      if (data == null) return;
      final path = data['path'] as String?;
      final name = (data['name'] as String?) ?? 'book';
      if (path == null) {
        _toast('无法读取该文件');
        return;
      }
      final lower = name.toLowerCase();
      if (!lower.endsWith('.txt') && !lower.endsWith('.docx')) {
        _toast('仅支持 TXT / DOCX 文件');
        return;
      }
      final bookId = await _persistImport(path, name);
      if (bookId != null && mounted) {
        Navigator.push(context,
            MaterialPageRoute(builder: (_) => ReaderScreen(db: widget.db, bookId: bookId)));
      }
    } catch (_) {
      // 无 VIEW intent / 通道异常：静默（正常从图标启动时无待处理文件）
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// 解析文件并入库，返回新书 id（标题去掉扩展名）
  Future<int?> _persistImport(String path, String fileName) async {
    if (_importing) return null;
    setState(() => _importing = true);
    try {
      // 解析放进 isolate，避免大文件卡主线程
      final chapters = await compute(_importTask, (path, SettingsService.instance.chapterRegex));
      if (chapters.isEmpty) {
        throw const FormatException('未解析出任何内容');
      }
      final title = fileName.replaceAll(RegExp(r'\.(txt|docx)$', caseSensitive: false), '');
      late final int bookId;
      await widget.db.transaction(() async {
        bookId = await widget.db.into(widget.db.books).insert(BooksCompanion.insert(
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
      _toast('导入完成：$title，共 ${chapters.length} 章');
      return bookId;
    } catch (e) {
      _toast('导入失败：$e');
      return null;
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _import() async {
    if (_importing) return;
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'docx'],
    );
    if (files.isEmpty || files.first.path == null) return;
    await _persistImport(files.first.path!, files.first.name);
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

  /// 每本书的（章节数, 插图数）
  Future<Map<int, (int, int)>> _loadStats(List<Book> books) async {
    final chapters = await widget.db.select(widget.db.chapters).get();
    final ills = await widget.db.select(widget.db.illustrations).get();
    final chCount = <int, int>{};
    final illCount = <int, int>{};
    for (final c in chapters) {
      chCount[c.bookId] = (chCount[c.bookId] ?? 0) + 1;
    }
    for (final i in ills) {
      illCount[i.bookId] = (illCount[i.bookId] ?? 0) + 1;
    }
    return {for (final b in books) b.id: (chCount[b.id] ?? 0, illCount[b.id] ?? 0)};
  }

  Future<Map<int, (int, int)>> _statsForBooks(List<Book> books) {
    if (!identical(_statsBooks, books)) {
      _statsBooks = books;
      _statsFuture = _loadStats(books);
    }
    return _statsFuture!;
  }

  Widget _bookMenu(Book book) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
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
    );
  }

  Widget _bookCard(Book book, int chapterCount, int illCount) {
    final scheme = Theme.of(context).colorScheme;
    final grad = _coverGradients[book.id % _coverGradients.length];
    final pct = chapterCount == 0 ? 0.0 : ((book.lastChapter + 1) / chapterCount).clamp(0.0, 1.0);
    return Material(
      color: Colors.white,
      elevation: 2,
      shadowColor: Colors.black26,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(
            builder: (_) => ReaderScreen(db: widget.db, bookId: book.id))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: grad,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0, top: 0, bottom: 0,
                width: 4,
                child: ColoredBox(color: Colors.white.withValues(alpha: 0.25)),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(book.format.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white)),
                  ),
                  const Spacer(),
                  Text(book.title,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800, height: 1.3,
                          color: Colors.white,
                          shadows: [Shadow(blurRadius: 4, color: Colors.black38, offset: Offset(0, 2))])),
                ]),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(book.title,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
                ),
                _bookMenu(book),
              ]),
              const SizedBox(height: 6),
              LinearProgressIndicator(
                value: pct,
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: 6),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text('第 ${book.lastChapter + 1} 章 · ${(pct * 100).round()}%',
                    style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFE4E6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.auto_awesome, size: 10, color: Color(0xFFE11D48)),
                    const SizedBox(width: 3),
                    Text('$illCount 图',
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFFE11D48))),
                  ]),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('我的书架',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
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
                  const Text('点击右下角导入本地 TXT / DOCX 小说\n或在文件管理器中用「打开方式」选择生图书',
                      textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          return FutureBuilder<Map<int, (int, int)>>(
            future: _statsForBooks(books),
            builder: (context, statSnap) {
              final stats = statSnap.data;
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 88),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.72,
                ),
                itemCount: books.length,
                itemBuilder: (context, i) {
                  final book = books[i];
                  final (chCount, illCount) = stats?[book.id] ?? (0, 0);
                  return _bookCard(book, chCount, illCount);
                },
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
