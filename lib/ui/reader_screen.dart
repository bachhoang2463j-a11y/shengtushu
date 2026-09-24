// 阅读器：分页渲染 / 双翻页模式 / 占位符插图 / 段落生图 / 进度记忆
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../reader/paginator.dart';
import '../services/generation_service.dart';
import '../services/settings_service.dart';
import 'edit_screen.dart';
import 'image_viewer_screen.dart';
import 'settings_screen.dart';
import 'theme_ext.dart';

const double _padH = 20;
const double _padV = 16;

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.db, required this.bookId});
  final AppDatabase db;
  final int bookId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final _gen = GenerationService.instance;
  final _settings = SettingsService.instance;

  Book? _book;
  List<Chapter> _chapters = const [];
  int _chapterIdx = 0;
  Chapter? _chapter;
  Stream<List<Illustration>>? _illsStream;

  List<ReaderPage> _pages = const [];
  String _layoutKey = '';
  bool _computing = false;
  double _pageHeight = 0;

  PageController? _pageCtrl;
  ScrollController? _scrollCtrl;
  int _curPage = 0;
  int? _pendingRestoreParagraph;
  bool _generating = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pageCtrl?.dispose();
    _scrollCtrl?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final book = await (widget.db.select(widget.db.books)..where((t) => t.id.equals(widget.bookId))).getSingle();
    final chapters = await (widget.db.select(widget.db.chapters)
          ..where((t) => t.bookId.equals(widget.bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
        .get();
    if (!mounted || chapters.isEmpty) return;
    setState(() {
      _book = book;
      _chapters = chapters;
      _chapterIdx = book.lastChapter.clamp(0, chapters.length - 1);
      _pendingRestoreParagraph = book.lastParagraph;
    });
    await _loadChapter();
  }

  Future<void> _loadChapter() async {
    final ch = _chapters[_chapterIdx];
    _illsStream = (widget.db.select(widget.db.illustrations)
          ..where((t) => t.chapterId.equals(ch.id))
          ..orderBy([(t) => OrderingTerm.asc(t.afterParagraph)]))
        .watch();
    setState(() {
      _chapter = ch;
      _layoutKey = '';
      _pages = const [];
    });
  }

  Future<void> _switchChapter(int idx) async {
    if (idx < 0 || idx >= _chapters.length) return;
    setState(() {
      _chapterIdx = idx;
      _curPage = 0;
      _pendingRestoreParagraph = 0;
    });
    _pageCtrl?.jumpToPage(0);
    await _loadChapter();
  }

  List<LayoutItem> _buildItems(List<String> paras, List<Illustration> ills) {
    final byIdx = <int, List<Illustration>>{};
    for (final i in ills) {
      (byIdx[i.afterParagraph] ??= []).add(i);
    }
    final items = <LayoutItem>[];
    for (var i = 0; i < paras.length; i++) {
      items.add(TextItem(i, paras[i]));
      for (final ill in byIdx[i] ?? const <Illustration>[]) {
        final aspect = ill.imgHeight == 0 ? 16 / 9 : ill.imgWidth / ill.imgHeight;
        items.add(ImageItem(ImageBlock(
          i,
          illustrationId: ill.id,
          status: ill.status,
          aspect: aspect,
          imagePath: ill.imagePath,
          error: ill.error,
          prompt: ill.prompt,
        )));
      }
    }
    return items;
  }

  Future<void> _recompute(List<String> paras, List<Illustration> ills, Size size) async {
    setState(() => _computing = true);
    await Future<void>.delayed(Duration.zero);
    final config = PageLayoutConfig(
      width: size.width,
      height: size.height,
      fontSize: _settings.fontSize,
      lineHeight: _settings.lineHeight,
      paragraphSpacing: _settings.fontSize * 0.55,
    );
    final pages = Paginator.paginate(items: _buildItems(paras, ills), config: config);
    if (!mounted) return;
    // 锚定当前阅读位置：记住当前页首段
    int anchor = _pendingRestoreParagraph ?? 0;
    if (_pendingRestoreParagraph == null && _pages.isNotEmpty && _curPage < _pages.length) {
      final blocks = _pages[_curPage].blocks;
      anchor = blocks.isEmpty ? 0 : blocks.first.paragraphIndex;
    }
    _pendingRestoreParagraph = null;
    final target = pages.indexWhere((p) => p.blocks.any((b) => b.paragraphIndex >= anchor));
    setState(() {
      _pages = pages;
      _pageHeight = size.height;
      _computing = false;
      _curPage = target < 0 ? 0 : target;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_curPage));
  }

  void _jumpTo(int page) {
    if (_pages.isEmpty) return;
    final p = page.clamp(0, _pages.length - 1);
    if (_settings.pageMode == 'page') {
      if (_pageCtrl?.hasClients ?? false) _pageCtrl!.jumpToPage(p);
    } else {
      final ctrl = _scrollCtrl;
      if ((ctrl?.hasClients ?? false) && _pageHeight > 0) {
        ctrl!.jumpTo((p * _pageHeight).clamp(0.0, ctrl.position.maxScrollExtent));
      }
    }
  }

  void _onPageChanged(int page) {
    _curPage = page;
    _saveProgress();
    if (mounted) setState(() {});
  }

  Future<void> _saveProgress() async {
    if (_book == null || _pages.isEmpty || _curPage >= _pages.length) return;
    final blocks = _pages[_curPage].blocks;
    final first = blocks.isEmpty ? 0 : blocks.first.paragraphIndex;
    await (widget.db.update(widget.db.books)..where((t) => t.id.equals(widget.bookId))).write(
      BooksCompanion(lastChapter: Value(_chapterIdx), lastParagraph: Value(first)),
    );
  }

  // ---------- 生图 ----------

  (int first, List<String>) _currentPageParagraphs() {
    if (_pages.isEmpty || _curPage >= _pages.length) return (0, const []);
    final idxs = _pages[_curPage].blocks.map((b) => b.paragraphIndex).toSet().toList()..sort();
    if (idxs.isEmpty) return (0, const []);
    final first = idxs.first;
    final last = idxs.last;
    final paras = _chapter!.content.split('\n');
    return (first, [for (var i = first; i <= last && i < paras.length; i++) paras[i]]);
  }

  List<String> _historyBefore(int firstParagraph) {
    final paras = _chapter!.content.split('\n');
    final n = _settings.historyCount;
    final start = (firstParagraph - n).clamp(0, paras.length);
    return [for (var i = start; i < firstParagraph; i++) paras[i]];
  }

  Future<void> _generatePage() async {
    final ch = _chapter;
    if (ch == null || _book == null) return;
    final (first, pageParas) = _currentPageParagraphs();
    if (pageParas.isEmpty) {
      _showError('当前页没有可用的段落，翻到有正文的一页再试。');
      return;
    }
    setState(() => _generating = true);
    try {
      final n = await _gen.generateBatch(
        book: _book!,
        chapter: ch,
        pageParagraphs: pageParas,
        firstParagraphIndex: first,
        history: _historyBefore(first),
      );
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已创建 $n 个插图占位符，开始排队生成…')));
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('生图失败'),
        ]),
        content: SingleChildScrollView(child: Text(message, style: const TextStyle(height: 1.6))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('知道了')),
        ],
      ),
    );
  }

  Future<void> _generateSingle(int paragraphIndex) async {
    final ch = _chapter;
    if (ch == null || _book == null) return;
    try {
      await _gen.generateSingle(
        book: _book!,
        chapter: ch,
        paragraphIndex: paragraphIndex,
        history: _historyBefore(paragraphIndex),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已入队生成')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('生图失败：$e')));
      }
    }
  }

  void _showParagraphMenu(int paragraphIndex, String text) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.image_outlined),
            title: const Text('为本段生成插图'),
            onTap: () {
              Navigator.pop(c);
              _generateSingle(paragraphIndex);
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_outlined),
            title: const Text('复制段落'),
            onTap: () {
              Clipboard.setData(ClipboardData(text: text));
              Navigator.pop(c);
            },
          ),
        ]),
      ),
    );
  }

  void _showChapterDrawer() {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: ListView.builder(
          itemCount: _chapters.length,
          itemBuilder: (context, i) => ListTile(
            dense: true,
            selected: i == _chapterIdx,
            title: Text(_chapters[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () {
              Navigator.pop(c);
              _switchChapter(i);
            },
          ),
        ),
      ),
    );
  }

  void _showQueueSheet() {
    showModalBottomSheet(
      context: context,
      builder: (c) => ListenableBuilder(
        listenable: _gen,
        builder: (context, _) {
          final tasks = _gen.queue;
          return SafeArea(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                title: Text('生成队列（${tasks.where((t) => t.status == 'queued' || t.status == 'running').length} 个待处理）'),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  TextButton(onPressed: _gen.retryFailed, child: const Text('重试失败')),
                  TextButton(
                      onPressed: () => _gen.clearQueue(includingPending: true),
                      child: const Text('清空')),
                ]),
              ),
              const Divider(height: 1),
              if (tasks.isEmpty)
                const Padding(padding: EdgeInsets.all(24), child: Text('队列为空')),
              ...tasks.map((t) => ListTile(
                    dense: true,
                    leading: switch (t.status) {
                      'done' => const Icon(Icons.check_circle, color: Colors.green),
                      'running' => const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      'failed' => const Icon(Icons.error_outline, color: Colors.red),
                      _ => const Icon(Icons.schedule, color: Colors.grey),
                    },
                    title: Text(t.promptPreview, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: t.status == 'running'
                        ? LinearProgressIndicator(value: t.progress == 0 ? null : t.progress)
                        : (t.error.isEmpty ? null : Text(t.error,
                            style: const TextStyle(fontSize: 11, color: Colors.red))),
                  )),
            ]),
          );
        },
      ),
    );
  }

  // ---------- 渲染 ----------

  Widget _renderBlock(PageBlock b, double fullWidth, {required int prevParIdx}) {
    if (b is ImageBlock) {
      return _renderImage(b, fullWidth);
    }
    final t = b as TextBlock;
    final spacing = (t.isFirst && t.paragraphIndex > prevParIdx)
        ? SizedBox(height: _settings.fontSize * 0.55)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        spacing,
        GestureDetector(
          onLongPress: () => _showParagraphMenu(t.paragraphIndex, t.text),
          child: Text(
            t.text,
            textAlign: t.isLast ? TextAlign.start : TextAlign.justify,
            style: TextStyle(
              fontSize: _settings.fontSize,
              height: _settings.lineHeight,
              color: context.readerText,
            ),
          ),
        ),
      ],
    );
  }

  Widget _renderImage(ImageBlock b, double fullWidth) {
    final h = (fullWidth / b.aspect.clamp(0.2, 5.0)).clamp(60.0, _pageHeight);
    Widget child;
    switch (b.status) {
      case 'done':
        child = InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ImageViewerScreen(
                  imagePath: b.imagePath ?? '', prompt: b.prompt))),
          child: Image.file(
            File(b.imagePath ?? ''),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const Center(child: Icon(Icons.broken_image)),
          ),
        );
        break;
      case 'running':
        double? ratio;
        for (final t in _gen.queue) {
          if (t.illustrationId == b.illustrationId && t.status == 'running') {
            ratio = t.progress == 0 ? null : t.progress;
          }
        }
        child = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 26, height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.5, value: ratio),
            ),
            const SizedBox(height: 6),
            Text(ratio == null ? '正在生成…' : '${(ratio * 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 12, color: context.readerText)),
          ],
        );
        break;
      case 'failed':
        child = InkWell(
          onTap: () => _gen.retryOne(b.illustrationId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(height: 4),
              Text(b.error, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
              const Text('点按重试', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
        );
        break;
      default: // pending
        child = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.image_outlined, color: Colors.grey.shade500),
          const SizedBox(height: 4),
          Text('插图占位 · 等待生成', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
        ]);
    }
    return Container(
      height: h,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: context.readerBackground == Colors.white ? Colors.grey.shade100 : Colors.grey.shade900,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade400.withValues(alpha: 0.4)),
      ),
      width: fullWidth,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _renderPage(ReaderPage page, double fullWidth) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: _padV),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < page.blocks.length; i++)
            _renderBlock(page.blocks[i], fullWidth,
                prevParIdx: i == 0 ? -1 : page.blocks[i - 1].paragraphIndex),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ch = _chapter;
    if (_book == null || ch == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final paras = ch.content.split('\n');
    return Scaffold(
      backgroundColor: context.readerBackground,
      appBar: AppBar(
        backgroundColor: context.readerBackground,
        title: GestureDetector(
          onTap: _showChapterDrawer,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(child: Text(ch.title, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.arrow_drop_down),
          ]),
        ),
        actions: [
          ListenableBuilder(
            listenable: _gen,
            builder: (context, _) => Stack(children: [
              IconButton(
                tooltip: '生成队列',
                icon: const Icon(Icons.queue_outlined),
                onPressed: _showQueueSheet,
              ),
              if (_gen.isBusy)
                const Positioned(
                  right: 8, top: 8,
                  child: SizedBox(width: 9, height: 9,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                ),
            ]),
          ),
          IconButton(
            tooltip: '编辑本章',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final c = _chapter;
              if (c == null) return;
              await Navigator.push(context,
                  MaterialPageRoute(builder: (_) => EditScreen(db: widget.db, chapter: c)));
              await _loadChapter();
            },
          ),
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => buildSettingsScreen(widget.db))),
          ),
        ],
      ),
      floatingActionButton: _generating
          ? const FloatingActionButton(
              onPressed: null,
              child: SizedBox(
                  width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            )
          : FloatingActionButton.extended(
              onPressed: _generatePage,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('本页生图'),
            ),
      body: StreamBuilder<List<Illustration>>(
        stream: _illsStream,
        builder: (context, illSnap) {
          final ills = illSnap.data ?? const <Illustration>[];
          return LayoutBuilder(builder: (context, cons) {
            final size = Size(
              cons.maxWidth - _padH * 2,
              cons.maxHeight - _padV * 2,
            );
            final key = '${ch.id}|${ch.content.length}|${ills.map((e) => '${e.id}:${e.status}:${e.imgWidth}x${e.imgHeight}').join(',')}'
                '|${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}'
                '|${_settings.fontSize}|${_settings.lineHeight}';
            if (key != _layoutKey && !_computing) {
              _layoutKey = key;
              Future.microtask(() => _recompute(paras, ills, size));
            }
            if (_computing || _pages.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            _pageCtrl ??= PageController(initialPage: _curPage);
            _scrollCtrl ??= ScrollController(
                initialScrollOffset: _curPage * _pageHeight);

            if (_settings.pageMode == 'page') {
              _scrollCtrl = null;
              return PageView.builder(
                controller: _pageCtrl,
                itemCount: _pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, i) => _renderPage(_pages[i], size.width),
              );
            } else {
              _pageCtrl = null;
              final ctrl = _scrollCtrl!;
              if (!ctrl.hasClients) {
                ctrl.addListener(() {
                  if (_pageHeight <= 0) return;
                  final page = (ctrl.offset / _pageHeight).round();
                  if (page != _curPage && page >= 0 && page < _pages.length) {
                    _onPageChanged(page);
                  }
                });
              }
              return ListView.builder(
                controller: ctrl,
                itemExtent: _pageHeight,
                itemCount: _pages.length,
                itemBuilder: (context, i) => _renderPage(_pages[i], size.width),
              );
            }
          });
        },
      ),
      bottomNavigationBar: _pages.isEmpty
          ? null
          : BottomAppBar(
              color: context.readerBackground,
              height: 34,
              padding: EdgeInsets.zero,
              child: Text(
                '  ${_curPage + 1} / ${_pages.length} · 第${_chapterIdx + 1}/${_chapters.length}章',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ),
    );
  }
}
