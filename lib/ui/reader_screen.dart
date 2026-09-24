// 阅读器：流式分页 / 双翻页模式 / 选中文段生图 / 插图管理 / 进度记忆
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../reader/paginator.dart';
import '../services/chapter_editor.dart';
import '../services/generation_service.dart';
import '../services/settings_service.dart';
import 'image_viewer_screen.dart';
import 'settings_screen.dart';
import 'theme_ext.dart';
import 'widgets.dart';

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
  bool _repaginating = false;
  int _repaginateSeq = 0;
  double _pageHeight = 0;
  Map<int, Illustration> _illsById = const {};

  PageController? _pageCtrl;
  ScrollController? _scrollCtrl;
  int _curPage = 0;
  int? _pendingRestoreParagraph;
  bool _generating = false;
  String _selectionText = '';

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
      _curPage = 0;
      _selectionText = '';
    });
  }

  Future<void> _switchChapter(int idx) async {
    if (idx < 0 || idx >= _chapters.length) return;
    setState(() {
      _chapterIdx = idx;
      _pendingRestoreParagraph = 0;
    });
    await _loadChapter();
  }

  List<LayoutItem> _buildItems(List<String> paras, List<Illustration> ills) {
    final byIdx = <int, List<Illustration>>{};
    for (final i in ills) {
      (byIdx[i.afterParagraph] ??= []).add(i);
    }
    final items = <LayoutItem>[];
    for (var i = 0; i < paras.length; i++) {
      final para = paras[i];
      final list = byIdx[i] ?? const <Illustration>[];
      if (list.isEmpty) {
        items.add(TextItem(i, para));
        continue;
      }
      // 段中插图：按偏移把段落拆成多段文本，图插在精确位置
      list.sort((a, b) {
        final oa = (a.anchorOffset < 0 || a.anchorOffset > para.length) ? para.length : a.anchorOffset;
        final ob = (b.anchorOffset < 0 || b.anchorOffset > para.length) ? para.length : b.anchorOffset;
        return oa.compareTo(ob);
      });
      var cursor = 0;
      for (final ill in list) {
        final off = (ill.anchorOffset < 0 || ill.anchorOffset > para.length) ? para.length : ill.anchorOffset;
        if (off > cursor) {
          items.add(TextItem(i, para.substring(cursor, off)));
          cursor = off;
        }
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
      if (cursor < para.length) {
        items.add(TextItem(i, para.substring(cursor)));
      }
    }
    return items;
  }

  /// 当前阅读位置锚点（当前页首段）
  int _currentAnchorParagraph() {
    if (_pages.isEmpty || _curPage >= _pages.length) return 0;
    final blocks = _pages[_curPage].blocks;
    return blocks.isEmpty ? 0 : blocks.first.paragraphIndex;
  }

  /// 流式重排版：期间旧页面保持可见可翻，完成后按段落锚点回位
  Future<void> _recompute(List<String> paras, List<Illustration> ills, Size size) async {
    final seq = ++_repaginateSeq;
    final anchor = _pendingRestoreParagraph ?? _currentAnchorParagraph();
    _pendingRestoreParagraph = null;
    if (mounted) setState(() => _repaginating = true);

    final config = PageLayoutConfig(
      width: size.width,
      height: size.height,
      fontSize: _settings.fontSize,
      lineHeight: _settings.lineHeight,
      paragraphSpacing: _settings.fontSize * 0.55,
    );
    final fresh = <ReaderPage>[];
    await for (final batch in Paginator.paginateStream(items: _buildItems(paras, ills), config: config)) {
      if (seq != _repaginateSeq) return; // 已有更新的排版任务
      fresh.addAll(batch);
    }
    if (seq != _repaginateSeq || !mounted) return;

    var target = fresh.indexWhere((p) => p.blocks.any((b) => b.paragraphIndex >= anchor));
    if (target < 0) target = 0;
    setState(() {
      _pages = fresh;
      _pageHeight = size.height;
      _repaginating = false;
      _curPage = target.clamp(0, fresh.length - 1);
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
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已创建 $n 个插图占位符（插在第 ${first + 1} 段之后），开始排队生成…')));
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 选中文段生图：只发所选文字，插图精确插在选区末尾（支持段中、跨段、不限长度）
  Future<void> _generateFromSelection(String sel) async {
    final ch = _chapter;
    if (ch == null || _book == null) return;
    sel = sel.trim();
    if (sel.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先长按滑动选中一段文字')));
      return;
    }
    final paras = ch.content.split('\n');
    var (anchor, offset) = GenerationService.locateSelectionEnd(
        paras, sel, hintParagraph: _currentAnchorParagraph());
    if (anchor < 0) {
      // 选区尾部无法定位（罕见），退化为当前页末段之后
      anchor = _currentPageParagraphs().$1;
      offset = -1;
    }
    setState(() => _generating = true);
    try {
      final n = await _gen.generateSelection(
        book: _book!,
        chapter: ch,
        selectionText: sel,
        endParagraphIndex: anchor,
        endCharOffset: offset,
        history: _historyBefore(anchor),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('已创建 $n 个插图占位符（插在第 ${anchor + 1} 段${offset >= 0 ? '选区末尾' : '末尾'}）…')));
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


  void _showImageMenu(ImageBlock b) {
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.zoom_in_outlined),
            title: const Text('查看大图'),
            onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(
                      imagePath: b.imagePath ?? '', prompt: b.prompt)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('修改提示词并重新生图'),
            onTap: () async {
              Navigator.pop(c);
              final v = await textInputDialog(context,
                  title: '生图提示词', initial: b.prompt, maxLines: 6);
              if (v != null && v.trim().isNotEmpty) {
                await _gen.updatePromptAndRegenerate(b.illustrationId, v);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.refresh_outlined),
            title: const Text('仅重新生图'),
            onTap: () {
              Navigator.pop(c);
              _gen.regenerate(b.illustrationId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('删除插图', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(c);
              final ok = await showDialog<bool>(
                context: context,
                builder: (cc) => AlertDialog(
                  title: const Text('删除插图'),
                  content: const Text('将删除该插图及其图片文件，确定？'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(cc, false), child: const Text('取消')),
                    FilledButton(onPressed: () => Navigator.pop(cc, true), child: const Text('删除')),
                  ],
                ),
              );
              if (ok == true) await _gen.deleteIllustration(b.illustrationId);
            },
          ),
        ]),
      ),
    );
  }

  /// 选区编辑：选中哪段改哪段，保存后精确替换回选区并重定位插图
  Future<void> _editSelection(SelectableRegionState selectableRegionState) async {
    final ch = _chapter;
    if (ch == null) return;
    final sel = _selectionText.trim();
    final paras = ch.content.split('\n');
    final hint = _currentAnchorParagraph();
    final (sP, sO) = ChapterEditor.locateSelectionStart(paras, sel, hintParagraph: hint);
    final (eP, eO) = GenerationService.locateSelectionEnd(paras, sel, hintParagraph: hint);
    selectableRegionState.hideToolbar();
    selectableRegionState.clearSelection();
    if (sP < 0 || eP < 0 || (eP == sP && eO <= sO)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('无法定位选区，请重新选择')));
      }
      return;
    }
    final edited = await textInputDialog(context, title: '编辑选中文字', initial: sel, maxLines: 12);
    if (edited == null || edited.trim().isEmpty || edited == sel.trim()) return;
    await ChapterEditor.replaceSelection(widget.db, ch,
        startPara: sP, startOffset: sO, endPara: eP, endOffset: eO, editedText: edited);
    await _loadChapter();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，插图锚点已重定位')));
    }
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
        // 不加 GestureDetector：长按必须交给 SelectionArea 原生选字
        Text(
          t.text,
          textAlign: t.isLast ? TextAlign.start : TextAlign.justify,
          style: TextStyle(
            fontSize: _settings.fontSize,
            height: _settings.lineHeight,
            color: context.readerText,
          ),
        ),
      ],
    );
  }

  Widget _renderImage(ImageBlock b, double fullWidth) {
    // 实时状态：排版缓存里只有布局信息，状态/路径以数据库最新值为准（进度变化不触发重排版）
    final live = _illsById[b.illustrationId];
    final status = live?.status ?? b.status;
    final imagePath = live?.imagePath ?? b.imagePath;
    final error = live?.error ?? b.error;
    final prompt = live?.prompt ?? b.prompt;
    final h = (fullWidth / b.aspect.clamp(0.2, 5.0)).clamp(60.0, _pageHeight);
    Widget child;
    switch (status) {
      case 'done':
        child = InkWell(
          onTap: () => Navigator.push(context, MaterialPageRoute(
              builder: (_) => ImageViewerScreen(
                  imagePath: imagePath ?? '', prompt: prompt))),
          child: Image.file(
            File(imagePath ?? ''),
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
          onTap: () => _gen.regenerate(b.illustrationId),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, color: Colors.red),
              const SizedBox(height: 4),
              Text(error, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Colors.red)),
              const Text('长按插图可管理 · 点按重试', style: TextStyle(fontSize: 12, color: Colors.grey)),
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
    return GestureDetector(
      onLongPress: () => _showImageMenu(ImageBlock(
        b.paragraphIndex,
        illustrationId: b.illustrationId,
        status: status,
        aspect: b.aspect,
        imagePath: imagePath,
        error: error,
        prompt: prompt,
      )),
      child: Container(
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
      ),
    );
  }

  Widget _renderPage(ReaderPage page, double fullWidth) {
    // SelectionArea 在列表层统一包裹（支持跨页选择），页面内只做纯排版
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

  /// 选中文字后的浮动菜单：生图 / 复制 / 全选（AdaptiveTextSelectionToolbar 负责锚定定位）
  Widget _selectionMenu(BuildContext context, SelectableRegionState selectableRegionState) {
    final endpoints = selectableRegionState.selectionEndpoints;
    return AdaptiveTextSelectionToolbar(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: endpoints.last.point,
        secondaryAnchor: endpoints.first.point,
      ),
      children: [
        Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(10),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              TextButton.icon(
                onPressed: () {
                  // 先捕获选区文本，再清除（清除会同步触发 onSelectionChanged(null)）
                  final sel = _selectionText;
                  selectableRegionState.hideToolbar();
                  selectableRegionState.clearSelection();
                  _generateFromSelection(sel);
                },
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('生图'),
              ),
              TextButton.icon(
                onPressed: () => _editSelection(selectableRegionState),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
              TextButton.icon(
                onPressed: () {
                  // ignore: deprecated_member_use
                  selectableRegionState.copySelection(SelectionChangedCause.toolbar);
                  selectableRegionState.hideToolbar();
                },
                icon: const Icon(Icons.copy_outlined, size: 18),
                label: const Text('复制'),
              ),
              TextButton.icon(
                onPressed: () {
                  selectableRegionState.selectAll(SelectionChangedCause.toolbar);
                  selectableRegionState.hideToolbar();
                },
                icon: const Icon(Icons.select_all_outlined, size: 18),
                label: const Text('全选'),
              ),
            ]),
          ),
        ),
      ],
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
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => buildSettingsScreen(widget.db))),
          ),
        ],
      ),
      floatingActionButton: (_settings.showGenFab && !_generating)
          ? FloatingActionButton.extended(
              onPressed: _generatePage,
              icon: const Icon(Icons.auto_awesome),
              label: const Text('本页生图'),
            )
          : (_generating
              ? const FloatingActionButton(
                  onPressed: null,
                  child: SizedBox(
                      width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
                )
              : null),
      body: StreamBuilder<List<Illustration>>(
        stream: _illsStream,
        builder: (context, illSnap) {
          final ills = illSnap.data ?? const <Illustration>[];
          _illsById = {for (final i in ills) i.id: i};
          return LayoutBuilder(builder: (context, cons) {
            final size = Size(
              cons.maxWidth - _padH * 2,
              cons.maxHeight - _padV * 2,
            );
            // 版面键只含影响布局的因素：段落内容 / 插图 id 与宽高 / 页面尺寸 / 字号行距。
            // 生成状态与进度变化不触发重排版（占位符内部自行刷新）。
            final key = '${ch.id}|${ch.content.length}|'
                '${ills.map((e) => '${e.id}:${e.imgWidth}x${e.imgHeight}').join(',')}'
                '|${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}'
                '|${_settings.fontSize}|${_settings.lineHeight}';
            if (key != _layoutKey && !_repaginating) {
              _layoutKey = key;
              Future.microtask(() => _recompute(paras, ills, size));
            }
            if (_pages.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }
            _pageCtrl ??= PageController(initialPage: _curPage);
            _scrollCtrl ??= ScrollController();

            if (_settings.pageMode == 'page') {
              return SelectionArea(
                onSelectionChanged: (sel) => _selectionText = sel?.plainText ?? '',
                contextMenuBuilder: _selectionMenu,
                child: Stack(children: [
                  PageView.builder(
                    controller: _pageCtrl,
                    itemCount: _pages.length,
                    onPageChanged: _onPageChanged,
                    itemBuilder: (context, i) => _renderPage(_pages[i], size.width),
                  ),
                  if (_repaginating)
                    Positioned(
                      top: 6, right: 16,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.black45,
                        label: const Text('排版中…',
                            style: TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                ]),
              );
            } else {
              final ctrl = _scrollCtrl!;
              if (!ctrl.hasClients) {
                ctrl.addListener(() {
                  if (_pageHeight <= 0) return;
                  final page = (ctrl.offset / _pageHeight).round();
                  if (page != _curPage && page >= 0 && page < _pages.length) {
                    _onPageChanged(page);
                  }
                });
                // 首次挂载：跳回当前阅读位置
                WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_curPage));
              }
              return SelectionArea(
                onSelectionChanged: (sel) => _selectionText = sel?.plainText ?? '',
                contextMenuBuilder: _selectionMenu,
                child: Stack(children: [
                  ListView.builder(
                    controller: ctrl,
                    itemExtent: _pageHeight,
                    itemCount: _pages.length,
                    itemBuilder: (context, i) => _renderPage(_pages[i], size.width),
                  ),
                  if (_repaginating)
                    Positioned(
                      top: 6, right: 16,
                      child: Chip(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: Colors.black45,
                        label: const Text('排版中…',
                            style: TextStyle(fontSize: 11, color: Colors.white)),
                      ),
                    ),
                ]),
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
