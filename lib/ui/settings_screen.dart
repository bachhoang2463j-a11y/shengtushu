// 设置页：阅读偏好 / LLM / ComfyUI / 生成参数 / 工作流 / 模板 / 人物预设 / 章节正则
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../services/comfyui_client.dart';
import '../services/default_workflow.dart';
import '../services/settings_service.dart';
import 'widgets.dart';
import 'workflow_map_screen.dart';

Widget buildSettingsScreen(AppDatabase db) => SettingsScreen(db: db);

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _s = SettingsService.instance;
  final _comfy = ComfyUIClient();
  String? _testResult;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          const SectionHeader(title: '阅读'),
          SettingRow(
            title: '字号',
            subtitle: _s.fontSize.toStringAsFixed(1),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _s.fontSize, min: 12, max: 32, divisions: 20,
                label: _s.fontSize.toStringAsFixed(1),
                onChanged: (v) => _s.setFontSize(v),
              ),
            ),
          ),
          SettingRow(
            title: '行距',
            subtitle: _s.lineHeight.toStringAsFixed(2),
            trailing: SizedBox(
              width: 160,
              child: Slider(
                value: _s.lineHeight, min: 1.2, max: 2.2, divisions: 20,
                label: _s.lineHeight.toStringAsFixed(2),
                onChanged: (v) => _s.setLineHeight(v),
              ),
            ),
          ),
          SettingRow(
            title: '主题',
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'light', label: Text('明亮')),
                ButtonSegment(value: 'sepia', label: Text('羊皮')),
                ButtonSegment(value: 'green', label: Text('护眼')),
                ButtonSegment(value: 'dark', label: Text('夜间')),
              ],
              selected: {_s.themeMode},
              onSelectionChanged: (v) => _s.setThemeMode(v.first),
            ),
          ),
          SettingRow(
            title: '翻页模式',
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'page', label: Text('左右翻页')),
                ButtonSegment(value: 'scroll', label: Text('上下滚动')),
              ],
              selected: {_s.pageMode},
              onSelectionChanged: (v) => _s.setPageMode(v.first),
            ),
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('显示「本页生图」按钮'),
            subtitle: const Text('默认关闭，避免遮挡正文；关闭时可用选中文段的方式生图'),
            value: _s.showGenFab,
            onChanged: (v) => _s.setShowGenFab(v),
          ),
          SettingRow(
            title: '章节分割正则',
            subtitle: _s.chapterRegex,
            onTap: () async {
              final v = await textInputDialog(context, title: '章节分割正则', initial: _s.chapterRegex);
              if (v != null && v.trim().isNotEmpty) await _s.setChapterRegex(v.trim());
            },
          ),

          const SectionHeader(title: 'LLM（OpenAI 兼容）'),
          SettingRow(
            title: 'API 地址',
            subtitle: _s.llm.baseUrl,
            onTap: () async {
              final v = await textInputDialog(context, title: 'API 地址', initial: _s.llm.baseUrl, hint: 'https://api.deepseek.com');
              if (v != null && v.trim().isNotEmpty) {
                final c = _s.llm..baseUrl = v.trim();
                await _s.setLlm(c);
              }
            },
          ),
          SettingRow(
            title: 'API Key',
            subtitle: _s.llm.apiKey.isEmpty ? '未设置' : '••••••••',
            onTap: () async {
              final v = await textInputDialog(context, title: 'API Key', initial: _s.llm.apiKey, obscure: true);
              if (v != null) await _s.setLlm(_s.llm..apiKey = v.trim());
            },
          ),
          SettingRow(
            title: '模型',
            subtitle: _s.llm.model,
            onTap: () async {
              final v = await textInputDialog(context, title: '模型名', initial: _s.llm.model, hint: 'deepseek-chat');
              if (v != null && v.trim().isNotEmpty) await _s.setLlm(_s.llm..model = v.trim());
            },
          ),

          const SectionHeader(title: 'ComfyUI'),
          SettingRow(
            title: '服务器地址',
            subtitle: _s.comfyUrl,
            onTap: () async {
              final v = await textInputDialog(context, title: 'ComfyUI 地址', initial: _s.comfyUrl, hint: 'http://192.168.1.100:8188');
              if (v != null && v.trim().isNotEmpty) await _s.setComfyUrl(v.trim());
            },
          ),
          SettingRow(
            title: '连通测试',
            subtitle: _testResult,
            trailing: const Icon(Icons.wifi_tethering),
            onTap: () async {
              setState(() => _testResult = '测试中…');
              final (ok, detail) = await _comfy.testConnection(_s.comfyUrl);
              setState(() => _testResult = (ok ? '✅ ' : '❌ ') + detail);
            },
          ),

          const SectionHeader(title: '生成参数'),
          SettingRow(
            title: '分辨率',
            subtitle: '${_s.genWidth} × ${_s.genHeight}',
            onTap: () => _editResolution(),
          ),
          SettingRow(
            title: '失败重试次数',
            subtitle: '${_s.genRetry}',
            onTap: () async {
              final v = await textInputDialog(context, title: '失败重试次数', initial: '${_s.genRetry}');
              final n = int.tryParse(v ?? '');
              if (n != null && n >= 0 && n <= 10) await _s.setGenParams(retry: n);
            },
          ),
          SettingRow(
            title: '前文上下文段数',
            subtitle: '${_s.historyCount}',
            onTap: () async {
              final v = await textInputDialog(context, title: '前文上下文段数（1-20）', initial: '${_s.historyCount}');
              final n = int.tryParse(v ?? '');
              if (n != null && n >= 0 && n <= 20) await _s.setGenParams(historyCount: n);
            },
          ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            title: const Text('每次生成随机种子'),
            value: _s.autoRandomSeed,
            onChanged: (v) => _s.setGenParams(autoRandomSeed: v),
          ),

          const SectionHeader(title: '生图模板'),
          SettingRow(
            title: '独立生图模板（多消息）',
            subtitle: '占位符：<!--历史上下文--> <!--设定说明--> <!--生词模版--> <!--人物列表--> <!--当前文本-->',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => TemplateEditorScreen(db: widget.db))),
          ),
          SettingRow(
            title: '生词模版（文风/画质要求）',
            subtitle: _s.styleText.split('\n').first,
            onTap: () async {
              final v = await textInputDialog(context, title: '生词模版', initial: _s.styleText, maxLines: 10);
              if (v != null) await _s.setStyleText(v);
            },
          ),
          SettingRow(
            title: '人物预设',
            subtitle: '固定特征标签注入 <!--人物列表-->',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const PersonaEditorScreen())),
          ),

          const SectionHeader(title: '工作流'),
          SettingRow(
            title: 'ComfyUI 工作流管理',
            subtitle: '导入 API 格式 JSON 并标记提示词/尺寸/种子节点',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => WorkflowManagerScreen(db: widget.db))),
          ),
        ],
      ),
    );
  }

  Future<void> _editResolution() async {
    final wCtrl = TextEditingController(text: '${_s.genWidth}');
    final hCtrl = TextEditingController(text: '${_s.genHeight}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('生成分辨率'),
        content: Row(children: [
          Expanded(child: TextField(controller: wCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '宽'))),
          const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('×')),
          Expanded(child: TextField(controller: hCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: '高'))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    final w = int.tryParse(wCtrl.text), h = int.tryParse(hCtrl.text);
    if (ok == true && w != null && h != null && w >= 64 && h >= 64) {
      await _s.setGenParams(width: w, height: h);
      if (mounted) setState(() {});
    }
  }
}

