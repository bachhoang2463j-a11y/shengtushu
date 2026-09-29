// 设置服务：shared_preferences 持久化（LLM/ComfyUI/生成参数/模板/预设/阅读偏好）
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'text_cleaner.dart';

class LlmConfig {
  String baseUrl;
  String apiKey;
  String model;
  double temperature;
  int maxTokens;
  LlmConfig({
    this.baseUrl = 'https://api.deepseek.com',
    this.apiKey = '',
    this.model = 'deepseek-chat',
    this.temperature = 0.9,
    this.maxTokens = 8192,
  });

  Map<String, dynamic> toJson() => {
    'baseUrl': baseUrl, 'apiKey': apiKey, 'model': model,
    'temperature': temperature, 'maxTokens': maxTokens,
  };
  factory LlmConfig.fromJson(Map<String, dynamic> j) => LlmConfig(
    baseUrl: j['baseUrl'] ?? 'https://api.deepseek.com',
    apiKey: j['apiKey'] ?? '',
    model: j['model'] ?? 'deepseek-chat',
    temperature: (j['temperature'] as num?)?.toDouble() ?? 0.9,
    maxTokens: j['maxTokens'] ?? 8192,
  );
}

/// 人物预设（脚本「人物列表」位：固定特征标签注入 <!--人物列表-->）
class PersonaPreset {
  String name;
  String tags;
  bool enabled;
  PersonaPreset({required this.name, this.tags = '', this.enabled = false});

  Map<String, dynamic> toJson() => {'name': name, 'tags': tags, 'enabled': enabled};
  factory PersonaPreset.fromJson(Map<String, dynamic> j) => PersonaPreset(
    name: j['name'] ?? '', tags: j['tags'] ?? '', enabled: j['enabled'] ?? false);
}

/// LLM 预设：一套连接配置的命名快照（应用 = 拷回 llm 配置）
class LlmPreset {
  String id;
  String name;
  LlmConfig llm;
  LlmPreset({required this.id, required this.name, required this.llm});

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'llm': llm.toJson()};
  factory LlmPreset.fromJson(Map<String, dynamic> j) => LlmPreset(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    llm: LlmConfig.fromJson((j['llm'] as Map<String, dynamic>?) ?? const {}),
  );
}

/// 生词模板预设：画风文本 + 绑定的 ComfyUI 工作流（null = 不绑定，应用时不动工作流）
class StylePreset {
  String id;
  String name;
  String styleText;
  int? workflowId;
  StylePreset({required this.id, required this.name, this.styleText = '', this.workflowId});

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'styleText': styleText, 'workflowId': workflowId};
  factory StylePreset.fromJson(Map<String, dynamic> j) => StylePreset(
    id: j['id'] ?? '',
    name: j['name'] ?? '',
    styleText: j['styleText'] ?? '',
    workflowId: j['workflowId'] as int?,
  );
}

/// 一条模板消息（多消息模板，占位符语法移植自生图助手脚本）
class TplMessage {
  String role; // system | user | assistant
  String content;
  TplMessage({required this.role, required this.content});

  Map<String, dynamic> toJson() => {'role': role, 'content': content};
  factory TplMessage.fromJson(Map<String, dynamic> j) =>
      TplMessage(role: j['role'] ?? 'system', content: j['content'] ?? '');
}

/// 朗读（TTS）配置：引擎 + 各家凭证/音色（请求格式移植自 Conversation_avatar 项目）
class TtsMimoConfig {
  /// voice 哨兵值：表示用上传的参考音频复刻音色（model 自动切 voiceclone）
  static const cloneVoiceId = '__clone__';

  String apiKey;
  String baseUrl;
  String model;
  String format; // wav | mp3
  String voice;
  String cloneAudioPath; // 参考音频在应用文档目录内的绝对路径（'' = 未上传）
  String cloneAudioName; // 原始文件名，展示用
  TtsMimoConfig({
    this.apiKey = '',
    this.baseUrl = 'https://api.xiaomimimo.com/v1',
    this.model = 'mimo-v2.5-tts',
    this.format = 'wav',
    this.voice = 'mimo_default',
    this.cloneAudioPath = '',
    this.cloneAudioName = '',
  });

