// 设置页：阅读偏好 / 文本清洗 / LLM / ComfyUI / 生成参数 / 工作流 / 模板 / 人物预设 / 章节正则
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../services/comfyui_client.dart';
import '../services/default_workflow.dart';
import '../services/settings_service.dart';
import '../services/text_cleaner.dart';
import '../services/tts_service.dart';
import 'data_management_screen.dart';
import 'widgets.dart';
import 'workflow_map_screen.dart';

Widget buildSettingsScreen(AppDatabase db) => SettingsScreen(db: db);

/// MiMo 预置音色（voice 字段直接透传接口），移植自 Conversation_avatar
const List<(String, String)> kMimoTtsVoices = [
  ('mimo_default', 'MiMo · 默认'),
  ('冰糖', '冰糖（中文女）'),
  ('茉莉', '茉莉（中文女）'),
  ('苏打', '苏打（中文男）'),
  ('白桦', '白桦（中文男）'),
  ('Mia', 'Mia（英文女）'),
  ('Chloe', 'Chloe（英文女）'),
  ('Milo', 'Milo（英文男）'),
  ('Dean', 'Dean（英文男）'),
];

/// 豆包官方音色（speaker 字段直接透传接口），移植自 Conversation_avatar
const List<(String, String)> kDoubaoTtsVoices = [
  ('zh_male_dayi_saturn_bigtts', '大壹（浑厚男声）'),
  ('zh_male_ruyayichen_saturn_bigtts', '儒雅逸辰（儒雅男声）'),
  ('saturn_zh_male_shuanglangshaonian_tob', '爽朗少年（阳光少年）'),
  ('saturn_zh_male_tiancaitongzhuo_tob', '天才同桌（学霸感）'),
  ('zh_male_m191_uranus_bigtts', '云舟（稳重男声）'),
  ('zh_male_taocheng_uranus_bigtts', '小天（阳光少年）'),
  ('zh_female_vv_uranus_bigtts', 'vivi（温柔女声）'),
  ('saturn_zh_female_cancan_tob', '知性灿灿（知性优雅）'),
  ('zh_female_meilinvyou_saturn_bigtts', '魅力女友（亲密对话）'),
  ('saturn_zh_female_keainvsheng_tob', '可爱女生（可爱活泼）'),
  ('saturn_zh_female_tiaopigongzhu_tob', '调皮公主（公主风）'),
  ('zh_female_jitangnv_saturn_bigtts', '鸡汤女（情感治愈）'),
  ('zh_female_santongyongns_saturn_bigtts', '流畅女声（通用）'),
  ('zh_female_xiaohe_uranus_bigtts', '小何（亲切女声）'),
  ('zh_female_xueayi_saturn_bigtts', '儿童绘本（绘本朗读）'),
  ('zh_female_mizai_saturn_bigtts', '黑猫侦探社咪仔（悬疑）'),
];

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
          const SectionHeader(title: '数据'),
          SettingRow(
            title: '数据管理',
            subtitle: '书库备份 / 从备份导入 / 另存与分享',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => DataManagementScreen(db: widget.db))),
          ),
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
          SettingRow(
            title: '章节分割正则',
            subtitle: _s.chapterRegex,
            onTap: () async {
              final v = await textInputDialog(context, title: '章节分割正则', initial: _s.chapterRegex);
              if (v != null && v.trim().isNotEmpty) await _s.setChapterRegex(v.trim());
            },
          ),

          const SectionHeader(title: '文本清洗（导入时自动应用）'),
          SettingRow(
            title: '去乱码碎片',
            subtitle: '删除「z u E w9 c w I8 a」这类空格分隔的字母/数字碎片',
            trailing: Switch(
              value: _s.cleanStripNoise,
              onChanged: (v) async {
                await _s.setCleanStripNoise(v);
                setState(() {});
              },
            ),
          ),
          SettingRow(
            title: '替换字符与莫忘码',
            subtitle: '删除 �、锟斤拷、烫烫烫、???、□□□',
            trailing: Switch(
              value: _s.cleanStripMojibake,
              onChanged: (v) async {
                await _s.setCleanStripMojibake(v);
                setState(() {});
              },
            ),
          ),
          SettingRow(
            title: '屏蔽正则规则',
            subtitle: _s.cleanRules.isEmpty
                ? '未设置（在阅读器选中垃圾内容后点「屏蔽」可生成）'
                : '${_s.cleanRules.length} 条 · 导入时自动应用',
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
                context, MaterialPageRoute(builder: (_) => const CleanRuleScreen())),
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

          const SectionHeader(title: '朗读音色（TTS）'),
          SettingRow(
            title: '语音引擎',
            trailing: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'mimo', label: Text('MiMo')),
                ButtonSegment(value: 'doubao', label: Text('豆包')),
              ],
              selected: {_s.tts.engine},
              onSelectionChanged: (v) async {
                final c = _s.tts..engine = v.first;
                await _s.setTts(c);
              },
            ),
          ),
          if (_s.tts.engine == 'mimo') ...[
            SettingRow(
              title: 'MiMo API Key',
              subtitle: _s.tts.mimo.apiKey.isEmpty ? '未设置' : '••••••••',
              onTap: () async {
                final v = await textInputDialog(context, title: 'MiMo API Key', initial: _s.tts.mimo.apiKey, obscure: true);
                if (v != null) await _s.setTts(_s.tts..mimo.apiKey = v.trim());
              },
            ),
            SettingRow(
              title: 'MiMo 接口地址',
              subtitle: _s.tts.mimo.baseUrl,
              onTap: () async {
                final v = await textInputDialog(context, title: 'MiMo 接口地址', initial: _s.tts.mimo.baseUrl, hint: 'https://api.xiaomimimo.com/v1');
                if (v != null && v.trim().isNotEmpty) await _s.setTts(_s.tts..mimo.baseUrl = v.trim());
              },
            ),
            SettingRow(
              title: 'MiMo 模型',
              subtitle: _s.tts.mimo.model,
              onTap: () async {
                final v = await textInputDialog(context, title: 'MiMo 模型', initial: _s.tts.mimo.model, hint: 'mimo-v2.5-tts');
                if (v != null && v.trim().isNotEmpty) await _s.setTts(_s.tts..mimo.model = v.trim());
              },
            ),
            SettingRow(
              title: 'MiMo 音频格式',
              trailing: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'wav', label: Text('WAV')),
                  ButtonSegment(value: 'mp3', label: Text('MP3')),
                ],
                selected: {_s.tts.mimo.format},
                onSelectionChanged: (v) async {
                  final c = _s.tts..mimo.format = v.first;
                  await _s.setTts(c);
                },
              ),
            ),
            SettingRow(
              title: '克隆参考音频',
              subtitle: _s.tts.mimo.cloneAudioName.isEmpty
                  ? '未上传 · 点按选一段 wav/mp3 音频样本复刻音色'
                  : _s.tts.mimo.cloneAudioName,
              onTap: _pickCloneAudio,
            ),
          ] else ...[
            SettingRow(
              title: '豆包 App ID',
              subtitle: _s.tts.doubao.appId.isEmpty ? '未设置' : _s.tts.doubao.appId,
              onTap: () async {
                final v = await textInputDialog(context, title: '豆包 App ID', initial: _s.tts.doubao.appId);
                if (v != null) await _s.setTts(_s.tts..doubao.appId = v.trim());
              },
            ),
            SettingRow(
              title: '豆包 Access Key',
              subtitle: _s.tts.doubao.accessKey.isEmpty ? '未设置' : '••••••••',
              onTap: () async {
                final v = await textInputDialog(context, title: '豆包 Access Key', initial: _s.tts.doubao.accessKey, obscure: true);
                if (v != null) await _s.setTts(_s.tts..doubao.accessKey = v.trim());
              },
            ),
            SettingRow(
              title: '豆包 Resource ID',
              subtitle: _s.tts.doubao.resourceId,
              onTap: () async {
                final v = await textInputDialog(context, title: '豆包 Resource ID', initial: _s.tts.doubao.resourceId, hint: 'seed-tts-2.0');
                if (v != null && v.trim().isNotEmpty) await _s.setTts(_s.tts..doubao.resourceId = v.trim());
              },
            ),
          ],
          SettingRow(
            title: '音色',
            subtitle: _ttsVoiceLabel(),
            onTap: _pickTtsVoice,
          ),
          SettingRow(
            title: '试听',
            subtitle: _ttsTestResult ?? '用当前引擎与音色合成一句示例',
            trailing: const Icon(Icons.volume_up),
            onTap: _previewTts,
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

  // ---------- 朗读音色 ----------

  String? _ttsTestResult;
  bool _ttsTesting = false;

  String _ttsVoiceLabel() {
    final cfg = _s.tts;
    final presets = cfg.engine == 'mimo' ? kMimoTtsVoices : kDoubaoTtsVoices;
    final voice = cfg.engine == 'mimo' ? cfg.mimo.voice : cfg.doubao.voice;
    if (voice == TtsMimoConfig.cloneVoiceId) {
      final name = cfg.mimo.cloneAudioName;
      return name.isEmpty ? '克隆音色（未上传参考音频）' : '克隆音色（$name）';
    }
    if (voice.isEmpty) return '未选择';
    for (final (id, name) in presets) {
      if (id == voice) return '$name（$id）';
    }
    return voice;
  }

  Future<void> _pickTtsVoice() async {
    final cfg = _s.tts;
    final isMimo = cfg.engine == 'mimo';
    final presets = isMimo ? kMimoTtsVoices : kDoubaoTtsVoices;
    final picked = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text(isMimo ? 'MiMo 音色' : '豆包音色'),
        children: [
          if (isMimo)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, TtsMimoConfig.cloneVoiceId),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('🎙 克隆音色（复刻参考音频）'),
                Text(
                  cfg.mimo.cloneAudioName.isEmpty ? '未上传参考音频，选择后需上传' : '参考音频：${cfg.mimo.cloneAudioName}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ]),
            ),
          for (final (id, name) in presets)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, id),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name),
                Text(id, style: const TextStyle(fontSize: 11, color: Colors.grey)),
              ]),
            ),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(c, ''),
            child: const Text('✎ 自定义音色 ID'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    var voice = picked;
    if (voice == TtsMimoConfig.cloneVoiceId) {
      // 克隆音色：还没传过参考音频就先引导上传，取消上传则不切换
      if (cfg.mimo.cloneAudioPath.isEmpty && !await _pickCloneAudio()) return;
    } else if (voice.isEmpty) {
      if (!mounted) return;
      final custom = await textInputDialog(
          context, title: '自定义音色 ID', initial: isMimo ? cfg.mimo.voice : cfg.doubao.voice);
      if (custom == null) return;
      voice = custom.trim();
      if (voice.isEmpty) return;
    }
    if (isMimo) {
      await _s.setTts(_s.tts..mimo.voice = voice);
    } else {
      await _s.setTts(_s.tts..doubao.voice = voice);
    }
    if (mounted) setState(() {});
  }

  /// 选择 MiMo 克隆参考音频：复制到应用文档目录统一管理，配置只存路径
  Future<bool> _pickCloneAudio() async {
    final files = await FilePicker.pickFiles(type: FileType.audio);
    if (files.isEmpty || files.first.path == null) return false;
    final name = files.first.name;
    final ext = name.contains('.') ? '.${name.split('.').last.toLowerCase()}' : '';
    final docs = await getApplicationDocumentsDirectory();
    final dest = File('${docs.path}/tts_clone_ref$ext');
    final oldPath = _s.tts.mimo.cloneAudioPath;
    try {
      await dest.delete(); // 同名旧文件直接覆盖
    } catch (_) {}
    await File(files.first.path!).copy(dest.path);
    if (oldPath.isNotEmpty && oldPath != dest.path) {
      try {
        await File(oldPath).delete(); // 换了扩展名时清掉旧文件
      } catch (_) {}
    }
    await _s.setTts(
        _s.tts..mimo.cloneAudioPath = dest.path..mimo.cloneAudioName = name);
    if (mounted) setState(() {});
    return true;
  }

  Future<void> _previewTts() async {
    if (_ttsTesting) return;
    setState(() {
      _ttsTesting = true;
      _ttsTestResult = '合成中…';
    });
    try {
      await TtsService.instance.speak('你好，这是生图书的朗读音色试听。');
      if (mounted) setState(() => _ttsTestResult = '✅ 播放完成');
    } catch (e) {
      if (mounted) setState(() => _ttsTestResult = '❌ $e');
    } finally {
      if (mounted) setState(() => _ttsTesting = false);
    }
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
                    wf.isActive
                        ? Icons.check_circle
                        : wf.isSecond
                            ? Icons.star
                            : Icons.radio_button_unchecked,
                    color: wf.isActive
                        ? Colors.green
                        : wf.isSecond
                            ? Colors.blue
                            : Colors.grey,
                  ),
                  title: Text(wf.name),
                  subtitle: Text(
                    wf.isActive ? '第一工作流' : wf.isSecond ? '第二工作流（↻2 重生成用）' : '未启用',
                    style: const TextStyle(fontSize: 12),
                  ),
                  onTap: () => Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WorkflowMapScreen(db: widget.db, workflow: wf))),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (!wf.isActive)
                      TextButton(
                        onPressed: () => _activate(wf),
                        child: const Text('启用'),
                      ),
                    TextButton(
                      onPressed: () => _toggleSecond(wf),
                      style: TextButton.styleFrom(
                        foregroundColor: wf.isSecond ? Colors.blue : null,
                      ),
                      child: Text(wf.isSecond ? '第二 ✓' : '第二'),
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

  /// 设为/取消第二工作流；设为时清空其他行的第二标记（同一时刻只有一个）
  Future<void> _toggleSecond(Workflow wf) async {
    final next = !wf.isSecond;
    await widget.db.transaction(() async {
      if (next) {
        await widget.db.update(widget.db.workflows).write(const WorkflowsCompanion(isSecond: Value(false)));
      }
      await (widget.db.update(widget.db.workflows)..where((t) => t.id.equals(wf.id)))
          .write(WorkflowsCompanion(isSecond: Value(next)));
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

/// 屏蔽正则规则库：导入时自动应用；规则可由阅读器选区生成，也可手写
class CleanRuleScreen extends StatefulWidget {
  const CleanRuleScreen({super.key});

  @override
  State<CleanRuleScreen> createState() => _CleanRuleScreenState();
}

class _CleanRuleScreenState extends State<CleanRuleScreen> {
  final _s = SettingsService.instance;
  late final List<CleanRule> _rules = List.of(_s.cleanRules);

  Future<void> _save() => _s.setCleanRules(_rules);

  Future<void> _edit(int? index) async {
    final res = await _editRuleDialog(context, index == null ? null : _rules[index]);
    if (res == null) return;
    setState(() {
      if (index == null) {
        _rules.add(res);
      } else {
        _rules[index] = res;
      }
    });
    await _save();
  }

  Future<void> _delete(int index) async {
    final r = _rules[index];
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除规则'),
        content: Text('删除「${r.name}」？已导入的书不受影响。'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _rules.removeAt(index));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('屏蔽正则规则')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('新增规则'),
      ),
      body: _rules.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  '还没有规则。\n在阅读器里选中要屏蔽的内容（如签名、广告、回复区），\n点浮动菜单的「屏蔽」，即可生成头尾锚点正则。',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              itemCount: _rules.length,
              itemBuilder: (context, i) {
                final r = _rules[i];
                return ListTile(
                  contentPadding: const EdgeInsets.only(left: 4),
                  title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(r.pattern,
                      maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                  onTap: () => _edit(i),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Switch(
                      value: r.enabled,
                      onChanged: (v) async {
                        setState(() => r.enabled = v);
                        await _save();
                      },
                    ),
                    IconButton(
                      tooltip: '删除',
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      onPressed: () => _delete(i),
                    ),
                  ]),
                );
              },
            ),
    );
  }
}