// ==================== 人物预设编辑 ====================
class PersonaEditorScreen extends StatefulWidget {
  const PersonaEditorScreen({super.key});
  @override
  State<PersonaEditorScreen> createState() => _PersonaEditorScreenState();
}

class _PersonaEditorScreenState extends State<PersonaEditorScreen> {
  final _s = SettingsService.instance;

  @override
  Widget build(BuildContext context) {
    final list = _s.personas;
    return Scaffold(
      appBar: AppBar(
        title: const Text('人物预设'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _edit(null),
          ),
        ],
      ),
      body: list.isEmpty
          ? const Center(child: Text('暂无人物预设\n\n例：名字「苏晚」，标签「long white hair, red eyes」', textAlign: TextAlign.center))
          : ListView.builder(
              itemCount: list.length,
              itemBuilder: (context, i) {
                final p = list[i];
                return ListTile(
                  title: Text(p.name),
                  subtitle: Text(p.tags, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(value: p.enabled, onChanged: (v) {
                      p.enabled = v;
                      _s.setPersonas(list);
                    }),
                    IconButton(icon: const Icon(Icons.delete_outline), onPressed: () {
                      setState(() => list.removeAt(i));
                      _s.setPersonas(list);
                    }),
                  ]),
                  onTap: () => _edit(p),
                );
              },
            ),
    );
  }

  Future<void> _edit(PersonaPreset? p) async {
    final nameCtrl = TextEditingController(text: p?.name ?? '');
    final tagsCtrl = TextEditingController(text: p?.tags ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(p == null ? '新增人物' : '编辑人物'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: '名字')),
          const SizedBox(height: 8),
          TextField(controller: tagsCtrl, maxLines: 3, decoration: const InputDecoration(labelText: '固定特征标签（SD tags）')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
        ],
      ),
    );
    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      final list = _s.personas;
      if (p == null) {
        list.add(PersonaPreset(name: nameCtrl.text.trim(), tags: tagsCtrl.text.trim(), enabled: true));
      } else {
        p.name = nameCtrl.text.trim();
        p.tags = tagsCtrl.text.trim();
      }
      await _s.setPersonas(list);
      if (mounted) setState(() {});
    }
  }
}