  Map<String, dynamic> toJson() => {
        'apiKey': apiKey,
        'baseUrl': baseUrl,
        'model': model,
        'format': format,
        'voice': voice,
        'cloneAudioPath': cloneAudioPath,
        'cloneAudioName': cloneAudioName,
      };
  factory TtsMimoConfig.fromJson(Map<String, dynamic> j) => TtsMimoConfig(
    apiKey: j['apiKey'] ?? '',
    baseUrl: j['baseUrl'] ?? 'https://api.xiaomimimo.com/v1',
    model: j['model'] ?? 'mimo-v2.5-tts',
    format: j['format'] ?? 'wav',
    voice: j['voice'] ?? 'mimo_default',
    cloneAudioPath: j['cloneAudioPath'] ?? '',
    cloneAudioName: j['cloneAudioName'] ?? '',
  );
}

class TtsDoubaoConfig {
  String appId;
  String accessKey;
  String resourceId;
  String uid;
  String voice;
  TtsDoubaoConfig({
    this.appId = '',
    this.accessKey = '',
    this.resourceId = 'seed-tts-2.0',
    this.uid = '1222356',
    this.voice = '',
  });

  Map<String, dynamic> toJson() =>
      {'appId': appId, 'accessKey': accessKey, 'resourceId': resourceId, 'uid': uid, 'voice': voice};
  factory TtsDoubaoConfig.fromJson(Map<String, dynamic> j) => TtsDoubaoConfig(
    appId: j['appId'] ?? '',
    accessKey: j['accessKey'] ?? '',
    resourceId: j['resourceId'] ?? 'seed-tts-2.0',
    uid: j['uid'] ?? '1222356',
    voice: j['voice'] ?? '',
  );
}

class TtsConfig {
  String engine; // mimo | doubao
  TtsMimoConfig mimo;
  TtsDoubaoConfig doubao;
  TtsConfig({this.engine = 'mimo', TtsMimoConfig? mimo, TtsDoubaoConfig? doubao})
      : mimo = mimo ?? TtsMimoConfig(),
        doubao = doubao ?? TtsDoubaoConfig();

  Map<String, dynamic> toJson() =>
      {'engine': engine, 'mimo': mimo.toJson(), 'doubao': doubao.toJson()};
  factory TtsConfig.fromJson(Map<String, dynamic> j) => TtsConfig(
    engine: j['engine'] ?? 'mimo',
    mimo: TtsMimoConfig.fromJson((j['mimo'] as Map<String, dynamic>?) ?? const {}),
    doubao: TtsDoubaoConfig.fromJson((j['doubao'] as Map<String, dynamic>?) ?? const {}),
  );
}

class SettingsService extends ChangeNotifier {
  SettingsService._();
  static final SettingsService instance = SettingsService._();

  late SharedPreferences _sp;

  Future<void> init() async {
    _sp = await SharedPreferences.getInstance();
    // 一次性迁移：对齐 demo 原型的阅读排版（字号 17 / 行高 1.85 / 羊皮纸主题）
    if (!(_sp.getBool('demoLayoutV1') ?? false)) {
      await _sp.setDouble('fontSize', 17.0);
      await _sp.setDouble('lineHeight', 1.85);
      await _sp.setString('theme', 'sepia');
      await _sp.setBool('demoLayoutV1', true);
    }
  }

  String _get(String key, String def) => _sp.getString(key) ?? def;
  Future<void> _set(String key, String v) async {
    await _sp.setString(key, v);
    notifyListeners();
  }

  // ---------- LLM ----------
  LlmConfig get llm => LlmConfig.fromJson(
      jsonDecode(_get('llm', '{}')) as Map<String, dynamic>);
  Future<void> setLlm(LlmConfig c) => _set('llm', jsonEncode(c.toJson()));

  // ---------- ComfyUI ----------
  String get comfyUrl => _get('comfyUrl', 'http://192.168.1.100:8188');
  Future<void> setComfyUrl(String v) => _set('comfyUrl', v);

  // ---------- 生成参数 ----------
  int get genWidth => _sp.getInt('genWidth') ?? 1280;
  int get genHeight => _sp.getInt('genHeight') ?? 720;
  int get genRetry => _sp.getInt('genRetry') ?? 3;
  int get historyCount => _sp.getInt('historyCount') ?? 4;
  bool get autoRandomSeed => _sp.getBool('autoRandomSeed') ?? true;
  Future<void> setGenParams({
    int? width, int? height, int? retry, int? historyCount, bool? autoRandomSeed,
  }) async {
    if (width != null) await _sp.setInt('genWidth', width);
    if (height != null) await _sp.setInt('genHeight', height);
    if (retry != null) await _sp.setInt('genRetry', retry);
    if (historyCount != null) await _sp.setInt('historyCount', historyCount);
    if (autoRandomSeed != null) await _sp.setBool('autoRandomSeed', autoRandomSeed);
    notifyListeners();
  }