/// 规则编辑框（正则合法性即时校验）
Future<CleanRule?> _editRuleDialog(BuildContext context, CleanRule? initial) async {
  final name = TextEditingController(text: initial?.name ?? '');
  final pattern = TextEditingController(text: initial?.pattern ?? '');
  final err = ValueNotifier<String?>(null);
  final res = await showDialog<CleanRule>(
    context: context,
    builder: (c) => ValueListenableBuilder<String?>(
      valueListenable: err,
      builder: (c, e, _) => AlertDialog(
        title: Text(initial == null ? '新增屏蔽规则' : '编辑屏蔽规则'),
        content: SizedBox(
          width: 460,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(
                  labelText: '规则名', border: OutlineInputBorder(), isDense: true),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pattern,
              maxLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: InputDecoration(
                labelText: '正则（逐行匹配，命中即整块删除）',
                hintText: r'^\s*签名[\s\S]*?回复倒序\s*$',
                border: const OutlineInputBorder(),
                isDense: true,
                errorText: e,
              ),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
          FilledButton(
            onPressed: () {
              final p = pattern.text.trim();
              if (p.isEmpty) {
                err.value = '正则不能为空';
                return;
              }
              try {
                RegExp(p, multiLine: true);
              } on FormatException {
                err.value = '正则不合法';
                return;
              }
              final n = name.text.trim();
              Navigator.pop(
                  c, CleanRule(name: n.isEmpty ? '未命名规则' : n, pattern: p, enabled: initial?.enabled ?? true));
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  name.dispose();
  pattern.dispose();
  err.dispose();
  return res;
}
