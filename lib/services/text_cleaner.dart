// 文本清洗：去乱码碎片、去替换字符/莫忘码、应用用户屏蔽正则
// 纯 Dart（不依赖 Flutter），导入解析在 isolate 里调用
import 'dart:convert';

/// 用户屏蔽规则：一条正则（multiLine），命中即整段删除。
/// 由阅读器选区生成（头尾锚点）或设置页手写。
class CleanRule {
  String name;
  String pattern;
  bool enabled;
  CleanRule({required this.name, required this.pattern, this.enabled = true});

  Map<String, dynamic> toJson() => {'name': name, 'pattern': pattern, 'enabled': enabled};

  factory CleanRule.fromJson(Map<String, dynamic> j) => CleanRule(
        name: j['name'] is String ? j['name'] as String : '',
        pattern: j['pattern'] is String ? j['pattern'] as String : '',
        enabled: j['enabled'] is bool ? j['enabled'] as bool : true,
      );
}

/// 清洗配置（全局设置 → 导入 isolate / 手动清理共用）
class CleanOptions {
  /// 去乱码：连续字母/数字碎片串
  final bool stripNoise;

  /// 去替换字符（�、锟斤拷、烫烫烫、???、□□□）
  final bool stripMojibake;

  final List<CleanRule> rules;

  const CleanOptions({
    this.stripNoise = true,
    this.stripMojibake = true,
    this.rules = const [],
  });

  bool get isNoop =>
      !stripNoise && !stripMojibake && !rules.any((r) => r.enabled && r.pattern.trim().isNotEmpty);

  Map<String, dynamic> toJson() => {
        'noise': stripNoise,
        'mojibake': stripMojibake,
        'rules': [for (final r in rules) r.toJson()],
      };

  factory CleanOptions.fromJson(Map<String, dynamic> j) => CleanOptions(
        stripNoise: j['noise'] is bool ? j['noise'] as bool : true,
        stripMojibake: j['mojibake'] is bool ? j['mojibake'] as bool : true,
        rules: [
          if (j['rules'] is List)
            for (final e in j['rules'] as List)
              if (e is Map<String, dynamic>) CleanRule.fromJson(e),
        ],
      );

  static CleanOptions decode(String? json) {
    if (json == null || json.isEmpty) return const CleanOptions();
    try {
      final raw = jsonDecode(json);
      if (raw is Map<String, dynamic>) return CleanOptions.fromJson(raw);
    } catch (_) {
      // 配置损坏：按默认口径处理
    }
    return const CleanOptions();
  }
}

/// 单条正则的命中统计（预览用）
class RulePreview {
  final bool invalid;
  final int hits;
  final int removed;
  final List<String> samples;

  const RulePreview({this.invalid = false, this.hits = 0, this.removed = 0, this.samples = const []});
}

class TextCleaner {
  TextCleaner._();

  /// 候选碎片：不含空白与中日韩文字、中文标点、全角字符的连续串
  static final RegExp _tokenRe = RegExp(r'[^\s\u3000-\u303f\u4e00-\u9fff\uff00-\uffef]+');
  static final RegExp _alnumRe = RegExp(r'[A-Za-z0-9]');
  static final RegExp _digitRe = RegExp(r'[0-9]');

