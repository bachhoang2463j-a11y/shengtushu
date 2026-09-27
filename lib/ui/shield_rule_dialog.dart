// 「屏蔽」确认框：选区生成的头尾锚点正则 + 本书命中预览，可改正则再应用
import 'dart:async';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../services/clean_service.dart';
import '../services/text_cleaner.dart';

/// 用户确认结果：rule 为最终规则；saveRule 表示同时存进全局规则库（导入时自动应用）
class ShieldDecision {
  final CleanRule rule;
  final bool saveRule;
  const ShieldDecision({required this.rule, required this.saveRule});
}

Future<ShieldDecision?> showShieldRuleDialog(
  BuildContext context, {
  required AppDatabase db,
  required int bookId,
  required CleanRule rule,
}) {
  return showDialog<ShieldDecision>(
    context: context,
    builder: (_) => _ShieldRuleDialog(db: db, bookId: bookId, rule: rule),
  );
}

class _ShieldRuleDialog extends StatefulWidget {
  const _ShieldRuleDialog({required this.db, required this.bookId, required this.rule});

  final AppDatabase db;
  final int bookId;
  final CleanRule rule;

  @override
  State<_ShieldRuleDialog> createState() => _ShieldRuleDialogState();
}

class _ShieldRuleDialogState extends State<_ShieldRuleDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.rule.name);
  late final TextEditingController _pattern = TextEditingController(text: widget.rule.pattern);
  CleanPreview? _preview;
  bool _loading = false;
  String? _error;
  Timer? _debounce;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _pattern.addListener(_onPatternChanged);
    _runPreview();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _name.dispose();
    _pattern.dispose();
    super.dispose();
  }

  void _onPatternChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _runPreview);
  }

  Future<void> _runPreview() async {
    final pattern = _pattern.text.trim();
    final seq = ++_seq;
    if (pattern.isEmpty) {
      setState(() {
        _preview = null;
        _loading = false;
        _error = null;
      });
      return;
    }
    try {
      RegExp(pattern, multiLine: true);
    } on FormatException {
      setState(() {
        _preview = null;
        _loading = false;
        _error = '正则不合法';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final p = await CleanService(widget.db).preview(
        widget.bookId,
        CleanOptions(stripNoise: false, stripMojibake: false, rules: [CleanRule(name: '', pattern: pattern)]),
      );
      if (!mounted || seq != _seq) return;
      setState(() {
        _preview = p;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _preview = null;
        _loading = false;
        _error = '预览失败：$e';
      });
    }
  }

  CleanRule _rule() => CleanRule(
        name: _name.text.trim().isEmpty ? widget.rule.name : _name.text.trim(),
        pattern: _pattern.text.trim(),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _preview;
    final canApply = p != null && p.hits > 0 && !p.wipesBook && !_loading;
    return AlertDialog(
      title: const Text('屏蔽选中内容'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                  labelText: '规则名', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pattern,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '正则（头尾锚点，可修改）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Text(_error!, style: TextStyle(fontSize: 12, color: scheme.error)),
            if (p != null) _previewBox(p, scheme),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消')),
        TextButton(
          onPressed: canApply
              ? () => Navigator.pop(context, ShieldDecision(rule: _rule(), saveRule: false))
              : null,
          child: const Text('仅清理本书'),
        ),
        FilledButton(
          onPressed: canApply
              ? () => Navigator.pop(context, ShieldDecision(rule: _rule(), saveRule: true))
              : null,
          child: const Text('清理并保存规则'),
        ),
      ],
    );
  }

  Widget _previewBox(CleanPreview p, ColorScheme scheme) {
    final warn = <String>[
      if (p.wipesBook) '该规则会清空整本书，已禁用执行',
      if (p.risky && !p.wipesBook) '删除量超过全书三成，请确认规则没有过宽',
      if (p.emptiedChapters.isNotEmpty)
        '将删除 ${p.emptiedChapters.length} 个被清空的章节（连带其插图记录）',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
        p.hits == 0 ? '本书没有命中' : '本书命中 ${p.hits} 处 · 删除 ${p.removed} 字',
        style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: p.hits == 0 ? scheme.onSurfaceVariant : scheme.onSurface),
      ),
      for (final w in warn)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('⚠ $w', style: TextStyle(fontSize: 12, color: scheme.error)),
        ),
      for (final s in p.samples)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(s,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
        ),
    ]);
  }
}
