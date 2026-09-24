// 章节纯文本编辑：保存后按锚点哈希重定位插图
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';

class EditScreen extends StatefulWidget {
  const EditScreen({super.key, required this.db, required this.chapter});
  final AppDatabase db;
  final Chapter chapter;

  @override
  State<EditScreen> createState() => _EditScreenState();
}

class _EditScreenState extends State<EditScreen> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.chapter.content);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final newContent = _ctrl.text.trim();
    if (newContent.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('内容不能为空')));
      return;
    }
    final newParas = newContent.split('\n');
    final newHashes = {for (var i = 0; i < newParas.length; i++) _hash(newParas[i]): i};

    await widget.db.transaction(() async {
      // 1. 更新章节内容
      await (widget.db.update(widget.db.chapters)..where((t) => t.id.equals(widget.chapter.id)))
          .write(ChaptersCompanion(content: Value(newContent)));
      // 2. 重锚定：按内容哈希找到新位置；找不到则夹紧到有效范围
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
        title: Text('编辑 · ${widget.chapter.title}', maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton(onPressed: _save, child: const Text('保存')),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _ctrl,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(
            hintText: '段落之间用换行分隔（空行会被归并）',
            border: InputBorder.none,
          ),
          style: const TextStyle(fontSize: 15, height: 1.6),
        ),
      ),
    );
  }
}