  /// 去乱码：把「空格分隔的连续短碎片」整串删除。
  ///
  /// 碎片定义：1~2 个字符、不含空白与中文、至少含一个字母或数字。
  /// 判定为乱码需同时满足：①碎片 ≥3 个；②其中单字符碎片 ≥2 个；
  /// ③含数字的碎片 ≥1 个，或碎片总数 ≥4。
  /// 由此 `z u E w9 c w I8 a` 会被删除，而 `I am a boy`（3 片、无数字）、
  /// `to be or not to be` 这类正常英文不会被误伤。
  static String stripNoiseRuns(String text) {
    if (text.isEmpty) return text;
    final matches = _tokenRe.allMatches(text).toList();
    if (matches.length < 3) return text;
    final cuts = <List<int>>[];
    var i = 0;
    while (i < matches.length) {
      if (!_isFragment(matches[i][0]!)) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < matches.length &&
          _isFragment(matches[j + 1][0]!) &&
          _onlyBlanks(text, matches[j].end, matches[j + 1].start)) {
        j++;
      }
      if (_isNoiseRun([for (var k = i; k <= j; k++) matches[k][0]!])) {
        cuts.add([matches[i].start, matches[j].end]);
      }
      i = j + 1;
    }
    if (cuts.isEmpty) return text;
    final sb = StringBuffer();
    var pos = 0;
    for (final c in cuts) {
      sb.write(text.substring(pos, c[0]));
      pos = c[1];
    }
    sb.write(text.substring(pos));
    return sb.toString();
  }

  static bool _isFragment(String t) => t.length <= 2 && _alnumRe.hasMatch(t);

  static bool _isNoiseRun(List<String> frags) {
    if (frags.length < 3) return false;
    final singles = frags.where((f) => f.length == 1).length;
    if (singles < 2) return false;
    return frags.any((f) => _digitRe.hasMatch(f)) || frags.length >= 4;
  }

  static bool _onlyBlanks(String text, int from, int to) {
    for (var i = from; i < to; i++) {
      final c = text.codeUnitAt(i);
      if (c != 0x20 && c != 0x09) return false;
    }
    return true;
  }

  /// 去替换字符 / 莫忘码
  static String stripMojibake(String s) {
    if (s.isEmpty) return s;
    var t = s.replaceAll('\uFFFD', '');
    t = t.replaceAll('锟斤拷', '');
    t = t.replaceAll(RegExp(r'[烫屯]{3,}'), '');
    t = t.replaceAll(RegExp(r'\?{3,}'), '');
    t = t.replaceAll(RegExp(r'\u25A1{3,}'), '');
    return t;
  }

  /// 原文（整本，未分章）清洗：换行归一 → 乱码/莫忘码 → 屏蔽规则。
  /// 不重排段首缩进，交给后续的 splitParagraphs 处理。
  static String cleanRawText(String text, CleanOptions o) {
    if (o.isNoop) return text;
    var t = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    if (o.stripNoise) t = stripNoiseRuns(t);
    if (o.stripMojibake) t = stripMojibake(t);
    return applyRules(t, o.rules);
  }

  /// 已入库章节文本的清洗：规则 → 乱码 → 莫忘码 → 段落归一。
  static String cleanChapterContent(String content, CleanOptions o) {
    if (o.isNoop) return content;
    var t = applyRules(content, o.rules);
    if (o.stripNoise) t = stripNoiseRuns(t);
    if (o.stripMojibake) t = stripMojibake(t);
    return normalizeParagraphs(t);
  }

  /// 段落归一（与 book_importer.splitParagraphs 同口径）：逐行 trim、
  /// 丢空白行、段首补两个全角空格。
  static String normalizeParagraphs(String text) {
    final out = <String>[];
    for (final line in text.split('\n')) {
      final s = line.trim();
      if (s.isEmpty) continue;
      out.add(s.startsWith('　') ? s : '　　$s');
    }
    return out.join('\n');
  }

  static String applyRules(String text, List<CleanRule> rules) {
    var t = text;
    for (final r in rules) {
      if (!r.enabled || r.pattern.trim().isEmpty) continue;
      try {
        t = t.replaceAll(RegExp(r.pattern, multiLine: true), '');
      } on FormatException {
        // 规则库 UI 已校验；此处兜底跳过
      }
    }
    return t;
  }

  /// 统计启用规则在 [text] 上的命中次数（预览用，不做替换）
  static int countHits(String text, List<CleanRule> rules) {
    var n = 0;
    for (final r in rules) {
      if (!r.enabled || r.pattern.trim().isEmpty) continue;
      try {
        n += RegExp(r.pattern, multiLine: true)
            .allMatches(text)
            .where((m) => m[0]!.isNotEmpty)
            .length;
      } on FormatException {
        // 忽略非法正则
      }
    }
    return n;
  }

  /// 由阅读器选区生成「头尾锚点」屏蔽规则。
  /// [head] / [tail] 为选区所在的整段文本（定位失败时传 null，退回选区首/末行）。
  static CleanRule buildRuleFromSelection(String selection, {String? head, String? tail}) {
    final lines = [
      for (final l in selection.split('\n'))
        if (l.trim().isNotEmpty) l.trim(),
    ];
    final h = (head != null && head.trim().isNotEmpty ? head.trim() : (lines.isEmpty ? '' : lines.first));
    final t = (tail != null && tail.trim().isNotEmpty ? tail.trim() : (lines.isEmpty ? '' : lines.last));
    final pattern = lines.length <= 1 && h == t
        ? '^\\s*${RegExp.escape(h)}.*\$'
        : '^\\s*${RegExp.escape(h)}[\\s\\S]*?${RegExp.escape(t)}\\s*\$';
    final name = h.length <= 12 ? h : '${h.substring(0, 12)}…';
    return CleanRule(name: name.isEmpty ? '未命名规则' : name, pattern: pattern);
  }

  /// 在 [text] 上试跑一条正则，统计命中次数 / 删除字数 / 前几条片段。
  static RulePreview previewRule(String text, String pattern) {
    if (pattern.trim().isEmpty) return const RulePreview();
    RegExp re;
    try {
      re = RegExp(pattern, multiLine: true);
    } on FormatException {
      return const RulePreview(invalid: true);
    }
    var hits = 0;
    var removed = 0;
    final samples = <String>[];
    for (final m in re.allMatches(text)) {
      final s = m[0]!;
      if (s.isEmpty) continue; // 空匹配不产生删除，不计入
      hits++;
      removed += s.length;
      if (samples.length < 3) samples.add(snippet(s));
    }
    return RulePreview(hits: hits, removed: removed, samples: samples);
  }

  /// 命中片段预览：空白折叠 + 截断
  static String snippet(String s, {int max = 60}) {
    final flat = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (flat.length <= max) return flat;
    return '${flat.substring(0, max)}…';
  }
}
