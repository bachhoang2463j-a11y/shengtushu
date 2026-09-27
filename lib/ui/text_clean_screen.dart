// 文本清洗（单本）：按当前口径对已导入的书跑一次，先预览命中再落库
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../services/clean_service.dart';
import '../services/library_activity.dart';
import '../services/settings_service.dart';
import '../services/text_cleaner.dart';
import 'widgets.dart';

class TextCleanScreen extends StatefulWidget {
  const TextCleanScreen({super.key, required this.db, required this.book});
  final AppDatabase db;
  final Book book;

  @override
  State<TextCleanScreen> createState() => _TextCleanScreenState();
}

class _TextCleanScreenState extends State<TextCleanScreen> {
  final _s = SettingsService.instance;

  late bool _noise = _s.cleanStripNoise;
  late bool _mojibake = _s.cleanStripMojibake;
  late final List<CleanRule> _rules = List.of(_s.cleanRules);

  /// 本次要应用的规则下标（不影响全局启用状态）
  final Set<int> _picked = {};

  CleanPreview? _preview;
  bool _busy = false;
  bool _stale = true;

  CleanService get _clean => CleanService(widget.db);

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < _rules.length; i++) {
      if (_rules[i].enabled) _picked.add(i);
    }
  }

  CleanOptions get _options => CleanOptions(
        stripNoise: _noise,
        stripMojibake: _mojibake,
        rules: [
          for (var i = 0; i < _rules.length; i++)
            if (_picked.contains(i)) _rules[i],
        ],
      );

  void _markDirty() => setState(() {
        _stale = true;
        _preview = null;
      });

  Future<void> _runPreview() async {
    final o = _options;
    if (o.isNoop) {
      setState(() {
        _preview = null;
        _stale = false;
      });
      return;
    }
    setState(() => _busy = true);
    try {
      final p = await _clean.preview(widget.book.id, o);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _busy = false;
        _stale = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast('预览失败：$e');
    }
  }

  Future<void> _apply() async {
    final p = _preview;
    if (p == null) return;
    if (p.wipesBook) {
      _toast('该配置会清空整本书，已中止');
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('执行文本清洗'),
        content: Text(
          '将删除 ${p.removed} 字'
          '${p.touched.isEmpty ? '' : '，影响 ${p.touched.length} 章'}'
          '${p.emptiedChapters.isEmpty ? '' : '，并删除 ${p.emptiedChapters.length} 个被清空的章节'}'
          '。正文改动不可撤销，确定？',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('执行')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await LibraryActivity.instance.write(() => _clean.apply(widget.book.id, _options));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _stale = true;
        _preview = null;
      });
      _toast(r.any
          ? '清洗完成：改 ${r.changed} 章 · 删除 ${r.removed} 字'
              '${r.deleted > 0 ? ' · 删除 ${r.deleted} 章' : ''}'
          : '没有需要清理的内容');
    } on LibraryBusyException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message);
    } on StateError catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      _toast(e.message);
    }
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text('文本清洗 · ${widget.book.title}')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SectionHeader(title: '清理项'),
          SettingRow(
            title: '去乱码碎片',
            subtitle: '删除「z u E w9 c w I8 a」这类空格分隔的字母/数字碎片',
            trailing: Switch(
              value: _noise,
              onChanged: (v) => setState(() {
                _noise = v;
                _markDirty();
              }),
            ),
          ),
          SettingRow(
            title: '替换字符与莫忘码',
            subtitle: '删除 �、锟斤拷、烫烫烫、???、□□□',
            trailing: Switch(
              value: _mojibake,
              onChanged: (v) => setState(() {
                _mojibake = v;
                _markDirty();
              }),
            ),
          ),
          const SectionHeader(title: '屏蔽正则规则（勾选本次应用）'),
          if (_rules.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('规则库为空。可在阅读器里选中垃圾内容后点「屏蔽」生成。',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          for (var i = 0; i < _rules.length; i++)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _picked.contains(i),
              title: Text(_rules[i].name, style: const TextStyle(fontSize: 14)),
              subtitle: Text(_rules[i].pattern,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
              onChanged: (v) => setState(() {
                v == true ? _picked.add(i) : _picked.remove(i);
                _markDirty();
              }),
            ),
          const SizedBox(height: 12),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _runPreview,
              icon: const Icon(Icons.search, size: 18),
              label: const Text('预览命中'),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              onPressed: (_busy || _stale || _preview == null || _preview!.wipesBook) ? null : _apply,
              icon: const Icon(Icons.cleaning_services_outlined, size: 18),
              label: const Text('开始清理'),
            ),
          ]),
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(minHeight: 2),
          ),
          if (_stale && !_busy)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Text('配置已改动，请重新预览', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          if (_preview != null) _previewCard(_preview!, scheme),
        ],
      ),
    );
  }

  Widget _previewCard(CleanPreview p, ColorScheme scheme) {
    final touched = p.touched;
    return Card(
      margin: const EdgeInsets.only(top: 14),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('命中 ${p.hits} 处 · 删除 ${p.removed} 字 · 影响 ${touched.length} 章',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          if (p.wipesBook)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('⚠ 该配置会清空整本书，禁止执行',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            )
          else if (p.risky)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('⚠ 删除量超过全书三成，请确认规则没有过宽',
                  style: TextStyle(fontSize: 12, color: scheme.error)),
            ),
          if (touched.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('没有可清理的内容', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
          for (final c in touched.take(12))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                c.emptied
                    ? '${c.title} · 整章清空 → 将删除'
                    : '${c.title} · 删 ${c.removed} 字${c.hits > 0 ? '（命中 ${c.hits} 处）' : ''}',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12,
                    color: c.emptied ? scheme.error : scheme.onSurfaceVariant),
              ),
            ),
          if (touched.length > 12)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('…另有 ${touched.length - 12} 章',
                  style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
            ),
        ]),
      ),
    );
  }
}
