// 工作流节点映射：为 API 格式 JSON 标记可替换字段
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../services/comfyui_client.dart';

class _NodeInfo {
  final String id;
  final String classType;
  final Map<String, dynamic> inputs;
  const _NodeInfo(this.id, this.classType, this.inputs);
}

class WorkflowMapScreen extends StatefulWidget {
  const WorkflowMapScreen({super.key, required this.db, required this.workflow});
  final AppDatabase db;
  final Workflow workflow;

  @override
  State<WorkflowMapScreen> createState() => _WorkflowMapScreenState();
}

class _WorkflowMapScreenState extends State<WorkflowMapScreen> {
  late WorkflowMapping _mapping;

  @override
  void initState() {
    super.initState();
    _mapping = WorkflowMapping.fromJson(widget.workflow.mapping);
  }

  List<_NodeInfo> _parseNodes() {
    try {
      final j = jsonDecode(widget.workflow.apiJson) as Map<String, dynamic>;
      final nodes = <_NodeInfo>[];
      j.forEach((id, v) {
        if (v is Map<String, dynamic>) {
          final cls = v['class_type']?.toString() ?? '?';
          final inputs = v['inputs'];
          nodes.add(_NodeInfo(id, cls, inputs is Map<String, dynamic> ? inputs : const {}));
        }
      });
      return nodes;
    } catch (_) {
      return const [];
    }
  }

  /// 每个角色的候选「node:field」：文本字段 → 提示词类；数字字段 → 尺寸/种子/批次类
  List<String> _candidates(List<_NodeInfo> nodes, {required bool text}) {
    final out = <String>[];
    for (final n in nodes) {
      n.inputs.forEach((field, value) {
        final isString = value is String;
        final isNum = value is num;
        if (text && isString) out.add('${n.id}:$field');
        if (!text && isNum) out.add('${n.id}:$field');
      });
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _parseNodes();
    if (nodes.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.workflow.name)),
        body: const Center(child: Text('工作流 JSON 解析失败')),
      );
    }
    final roles = [
      ('positive', '正向提示词', true, 'LLM 提炼的插图提示词会写入这里'),
      ('negative', '负向提示词', false, '可留空'),
      ('width', '宽度', false, '阅读器生成时会覆盖为设置值'),
      ('height', '高度', false, ''),
      ('seed', '种子', false, '勾选「随机种子」后每次覆盖'),
      ('batch', '批次数', false, ''),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text('映射 · ${widget.workflow.name}'),
        actions: [
          TextButton(
            onPressed: () async {
              final m = WorkflowMapping(
                positive: _mapping.positive, negative: _mapping.negative,
                width: _mapping.width, height: _mapping.height,
                seed: _mapping.seed, batch: _mapping.batch,
              );
              final json = jsonEncode(m.toJson());
              await (widget.db.update(widget.db.workflows)..where((t) => t.id.equals(widget.workflow.id)))
                  .write(WorkflowsCompanion(mapping: Value(json)));
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('映射已保存')));
                Navigator.pop(context);
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('共 ${nodes.length} 个节点。至少映射「正向提示词」；无需替换的字段可以不映射。',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 12),
          for (final (key, label, isText, hint) in roles)
            _roleEditor(context, nodes, key, label, isText, hint),
          const SizedBox(height: 12),
          const Divider(),
          Text('节点一览', style: Theme.of(context).textTheme.titleSmall),
          ...nodes.map((n) => ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text('#${n.id} · ${n.classType}'),
                subtitle: Text(n.inputs.keys.join(', '), style: const TextStyle(fontSize: 11)),
              )),
        ],
      ),
    );
  }

  Widget _roleEditor(BuildContext context, List<_NodeInfo> nodes, String key,
      String label, bool isText, String hint) {
    final candidates = _candidates(nodes, text: isText);
    final current = switch (key) {
      'positive' => _mapping.positive,
      'negative' => _mapping.negative,
      'width' => _mapping.width,
      'height' => _mapping.height,
      'seed' => _mapping.seed,
      'batch' => _mapping.batch,
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          border: const OutlineInputBorder(),
        ),
        child: DropdownButton<String>(
          isDense: true,
          isExpanded: true,
          underline: const SizedBox.shrink(),
          hint: Text(current == null ? '（不映射）' : '', style: const TextStyle(fontSize: 12)),
          value: current,
          items: [
            const DropdownMenuItem(value: '', child: Text('（不映射）', style: TextStyle(fontSize: 12))),
            ...candidates.map((c) => DropdownMenuItem(
                value: c, child: Text(c, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')))),
          ],
          onChanged: (v) {
            setState(() {
              final val = (v == null || v.isEmpty) ? null : v;
              switch (key) {
                case 'positive': _mapping = WorkflowMapping(positive: val, negative: _mapping.negative, width: _mapping.width, height: _mapping.height, seed: _mapping.seed, batch: _mapping.batch);
                case 'negative': _mapping = WorkflowMapping(positive: _mapping.positive, negative: val, width: _mapping.width, height: _mapping.height, seed: _mapping.seed, batch: _mapping.batch);
                case 'width': _mapping = WorkflowMapping(positive: _mapping.positive, negative: _mapping.negative, width: val, height: _mapping.height, seed: _mapping.seed, batch: _mapping.batch);
                case 'height': _mapping = WorkflowMapping(positive: _mapping.positive, negative: _mapping.negative, width: _mapping.width, height: val, seed: _mapping.seed, batch: _mapping.batch);
                case 'seed': _mapping = WorkflowMapping(positive: _mapping.positive, negative: _mapping.negative, width: _mapping.width, height: _mapping.height, seed: val, batch: _mapping.batch);
                case 'batch': _mapping = WorkflowMapping(positive: _mapping.positive, negative: _mapping.negative, width: _mapping.width, height: _mapping.height, seed: _mapping.seed, batch: val);
              }
            });
          },
        ),
      ),
    );
  }
}
