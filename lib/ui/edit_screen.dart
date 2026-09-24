// 章节纯文本编辑（页窗口模式）：只编辑指定段落区间，保存后按锚点哈希重定位插图。
// 整章一个巨型 TextField 是 Flutter 著名的卡顿源，按页窗口编辑可完全避开。
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({
    super.key,
    required this.db,
    required this.chapter,
    required this.startParagraph,
    required this.endParagraph,
  }) : assert(startParagraph <= endParagraph);

  final AppDatabase db;
  final Chapter chapter;
  final int startParagraph; // 0-based，含
  final int endParagraph; // 0-based，含

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _ctrl;
  late final List<String> _oldParas;

  @override
  void initState() {
    super.initState();
    _oldParas = widget.chapter.content.split('\n');
    _ctrl = TextEditingController(
        text: _oldParas.sublist(widget.startParagraph, widget.endParagraph + 1).join('\n'));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final edited = _ctrl.text.trim();
    if (edited.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内容不能为空')));
      return;
    }
    final editedParas = edited.split('\n');
    final newParas = [
      ..._oldParas.sublist(0, widget.startParagraph),
      ...editedParas,
      ..._oldParas.sublist(widget.endParagraph + 1),
    ];
    final newHashes = {for (var i = 0; i < newParas.length; i++) _hash(newParas[i]): i};
    final newContent = newParas.join('\n');

    await widget.db.transaction(() async {
      await (widget.db.update(widget.db.chapters)..where((t) => t.id.equals(widget.chapter.id)))
          .write(ChaptersCompanion(content: Value(newContent)));
      // 重锚定：按内容哈希找新位置；找不到则夹紧到有效范围
      final ills = await (widget.db.select(widget.db.illustrations)
            ..where((t) => t.chapterId.equals(widget.chapter.id)))
          .get();
      for (final ill in ills) {
        var newIdx = newHashes[ill.anchorHash];
        newIdx ??= ill.afterParagraph.clamp(0, newParas.length - 1);
        if (newIdx != ill.afterParagraph) {
          await (widget.db.update(widget.db.illustrations)..where((t) => t.id.equals(ill.id)))
              .write(IllustrationsCompanion(afterParagraph: Value(newIdx)));
        }
      }
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('已保存，插图锚点已重定位')));
      Navigator.pop(context);
    }
  }

  String _hash(String s) {
    var h = 0x811c9dc5;
    for (final code in s.runes) {
      h ^= code & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= (code >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('编辑第 ${widget.startParagraph + 1}-${widget.endParagraph + 1} 段',
            style: const TextStyle(fontSize: 16)),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Expanded(
            child: TextField(
              controller: _ctrl,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                hintText: '编辑本页段落，段落之间用换行分隔',
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontSize: 15, height: 1.6),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('窗口编辑模式：仅编辑本页段落，避免整章大文本卡顿',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
        ]),
      ),
    );
  }
}