  // ---------- 独立生图模板（多消息，占位符语法见 prompt_service.dart）----------
  List<TplMessage> get indepTemplate {
    final raw = _get('indepTemplate', '');
    if (raw.isNotEmpty) {
      try {
        return (jsonDecode(raw) as List)
            .map((e) => TplMessage.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }
    return defaultIndepTemplate();
  }
  Future<void> setIndepTemplate(List<TplMessage> msgs) =>
      _set('indepTemplate', jsonEncode(msgs.map((m) => m.toJson()).toList()));
  Future<void> resetIndepTemplate() => _sp.remove('indepTemplate').then((_) => notifyListeners());

  // ---------- 生词模版（文风/画质要求文本，注入 <!--生词模版-->）----------
  String get styleText => _get('styleText', kDefaultStyleText);
  Future<void> setStyleText(String v) => _set('styleText', v);

  // ---------- 人物预设 ----------
  List<PersonaPreset> get personas {
    final raw = _get('personas', '[]');
    try {
      return (jsonDecode(raw) as List)
          .map((e) => PersonaPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
  Future<void> setPersonas(List<PersonaPreset> list) =>
      _set('personas', jsonEncode(list.map((p) => p.toJson()).toList()));

  // ---------- LLM 预设（多套连接配置快照，应用 = 拷回 llm）----------
  List<LlmPreset> get llmPresets {
    final raw = _get('llmPresets', '[]');
    try {
      return (jsonDecode(raw) as List)
          .map((e) => LlmPreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
  Future<void> setLlmPresets(List<LlmPreset> list) =>
      _set('llmPresets', jsonEncode(list.map((p) => p.toJson()).toList()));

  // ---------- 生词模板预设（画风文本 + 绑定工作流，应用 = 拷回 styleText + 激活工作流）----------
  List<StylePreset> get stylePresets {
    final raw = _get('stylePresets', '[]');
    try {
      return (jsonDecode(raw) as List)
          .map((e) => StylePreset.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }
  Future<void> setStylePresets(List<StylePreset> list) =>
      _set('stylePresets', jsonEncode(list.map((p) => p.toJson()).toList()));

  // ---------- 朗读（TTS） ----------
  TtsConfig get tts {
    try {
      return TtsConfig.fromJson(jsonDecode(_get('tts', '{}')) as Map<String, dynamic>);
    } catch (_) {
      return TtsConfig();
    }
  }
  Future<void> setTts(TtsConfig c) => _set('tts', jsonEncode(c.toJson()));

  // ---------- 阅读偏好 ----------
  double get fontSize => _sp.getDouble('fontSize') ?? 17.0;
  double get lineHeight => _sp.getDouble('lineHeight') ?? 1.85;
  String get themeMode => _get('theme', 'sepia'); // light | sepia | green | dark
  String get pageMode => _get('pageMode', 'page'); // page | scroll
  Future<void> setFontSize(double v) async { await _sp.setDouble('fontSize', v); notifyListeners(); }
  Future<void> setLineHeight(double v) async { await _sp.setDouble('lineHeight', v); notifyListeners(); }
  Future<void> setThemeMode(String v) async { await _sp.setString('theme', v); notifyListeners(); }
  Future<void> setPageMode(String v) async { await _sp.setString('pageMode', v); notifyListeners(); }

  // ---------- 章节正则 ----------
  String get chapterRegex => _get('chapterRegex', kDefaultChapterRegexSetting);
  Future<void> setChapterRegex(String v) => _set('chapterRegex', v);

  // ---------- 文本清洗 ----------
  bool get cleanStripNoise => _sp.getBool('cleanStripNoise') ?? true;
  bool get cleanStripMojibake => _sp.getBool('cleanStripMojibake') ?? true;

  List<CleanRule> get cleanRules {
    final raw = _get('cleanRules', '[]');
    try {
      return [
        for (final e in jsonDecode(raw) as List)
          if (e is Map<String, dynamic>) CleanRule.fromJson(e),
      ];
    } catch (_) {
      return [];
    }
  }

  Future<void> setCleanStripNoise(bool v) async {
    await _sp.setBool('cleanStripNoise', v);
    notifyListeners();
  }

  Future<void> setCleanStripMojibake(bool v) async {
    await _sp.setBool('cleanStripMojibake', v);
    notifyListeners();
  }

  Future<void> setCleanRules(List<CleanRule> rules) =>
      _set('cleanRules', jsonEncode([for (final r in rules) r.toJson()]));

  /// 当前清洗配置（导入 isolate 传递 / 手动清理共用）
  CleanOptions get cleanOptions => CleanOptions(
        stripNoise: cleanStripNoise,
        stripMojibake: cleanStripMojibake,
        rules: cleanRules,
      );

  String cleanOptionsJson() => jsonEncode(cleanOptions.toJson());
}

const String kDefaultChapterRegexSetting = r'^\s*(第[0-9〇零一二三四五六七八九十百千万两]+[章回节卷集部篇].*)$';

/// 默认生词模版（文风/画质要求）
const String kDefaultStyleText = '''
画质：masterpiece, best quality, highly detailed, ultra-detailed
画面：小说插图风格，构图完整，光影自然，情绪贴合剧情
要求：根据剧情选取最具画面感的场景；人物外貌与服饰需与描述一致；不要出现文字、水印、对话框。
''';

/// 默认独立生图模板。
/// 结构与输出规范移植自「生图助手 v45.3.1」indepGenTemplateV2
/// （JSON insertions / [P1][P2] 编号 / [IMG_GEN] 包裹 / 核心规则），
/// 不携带原脚本中的注入类前置消息；需要时可在设置里自行添加。
List<TplMessage> defaultIndepTemplate() => [
  TplMessage(role: 'system', content: '''
你是专业的小说插图提示词生成助手。你的工作是分析剧情文本，在合适的位置生成对应的文生图提示词，以JSON格式返回结果。

重要：只为【当前文本】部分的内容生成图片，其他部分仅作为人物服装、环境、姿态、表情等细节的参考。'''),
  TplMessage(role: 'user', content: '———————— 📜 前文上下文 ————————\n（说明：以下是之前的剧情，仅供参考，禁止对这部分内容生成图片）\n\n<!--历史上下文-->'),
  TplMessage(role: 'user', content: '———————— 📖 设定说明 ————————\n⚠️ 作用：作为人物当前的【穿着】、【姿势】、【状态】、【环境】等等信息的参考。\n⚠️ 注意：这部分内容仅供参考，禁止在这里的内容处生成图片。\n\n<!--设定说明-->'),
  TplMessage(role: 'user', content: '———————— 🎨 生词模版 ————————\n📜 以下是用户定义的提示词模版，生成prompt时请严格按照模版中的要求和格式来生成。\n\n<!--生词模版-->'),
  TplMessage(role: 'user', content: '———————— 👤 人物列表 ————————\n📜 以下是人物固定特征标签，生成prompt时涉及对应人物必须原样使用：\n\n<!--人物列表-->'),
  TplMessage(role: 'system', content: '''
## ⚠️ 核心规则（必须严格遵守）
1. 🎯 **只能**为【📌 当前文本】部分的内容生成图片
2. ❌ **绝对禁止**在【📖 设定说明】或【📜 前文上下文】的内容处生成图片
3. ✅ **必须至少生成1个提示词**
4. ⚠️ **格式第一**：必须输出有效JSON，绝对不要在JSON外面写任何内容

## 📋 输出格式（严格遵守）
```json
{
  "insertions": [
    { "after_paragraph": 数字, "prompt": "提示词内容" }
  ]
}
```

### 字段说明：
- **insertions**: 数组，包含所有要插入的图片
- **after_paragraph**: 数字，对应[P1][P2]...的编号，表示图片插入在该段落之后
- **prompt**: 字符串，Stable Diffusion标签，用逗号分隔

### prompt字段格式（二选一）：
**方式1 - 直接输出标签：**
```json
{ "after_paragraph": 1, "prompt": "masterpiece, best quality, 1girl, smile, ..." }
```

**方式2 - 包含分析思考（如需要）：**
如果需要在prompt中加入分析，请用[IMG_GEN]标签包裹最终提示词：
```json
{ "after_paragraph": 1, "prompt": "分析：这里是你的思考过程...\\n[IMG_GEN]masterpiece, best quality, 1girl, smile, ...[/IMG_GEN]" }
```
注意：分析内容必须在prompt字段内部，[IMG_GEN]标签内只能是纯SD标签。

## 🚫 禁止事项
- 禁止在JSON外面写任何文字（包括思考过程）
- 禁止复制模版中的系统指令'''),
  TplMessage(role: 'user', content: '''
———————— 🌍 当前文本（核心任务）————————

📜 作用：这是你需要分析并生成图片提示词的内容！
⚠️ 重要规则：
   1. 段落已用 [P1], [P2]... 编号标记
   2. after_paragraph 的数字必须对应这些编号
   3. 必须至少生成1个提示词！
   4. 只输出JSON，不要输出其他任何内容！

<!--当前文本-->'''),
];
