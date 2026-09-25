// 阅读器：沉浸式排版（demo 原型）/ 连续滚动 + 双翻页模式 / 选中文段生图 / 插图管理 / 进度记忆
import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/database.dart';
import '../reader/paginator.dart';
import '../services/chapter_editor.dart';
import '../services/generation_service.dart';
import '../services/quote_expander.dart';
import '../services/settings_service.dart';
import '../services/tts_service.dart';
import 'image_viewer_screen.dart';
import 'settings_screen.dart';
import 'theme_ext.dart';
import 'widgets.dart';

const double _padH = 22;
const double _padV = 10;
const double _paragraphSpacing = 16;
const String kReaderFontFamily = 'NotoSansSC';
const Color _accent = Color(0xFFE11D48); // demo 主强调色（玫红）

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
  List<int> _pageStartPara = const []; // 每页首段，滚动位置→页 的映射
  String _layoutKey = '';
  bool _repaginating = false;
  int _repaginateSeq = 0;
  double _pageHeight = 0;
  Map<int, Illustration> _illsById = const {};

  // 连续滚动模式：整段流 + 累计顶边偏移（含列表顶部 padding）
  List<LayoutItem> _flowItems = const [];
  List<double> _flowOffsets = const [];
  bool _scrollListening = false;

  PageController? _pageCtrl;
  ScrollController? _scrollCtrl;
  int _curPage = 0;
  int? _pendingRestoreParagraph;
  bool _generating = false;
  String _selectionText = '';
  SelectableRegionState? _selRegionState; // 选区菜单构建时保存，点非文本区域时用来清除选区

  // 插图历史回看偏移：0 = 最新一张，1 = 上一张（更旧），仅阅读会话内有效
  final Map<int, int> _histOffset = {};
  // 历史计数徽标：切换历史版本时短暂显示「N/M」，之后自动消失
  int? _histBadgeId;
  Timer? _histBadgeTimer;

  // 沉浸式交互状态
  bool _overlayVisible = false;
  bool _stylePanelVisible = false;
  String _lastLightTheme = 'sepia';
  DateTime _now = DateTime.now();
  Timer? _clockTimer;

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _load();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _histBadgeTimer?.cancel();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
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
          history: GenerationService.decodeHistory(ill.history),
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
      fontFamily: kReaderFontFamily,
      paragraphSpacing: _paragraphSpacing,
    );
    // 连续滚动模式的数据：整段流 + 与渲染规则一致的测高累计偏移
    final items = _buildItems(paras, ills);
    final heights = Paginator.estimateFlowHeights(items, config, maxImageH: size.height - 12);
    final offsets = Paginator.cumulativeOffsets(heights);
    for (var i = 0; i < offsets.length; i++) {
      offsets[i] += _padV; // ListView 顶部 padding
    }
    if (seq != _repaginateSeq) return;
    if (mounted) {
      setState(() {
        _flowItems = items;
        _flowOffsets = offsets;
      });
    }

    final fresh = <ReaderPage>[];
    await for (final batch in Paginator.paginateStream(items: items, config: config)) {
      if (seq != _repaginateSeq) return; // 已有更新的排版任务
      fresh.addAll(batch);
    }
    if (seq != _repaginateSeq || !mounted) return;

    var target = fresh.indexWhere((p) => p.blocks.any((b) => b.paragraphIndex >= anchor));
    if (target < 0) target = 0;
    setState(() {
      _pages = fresh;
      _pageStartPara = [for (final p in fresh) p.blocks.isEmpty ? 0 : p.blocks.first.paragraphIndex];
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
      if ((ctrl?.hasClients ?? false) && _flowOffsets.isNotEmpty) {
        final blocks = _pages[p].blocks;
        final para = blocks.isEmpty ? 0 : blocks.first.paragraphIndex;
        var idx = _firstItemIndexOfParagraph(para);
        final target = _flowOffsets[idx].clamp(0.0, ctrl!.position.maxScrollExtent);
        ctrl.jumpTo(target);
        // 懒加载列表首帧 maxScrollExtent 未必就绪，下一帧再校准一次
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctrl.hasClients) {
            ctrl.jumpTo(_flowOffsets[idx].clamp(0.0, ctrl.position.maxScrollExtent));
          }
        });
      }
    }
  }

  int _firstItemIndexOfParagraph(int para) {
    for (var i = 0; i < _flowItems.length; i++) {
      if (_flowItems[i].paragraphIndex >= para) return i;
    }
    return _flowItems.isEmpty ? 0 : _flowItems.length - 1;
  }

  void _onScroll() {
    if (_flowOffsets.isEmpty || _pageStartPara.isEmpty) return;
    final ctrl = _scrollCtrl;
    if (ctrl == null || !ctrl.hasClients) return;
    final idx = Paginator.flowIndexAtOffset(_flowOffsets, ctrl.offset);
    final para = idx < _flowItems.length ? _flowItems[idx].paragraphIndex : 0;
    final page = _pageForParagraph(para);
    if (page >= 0 && page != _curPage) _onPageChanged(page);
  }

  /// 段落 → 所在页（页首段单调递增，可二分）
  int _pageForParagraph(int para) {
    var lo = 0, hi = _pageStartPara.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (_pageStartPara[mid] <= para) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
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

  // ---------- 沉浸式交互（demo：三分区点击 / 呼出栏 / 排版面板） ----------

  /// 点按非文本区域时清除文字选区（SelectionArea 只在点按可选文本时收起，图片/空白处不会）
  void _dismissSelection() {
    _selRegionState
      ?..hideToolbar()
      ..clearSelection();
  }

  void _handleTapUp(TapUpDetails d) {
    // 有活动选区时先清除选区（不翻页），下一次点按再正常生效
    if (_selectionText.isNotEmpty) {
      _dismissSelection();
      return;
    }
    // 只有左右翻页模式启用三分区；滚动模式点哪都只呼出/收起控制栏（避免误触翻动）
    if (_settings.pageMode == 'page') {
      final frac = d.localPosition.dx / MediaQuery.sizeOf(context).width;
      if (frac < 0.25) {
        _pageShift(-1);
        return;
      }
      if (frac > 0.75) {
        _pageShift(1);
        return;
      }
    }
    _toggleOverlay();
  }

  void _pageShift(int delta) {
    if (_pages.isEmpty) return;
    _jumpTo((_curPage + delta).clamp(0, _pages.length - 1));
  }

  void _toggleOverlay() {
    setState(() {
      _overlayVisible = !_overlayVisible;
      if (!_overlayVisible) _stylePanelVisible = false;
    });
  }

  void _toggleDark() {
    final cur = _settings.themeMode;
    if (cur == 'dark') {
      _settings.setThemeMode(_lastLightTheme);
    } else {
      _lastLightTheme = cur;
      _settings.setThemeMode('dark');
    }
  }

  void _adjustFontSize(double delta) {
    final v = (_settings.fontSize + delta).clamp(12.0, 32.0);
    _settings.setFontSize(v);
  }

  Widget _miniHeader(Chapter ch) {
    final c = context.readerSub;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');
    return SizedBox(
      height: 38,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 10, _padH, 4),
        child: Row(children: [
          Expanded(
            child: GestureDetector(
              onTap: _showChapterDrawer,
              child: Text(ch.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: c, letterSpacing: 0.2)),
            ),
          ),
          Text('$hh:$mm', style: TextStyle(fontSize: 11, color: c, letterSpacing: 0.2)),
        ]),
      ),
    );
  }

  Widget _miniFooter() {
    final c = context.readerSub;
    final total = _pages.length;
    final pct = total == 0 ? '' : '${(((_curPage + 1) / total) * 100).toStringAsFixed(1)}%';
    return SizedBox(
      height: 34,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(_padH, 0, _padH, 6),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('第 ${_curPage + 1} / $total 页', style: TextStyle(fontSize: 11, color: c, letterSpacing: 0.2)),
          Text(pct, style: TextStyle(fontSize: 11, color: c, letterSpacing: 0.2)),
        ]),
      ),
    );
  }

  Widget _queueAction() {
    return ListenableBuilder(
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
    );
  }

  Widget _overlayTop() {
    return Positioned(
      top: 0, left: 0, right: 0,
      child: AnimatedSlide(
        offset: _overlayVisible ? Offset.zero : const Offset(0, -1.2),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: Material(
          color: context.readerBackground.withValues(alpha: 0.96),
          child: IgnorePointer(
            ignoring: !_overlayVisible,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  IconButton(
                    tooltip: '返回书架',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: _showChapterDrawer,
                      child: Text(
                        _book?.title ?? '',
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: context.readerText),
                      ),
                    ),
                  ),
                  _queueAction(),
                  IconButton(
                    tooltip: '设置',
                    icon: const Icon(Icons.settings_outlined),
                    onPressed: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => buildSettingsScreen(widget.db))),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayBottom() {
    final ch = _chapter!;
    final total = _pages.length;
    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: AnimatedSlide(
        offset: _overlayVisible ? Offset.zero : const Offset(0, 1.2),
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: Material(
          color: context.readerBackground.withValues(alpha: 0.96),
          child: IgnorePointer(
            ignoring: !_overlayVisible,
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('第 ${_curPage + 1} / $total 页 · ${ch.title}',
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: context.readerSub)),
                  Row(children: [
                    TextButton(
                      onPressed: _chapterIdx > 0 ? () => _switchChapter(_chapterIdx - 1) : null,
                      child: const Text('上一章'),
                    ),
                    Expanded(
                      child: Slider(
                        value: total == 0 ? 1 : (_curPage + 1).clamp(1, total).toDouble(),
                        min: 1,
                        max: total < 1 ? 1 : total.toDouble(),
                        onChanged: total < 1 ? null : (v) => _jumpTo(v.toInt() - 1),
                        onChangeEnd: (_) => _saveProgress(),
                      ),
                    ),
                    TextButton(
                      onPressed: _chapterIdx < _chapters.length - 1
                          ? () => _switchChapter(_chapterIdx + 1)
                          : null,
                      child: const Text('下一章'),
                    ),
                  ]),
                  Row(children: [
                    _overlayAction(Icons.menu_book_outlined, '目录', _showChapterDrawer),
                    _overlayAction(Icons.photo_library_outlined, '图片', _showImageManager),
                    _overlayAction(Icons.text_fields, '排版',
                        () => setState(() => _stylePanelVisible = !_stylePanelVisible)),
                    _overlayAction(
                        _settings.themeMode == 'dark'
                            ? Icons.light_mode_outlined
                            : Icons.dark_mode_outlined,
                        '夜间', _toggleDark),
                    _overlayAction(Icons.auto_awesome, '本页生图', _generatePage, color: _accent),
                  ]),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _overlayAction(IconData icon, String label, VoidCallback onTap, {Color? color}) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 20, color: color ?? context.readerText),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color ?? context.readerText)),
          ]),
        ),
      ),
    );
  }

  Widget _stylePanelCard() {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.16), blurRadius: 35, offset: const Offset(0, 12)),
        ],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Text('字号调节',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _fontBtn('A −', () => _adjustFontSize(-1)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(_settings.fontSize.toStringAsFixed(0),
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
              ),
              _fontBtn('A +', () => _adjustFontSize(1)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Text('背景主题',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: scheme.onSurface)),
          const Spacer(),
          _swatch('sepia', const Color(0xFFF5EEDB)),
          const SizedBox(width: 10),
          _swatch('light', const Color(0xFFFAFAFA)),
          const SizedBox(width: 10),
          _swatch('green', const Color(0xFFE3EDE4)),
          const SizedBox(width: 10),
          _swatch('dark', const Color(0xFF151719)),
        ]),
      ]),
    );
  }

  Widget _fontBtn(String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        child: Text(label,
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: scheme.onSurface)),
      ),
    );
  }

  Widget _swatch(String theme, Color color) {
    final active = _settings.themeMode == theme;
    return GestureDetector(
      onTap: () {
        if (theme != 'dark') _lastLightTheme = theme;
        _settings.setThemeMode(theme);
      },
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
              color: active ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
        ),
      ),
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
    if (_generating) return; // 防重复触发
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
      if (mounted) _showError(_friendlyError(e));
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
      if (mounted) _showError(_friendlyError(e));
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  /// 朗读选中文本：选区两侧/自身有 "…" 时自动扩展/剥离为引号内文本（QuoteExpander）。
  /// 说明：SDK 无编程式选区 API，视觉选区无法自动扩到引号内；
  /// 扩展在点击朗读时完成，「朗读中」提示条会显示将要朗读的完整文本。
  Future<void> _speakSelection(String sel) async {
    final ch = _chapter;
    var text = sel.trim();
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先长按滑动选中一段文字')));
      return;
    }
    if (ch != null) {
      text = QuoteExpander.expand(ch.content.split('\n'), text,
          hintParagraph: _currentAnchorParagraph());
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: const Duration(minutes: 10),
      content: Text('朗读中：${text.length > 24 ? '${text.substring(0, 24)}…' : text}'),
      action: SnackBarAction(label: '停止', onPressed: () => TtsService.instance.stop()),
    ));
    try {
      await TtsService.instance.speak(text);
      messenger.hideCurrentSnackBar(); // 播完自动收起
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text('朗读失败：${_friendlyError(e)}')));
    }
  }

  /// 把底层网络异常翻译成可操作的提示（如 HandshakeException 多为代理/系统时间问题）
  String _friendlyError(Object e) {
    final s = e.toString();
    if (s.contains('HandshakeException')) {
      return '网络握手失败（HandshakeException），无法与服务器建立 HTTPS 连接。\n\n'
          '检查：① 手机网络是否可用 ② 代理 / VPN 是否拦截了 API 域名 ③ 系统时间是否正确';
    }
    return s;
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


  /// 插图管理面板（demo 式 bottom sheet：拖动把手 + 提示词预览卡 + 圆角动作按钮）
  /// 大图页删除当前查看的这张：删文件并同步 DB（当前图被删则提升最近一张历史）
  Future<void> _deleteCurrentImage(int illustrationId, String path) async {
    await _gen.deleteIllustrationImages({illustrationId: [path]});
    _histOffset.remove(illustrationId); // 提升后重新对齐到最新一张
    if (mounted) Navigator.pop(context); // 关闭大图页，回阅读器
  }

  /// 跳到指定段落（图片管理跳转用）
  void _jumpToParagraph(int para) {
    if (_pages.isEmpty) return;
    if (_settings.pageMode == 'page') {
      var page = _pageForParagraph(para);
      if (page < 0) page = 0;
      _jumpTo(page);
    } else {
      final ctrl = _scrollCtrl;
      if ((ctrl?.hasClients ?? false) && _flowOffsets.isNotEmpty) {
        final idx = _firstItemIndexOfParagraph(para);
        ctrl!.jumpTo(_flowOffsets[idx].clamp(0.0, ctrl.position.maxScrollExtent));
      }
    }
  }

  /// 图片管理面板：本书全部插图（含历史版本），点按查看该图并跳段落，多选删除
  void _showImageManager() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (c) => _ImageManagerSheet(
        db: widget.db,
        bookId: widget.bookId,
        onOpen: (it) {
          Navigator.pop(c);
          _viewHistoryImage(it.illId, it.path);
          _jumpToParagraph(it.para);
        },
        onCompress: () => _gen.compressBookImages(widget.bookId),
        onDelete: _gen.deleteIllustrationImages,
      ),
    );
  }

  /// 图片管理点按：把该插图在阅读器里切换到被点的这张
  void _viewHistoryImage(int illId, String path) {
    final live = _illsById[illId];
    if (live == null) return;
    final paths = [
      ...GenerationService.decodeHistory(live.history),
      if ((live.imagePath ?? '').isNotEmpty) live.imagePath!,
    ];
    final idx = paths.indexOf(path);
    if (idx < 0) return;
    setState(() => _histOffset[illId] = paths.length - 1 - idx);
  }

  void _showImageMenu(ImageBlock b) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 38, height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.6)),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('当前插图提示词',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant)),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: b.prompt));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('提示词已复制')));
                    },
                    child: Text('复制',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: scheme.primary)),
                  ),
                ]),
                const SizedBox(height: 6),
                Text(
                  b.prompt.isEmpty ? '（无提示词）' : b.prompt,
                  style: TextStyle(fontSize: 12, height: 1.5, color: scheme.onSurface),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            _sheetBtn(c, Icons.zoom_in_outlined, '查看高清大图', () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(
                      imagePath: b.imagePath ?? '', prompt: b.prompt,
                      onDelete: (b.imagePath ?? '').isEmpty
                          ? null
                          : () => _deleteCurrentImage(b.illustrationId, b.imagePath!))));
            }),
            _sheetBtn(c, Icons.edit_note_outlined, '修改提示词并重新生图', () async {
              Navigator.pop(c);
              final v = await textInputDialog(context,
                  title: '生图提示词', initial: b.prompt, maxLines: 6);
              if (v != null && v.trim().isNotEmpty) {
                await _gen.updatePromptAndRegenerate(b.illustrationId, v);
              }
            }),
            _sheetBtn(c, Icons.refresh_outlined, '仅重新生图', () {
              Navigator.pop(c);
              _gen.regenerate(b.illustrationId);
            }),
            _sheetBtn(c, Icons.delete_outline, '删除插图', () async {
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
            }, danger: true),
          ]),
        ),
      ),
    );
  }

  Widget _sheetBtn(BuildContext c, IconData icon, String label, VoidCallback onTap, {bool danger = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: danger ? scheme.errorContainer : scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 18, color: danger ? scheme.error : scheme.onSurface),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: danger ? scheme.error : scheme.onSurface)),
            ]),
          ),
        ),
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

  TextStyle _bodyTextStyle() {
    return TextStyle(
      fontSize: _settings.fontSize,
      height: _settings.lineHeight,
      fontFamily: kReaderFontFamily,
      color: context.readerText,
    );
  }

  Widget _textBody(String text) {
    // 空段渲染为一行高，与分页器/流测高的口径一致
    if (text.isEmpty) {
      return SizedBox(height: _settings.fontSize * _settings.lineHeight);
    }
    return Text(text, textAlign: TextAlign.justify, style: _bodyTextStyle());
  }

  Widget _renderBlock(PageBlock b, double fullWidth, {required int prevParIdx}) {
    if (b is ImageBlock) {
      return _renderImage(b, fullWidth);
    }
    final t = b as TextBlock;
    final spacing = (t.isFirst && t.paragraphIndex > prevParIdx)
        ? SizedBox(height: _paragraphSpacing)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        spacing,
        // 不加 GestureDetector：长按必须交给 SelectionArea 原生选字
        _textBody(t.text),
      ],
    );
  }

  /// 连续滚动模式：整段/插图直接渲染，不按页切块（段落永不劈开、间距均匀）
  Widget _renderFlowItem(LayoutItem item, double fullWidth, {required int prevParIdx}) {
    if (item is ImageItem) {
      return _renderImage(item.block, fullWidth);
    }
    final t = item as TextItem;
    final spacing = (t.paragraphIndex > prevParIdx)
        ? SizedBox(height: _paragraphSpacing)
        : const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        spacing,
        _textBody(t.text),
      ],
    );
  }

  /// 历史切换共用：更新偏移并短暂显示计数徽标
  void _setHistOffset(int illustrationId, int offset) {
    setState(() {
      _histOffset[illustrationId] = offset;
      _histBadgeId = illustrationId;
    });
    _histBadgeTimer?.cancel();
    _histBadgeTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _histBadgeId = null);
    });
  }

  /// 左侧竖带历史步进：dir=+1 向更旧（左下），dir=-1 向更新（左上）；到边界无反应
  void _stepImage(int illustrationId, int total, int dir) {
    final next = (_histOffset[illustrationId] ?? 0) + dir;
    if (next < 0 || next > total - 1) return;
    _setHistOffset(illustrationId, next);
  }

  /// 右侧中部「切下一张」：向更新方向步进，到最新后绕回最旧循环浏览
  void _cycleNextImage(int illustrationId, int total) {
    if (total <= 1) return;
    _setHistOffset(illustrationId, ((_histOffset[illustrationId] ?? 0) + total - 1) % total);
  }

  /// 右侧热区快速重生成分流：slot 1 = 第一工作流（右上 1/3），slot 2 = 第二工作流（右下 1/3）
  Future<void> _regenWithSlot(int illustrationId, int slot) async {
    if (slot == 2) {
      final rows =
          await (widget.db.select(widget.db.workflows)..where((t) => t.isSecond.equals(true))).get();
      if (rows.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('未设置第二工作流：到 设置 → 工作流管理，点某个工作流的「第二」按钮')));
        }
        return;
      }
    }
    if ((_histOffset[illustrationId] ?? 0) != 0) {
      setState(() => _histOffset[illustrationId] = 0); // 从旧版本直接重生：回到最新视图等新图
    }
    await _gen.regenerate(illustrationId, useSecond: slot == 2);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已用第${slot == 2 ? '二' : '一'}工作流重新生成')));
    }
  }

  Widget _renderImage(ImageBlock b, double fullWidth) {
    // 实时状态：排版缓存里只有布局信息，状态/路径以数据库最新值为准（进度变化不触发重排版）
    final live = _illsById[b.illustrationId];
    final status = live?.status ?? b.status;
    final imagePath = live?.imagePath ?? b.imagePath;
    final error = live?.error ?? b.error;
    final prompt = live?.prompt ?? b.prompt;
    final h = (fullWidth / b.aspect.clamp(0.2, 5.0)).clamp(60.0, _pageHeight - 12);
    // 多版本：history（旧→新）+ 当前图；offset 0 = 最新一张。
    // DB 实时值优先（原始 JSON 需解码），排版缓存里已是解码后的列表。
    final List<String> hist;
    final l = live;
    if (l != null) {
      hist = GenerationService.decodeHistory(l.history);
    } else {
      hist = b.history;
    }
    final paths = [
      ...hist,
      if (imagePath != null && imagePath.isNotEmpty) imagePath,
    ];
    final histTotal = paths.length;
    final histOffset = histTotal == 0 ? 0 : (_histOffset[b.illustrationId] ?? 0).clamp(0, histTotal - 1);
    // 当前正在查看的那张（offset 0 = 最新）；切图/大图/删除都以它为准
    final shown = paths.isEmpty ? null : paths[paths.length - 1 - histOffset];
    Widget child;
    switch (status) {
      case 'done':
        child = GestureDetector(
          key: ValueKey('ill-gesture-${b.illustrationId}'),
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) {
            // 有文字选区时点图片：先清除选区，本次点按不作他用
            if (_selectionText.isNotEmpty) {
              _dismissSelection();
              return;
            }
            // 热区按实际渲染宽算：fullWidth 是屏宽，外层 Padding 左右各收窄 _padH
            final imgW = fullWidth - 2 * _padH;
            final frac = d.localPosition.dx / imgW;
            final dy = d.localPosition.dy;
            if (frac < 0.2) {
              // 左侧竖带：上半切到更新一版，下半切到更旧一版
              _stepImage(b.illustrationId, histTotal, dy < h / 2 ? -1 : 1);
            } else if (frac >= 0.8) {
              // 右侧竖带三段：上 1/3 第一工作流重生，中 1/3 切下一张，下 1/3 第二工作流重生
              if (dy < h / 3) {
                _regenWithSlot(b.illustrationId, 1);
              } else if (dy >= h * 2 / 3) {
                _regenWithSlot(b.illustrationId, 2);
              } else {
                _cycleNextImage(b.illustrationId, histTotal);
              }
            } else {
              Navigator.push(context, MaterialPageRoute(
                  builder: (_) => ImageViewerScreen(
                      imagePath: shown ?? '', prompt: prompt,
                      onDelete: (shown ?? '').isEmpty
                          ? null
                          : () => _deleteCurrentImage(b.illustrationId, shown!))));
            }
          },
          child: Image.file(
            File(shown ?? ''),
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
        imagePath: shown,
        error: error,
        prompt: prompt,
        history: paths,
      )),
      child: Stack(children: [
        Container(
          height: h,
          margin: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey.shade900
                : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey.shade400.withValues(alpha: 0.4)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 20, offset: const Offset(0, 6)),
            ],
          ),
          width: fullWidth,
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
        // 历史计数徽标：切换历史版本后短暂显示，随后自动淡出
        Positioned(
          left: 14, bottom: 14,
          child: IgnorePointer(
            child: AnimatedOpacity(
              opacity: (_histBadgeId == b.illustrationId && histTotal > 1) ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${histTotal - histOffset}/$histTotal',
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ),
        ),
      ]),
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

  /// 选中文字后的浮动菜单：生图 / 朗读 / 编辑 / 复制 / 全选（demo 胶囊样式，AdaptiveTextSelectionToolbar 负责锚定）
  Widget _selectionMenu(BuildContext context, SelectableRegionState selectableRegionState) {
    _selRegionState = selectableRegionState;
    final endpoints = selectableRegionState.selectionEndpoints;
    return AdaptiveTextSelectionToolbar(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: endpoints.last.point,
        secondaryAnchor: endpoints.first.point,
      ),
      children: [
        Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(999),
          color: const Color(0xFF1E293B),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _pillButton(
                '生图', Icons.auto_awesome,
                primary: true,
                onTap: () {
                  // 先捕获选区文本，再清除（清除会同步触发 onSelectionChanged(null)）
                  final sel = _selectionText;
                  selectableRegionState.hideToolbar();
                  selectableRegionState.clearSelection();
                  _generateFromSelection(sel);
                },
              ),
              _pillButton(
                '朗读', Icons.volume_up_outlined,
                onTap: () {
                  // 先捕获选区文本，再清除（清除会同步触发 onSelectionChanged(null)）
                  final sel = _selectionText;
                  selectableRegionState.hideToolbar();
                  selectableRegionState.clearSelection();
                  _speakSelection(sel);
                },
              ),
              _pillButton('编辑', Icons.edit_outlined,
                  onTap: () => _editSelection(selectableRegionState)),
              _pillButton('复制', Icons.copy_outlined, onTap: () {
                // ignore: deprecated_member_use
                selectableRegionState.copySelection(SelectionChangedCause.toolbar);
                selectableRegionState.hideToolbar();
              }),
              _pillButton('全选', Icons.select_all_outlined, onTap: () {
                selectableRegionState.selectAll(SelectionChangedCause.toolbar);
                selectableRegionState.hideToolbar();
              }),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _pillButton(String label, IconData icon, {required VoidCallback onTap, bool primary = false}) {
    const fg = Color(0xFFE2E8F0);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: primary
            ? BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFFE11D48), Color(0xFFF43F5E)]),
                borderRadius: BorderRadius.circular(999),
              )
            : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: primary ? Colors.white : fg),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: primary ? Colors.white : fg)),
        ]),
      ),
    );
  }

  // ---------- 组装 ----------

  Widget _buildContent(List<LayoutItem> items, Size size) {
    if (_pages.isEmpty || items.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    _pageCtrl ??= PageController(initialPage: _curPage);
    _scrollCtrl ??= ScrollController();

    Widget content;
    if (_settings.pageMode == 'page') {
      content = PageView.builder(
        controller: _pageCtrl,
        itemCount: _pages.length,
        onPageChanged: _onPageChanged,
        itemBuilder: (context, i) => _renderPage(_pages[i], size.width),
      );
    } else {
      final ctrl = _scrollCtrl!;
      if (!_scrollListening) {
        _scrollListening = true;
        ctrl.addListener(_onScroll);
      }
      if (!ctrl.hasClients) {
        // 首次挂载 / 重排版后重挂：跳回当前阅读位置
        WidgetsBinding.instance.addPostFrameCallback((_) => _jumpTo(_curPage));
      }
      content = ListView.builder(
        controller: ctrl,
        padding: const EdgeInsets.symmetric(horizontal: _padH, vertical: _padV),
        itemCount: _flowItems.length,
        itemBuilder: (context, i) => _renderFlowItem(
          _flowItems[i],
          size.width,
          prevParIdx: i == 0 ? -1 : _flowItems[i - 1].paragraphIndex,
        ),
      );
    }
    return SelectionArea(
      onSelectionChanged: (sel) => _selectionText = sel?.plainText ?? '',
      contextMenuBuilder: _selectionMenu,
      child: Stack(children: [
        Positioned.fill(
          child: GestureDetector(
            // 三分区点击：左上一页 / 右下一页 / 中央呼出控制栏（demo 交互）
            behavior: HitTestBehavior.opaque,
            onTapUp: _handleTapUp,
            child: content,
          ),
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

  @override
  Widget build(BuildContext context) {
    final ch = _chapter;
    if (_book == null || ch == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final paras = ch.content.split('\n');
    return Scaffold(
      backgroundColor: context.readerBackground,
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
            return Stack(children: [
              Column(children: [
                _miniHeader(ch),
                Expanded(child: _buildContent(_flowItems, size)),
                _miniFooter(),
              ]),
              _overlayTop(),
              // 快捷排版抽屉（悬浮于底栏之上）
              Positioned(
                left: 16, right: 16,
                bottom: MediaQuery.paddingOf(context).bottom + 160,
                child: AnimatedSlide(
                  offset: _stylePanelVisible ? Offset.zero : const Offset(0, 0.3),
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  child: AnimatedOpacity(
                    opacity: _stylePanelVisible ? 1 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: IgnorePointer(
                      ignoring: !_stylePanelVisible,
                      child: _stylePanelCard(),
                    ),
                  ),
                ),
              ),
              _overlayBottom(),
            ]);
          });
        },
      ),
    );
  }
}

/// 图片管理面板：显示本书生成的所有图片（含历史版本），
/// 点按跳转到对应段落；多选删除以清理体积。
class _ImageManagerSheet extends StatefulWidget {
  const _ImageManagerSheet({
    required this.db,
    required this.bookId,
    required this.onOpen,
    required this.onCompress,
    required this.onDelete,
  });

  final AppDatabase db;
  final int bookId;
  final void Function(({int illId, int para, String path, bool current})) onOpen;
  final Future<int> Function() onCompress;
  final Future<void> Function(Map<int, List<String>> targets) onDelete;

  @override
  State<_ImageManagerSheet> createState() => _ImageManagerSheetState();
}

class _ImageManagerSheetState extends State<_ImageManagerSheet> {
  List<({int illId, int para, String path, bool current})> _items = const [];
  final Set<String> _selected = {};
  bool _multi = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await (widget.db.select(widget.db.illustrations)
          ..where((t) => t.bookId.equals(widget.bookId))
          ..orderBy([(t) => OrderingTerm.asc(t.afterParagraph)]))
        .get();
    final items = <({int illId, int para, String path, bool current})>[];
    for (final ill in rows) {
      for (final h in GenerationService.decodeHistory(ill.history)) {
        items.add((illId: ill.id, para: ill.afterParagraph, path: h, current: false));
      }
      final cur = ill.imagePath;
      if (cur != null && cur.isNotEmpty) {
        items.add((illId: ill.id, para: ill.afterParagraph, path: cur, current: true));
      }
    }
    if (mounted) {
      setState(() {
        _items = items;
        _loading = false;
      });
    }
  }

  Future<void> _deleteSelected() async {
    final byIll = <int, List<String>>{};
    for (final it in _items) {
      if (_selected.contains(it.path)) (byIll[it.illId] ??= []).add(it.path);
    }
    if (byIll.isEmpty) return;
    await widget.onDelete(byIll);
    _selected.clear();
    await _load();
  }

  Future<void> _confirmDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除所选图片'),
        content: Text('将删除 ${_selected.length} 张图片文件，当前图被删后该位置回到待生成，确定？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) await _deleteSelected();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaQuery.heightOf(context) * 0.75,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(children: [
            Text('图片管理 · ${_items.length} 张',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const Spacer(),
            TextButton(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                final kb = await widget.onCompress();
                await _load();
                messenger.showSnackBar(SnackBar(
                    content: Text(kb > 0
                        ? '已压缩存量 PNG，节省 ${(kb / 1024).toStringAsFixed(1)} MB'
                        : '没有需要压缩的 PNG 图片')));
              },
              child: const Text('压缩存储'),
            ),
            TextButton(
              onPressed: () => setState(() {
                _multi = !_multi;
                _selected.clear();
              }),
              child: Text(_multi ? '退出多选' : '多选'),
            ),
            if (_multi)
              TextButton(
                onPressed: _selected.isEmpty ? null : _confirmDelete,
                style: TextButton.styleFrom(foregroundColor: scheme.error),
                child: Text('删除所选${_selected.isEmpty ? '' : '(${_selected.length})'}'),
              ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? Center(
                      child: Text('本书还没有生成过插图',
                          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant)))
                  : GridView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 0.75,
                      ),
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final it = _items[i];
                        final sel = _selected.contains(it.path);
                        return InkWell(
                          onTap: () {
                            if (_multi) {
                              setState(() {
                                sel ? _selected.remove(it.path) : _selected.add(it.path);
                              });
                            } else {
                              widget.onOpen(it);
                            }
                          },
                          borderRadius: BorderRadius.circular(10),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: Stack(fit: StackFit.expand, children: [
                              Image.file(
                                File(it.path),
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  color: scheme.surfaceContainerHighest,
                                  child: const Center(child: Icon(Icons.broken_image)),
                                ),
                              ),
                              Positioned(
                                left: 0, right: 0, bottom: 0,
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(6, 10, 6, 5),
                                  decoration: const BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [Colors.transparent, Colors.black54],
                                    ),
                                  ),
                                  child: Text(
                                    '第 ${it.para + 1} 段 · ${it.current ? '当前' : '历史'}',
                                    maxLines: 1, overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                                  ),
                                ),
                              ),
                              if (_multi)
                                Positioned(
                                  top: 4, right: 4,
                                  child: Icon(
                                    sel ? Icons.check_circle : Icons.radio_button_unchecked,
                                    size: 20,
                                    color: sel ? scheme.primary : Colors.white,
                                  ),
                                ),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