// ==================== 模板编辑器 ====================
class TemplateEditorScreen extends StatefulWidget {
  const TemplateEditorScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<TemplateEditorScreen> createState() => _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends State<TemplateEditorScreen> {
  final _s = SettingsService.instance;

  @override
  Widget build(BuildContext context) {
    final msgs = _s.indepTemplate;
    return Scaffold(
      appBar: AppBar(
        title: const Text('独立生图模板'),
        actions: [
          IconButton(
            tooltip: '恢复默认',
            icon: const Icon(Icons.restart_alt),
            onPressed: () async {
              await _s.resetIndepTemplate();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _edit(null),
        child: const Icon(Icons.add),
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: msgs.length,
        itemBuilder: (context, i) {
          final m = msgs[i];
          return Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: _roleBadge(m.role),
              title: Text(
                m.content.replaceAll('\n', ' '),
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: m.content.contains('<!--') ? const Text('含占位符', style: TextStyle(fontSize: 12)) : null,
              onTap: () => _edit(m),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: () async {
                  msgs.removeAt(i);
                  await _s.setIndepTemplate(msgs);
                  setState(() {});
                },
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _roleBadge(String role) => Chip(
        label: Text(role, style: const TextStyle(fontSize: 11)),
        visualDensity: VisualDensity.compact,
        backgroundColor: switch (role) {
          'system' => Colors.deepPurple.shade100,
          'user' => Colors.blue.shade100,
          _ => Colors.orange.shade100,
        },
      );

  Future<void> _edit(TplMessage? m) async {
    final contentCtrl = TextEditingController(text: m?.content ?? '');
    var role = m?.role ?? 'system';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setDlg) => AlertDialog(
          title: Text(m == null ? '新增消息' : '编辑消息'),
          content: SizedBox(
            width: 480,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: '角色'),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('system')),
                  DropdownMenuItem(value: 'user', child: Text('user')),
                  DropdownMenuItem(value: 'assistant', child: Text('assistant')),
                ],
                onChanged: (v) => setDlg(() => role = v ?? 'system'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: contentCtrl,
                maxLines: 14,
                decoration: const InputDecoration(
                  labelText: '内容（可用占位符）',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('保存')),
          ],
        ),
      ),
    );
    if (ok == true && contentCtrl.text.trim().isNotEmpty) {
      final msgs = _s.indepTemplate;
      if (m == null) {
        msgs.add(TplMessage(role: role, content: contentCtrl.text));
      } else {
        m.role = role;
        m.content = contentCtrl.text;
      }
      await _s.setIndepTemplate(msgs);
      if (mounted) setState(() {});
    }
  }
}

// ==================== 工作流管理 ====================
class WorkflowManagerScreen extends StatefulWidget {
  const WorkflowManagerScreen({super.key, required this.db});
  final AppDatabase db;
  @override
  State<WorkflowManagerScreen> createState() => _WorkflowManagerScreenState();
}

class _WorkflowManagerScreenState extends State<WorkflowManagerScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ComfyUI 工作流')),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'loadDefault',
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              await loadDefaultWorkflow(widget.db);
              messenger.showSnackBar(
                  const SnackBar(content: Text('已载入内置 Z-Image 默认工作流并启用')));
            },
            child: const Icon(Icons.auto_awesome),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'importJson',
            onPressed: _import,
            icon: const Icon(Icons.upload_file),
            label: const Text('导入 API JSON'),
          ),
        ],
      ),
      body: StreamBuilder(
        stream: (widget.db.select(widget.db.workflows)).watch(),
        builder: (context, snap) {
          final list = snap.data ?? const <Workflow>[];
          if (list.isEmpty) {
            return const Center(
              child: Text('还没有工作流\n\n在 ComfyUI 网页里排版好后，\n菜单「工作流 → 导出(API)」保存 JSON，\n到这里导入并映射节点。',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, height: 1.8)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            itemBuilder: (context, i) {
              final wf = list[i];
              return Card(
                child: ListTile(
                  leading: Icon(
                    wf.isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: wf.isActive ? Colors.green : Colors.grey,
                  ),
                  title: Text(wf.name),
                  subtitle: Text(wf.isActive ? '已启用' : '未启用', style: const TextStyle(fontSize: 12)),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WorkflowMapScreen(db: widget.db, workflow: wf))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!wf.isActive)
                      TextButton(
                        onPressed: () => _activate(wf),
                        child: const Text('启用'),
                      ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        await (widget.db.delete(widget.db.workflows)..where((t) => t.id.equals(wf.id))).go();
                      },
                    ),
                  ]),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _activate(Workflow wf) async {
    await widget.db.transaction(() async {
      await widget.db.update(widget.db.workflows).write(const WorkflowsCompanion(isActive: Value(false)));
      await (widget.db.update(widget.db.workflows)..where((t) => t.id.equals(wf.id)))
          .write(const WorkflowsCompanion(isActive: Value(true)));
    });
  }

  Future<void> _import() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (files.isEmpty || files.first.path == null) return;
    final bytes = await files.first.readAsBytes();
    final json = utf8.decode(bytes);
    if (!json.trimLeft().startsWith('{')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('不是有效的 API 格式 JSON（应为 {节点ID: {...}} 的对象）')));
      }
      return;
    }
    final name = files.first.name.replaceAll(RegExp(r'\.json$', caseSensitive: false), '');
    await widget.db.into(widget.db.workflows).insert(WorkflowsCompanion.insert(name: name, apiJson: json));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已导入「$name」，点击它去映射节点')));
    }
  }
}
