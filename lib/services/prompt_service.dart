// 提示词服务：模板组装（占位符替换）+ insertions JSON 解析
// 占位符与 [IMG_GEN] 语法移植自「生图助手 v45.3.1」
import 'dart:convert';

import 'settings_service.dart';

/// 模板中可用的占位符
class PromptPlaceholders {
  static const history = '<!--历史上下文-->';
  static const lore = '<!--设定说明-->';
  static const style = '<!--生词模版-->';
  static const personas = '<!--人物列表-->';
  static const current = '<!--当前文本-->';
}

/// LLM 返回的一条插图指令
class Insertion {
  final int afterParagraph; // 1-based，对应当前批次的 [P1][P2]... 编号
  final String prompt; // 已剥离 [IMG_GEN] 包装的纯提示词
  const Insertion({required this.afterParagraph, required this.prompt});
}

class PromptService {
  /// 组装多消息模板。批次段落为 [paragraphs]（当前页），
  /// [history] 为其前 N 段文本，[lore] 为该书设定说明。
  List<TplMessage> buildMessages({
    required List<TplMessage> template,
    required List<String> paragraphs,
    required List<String> history,
    required String lore,
    required String styleText,
    required List<PersonaPreset> personas,
  }) {
    final numbered = [for (var i = 0; i < paragraphs.length; i++) '[P${i + 1}] ${paragraphs[i]}'].join('\n\n');
    final historyText = history.isEmpty ? '（无前文）' : history.join('\n\n');
    final loreText = lore.trim().isEmpty ? '（无）' : lore.trim();
    final styleT = styleText.trim().isEmpty ? '（无）' : styleText.trim();
    final personaList = personas.where((p) => p.enabled && p.tags.trim().isNotEmpty).toList();
    final personaText = personaList.isEmpty
        ? '（无）'
        : personaList.map((p) => '${p.name}: ${p.tags.trim()}').join('\n');

    String sub(String content) => content
        .replaceAll(PromptPlaceholders.history, historyText)
        .replaceAll(PromptPlaceholders.lore, loreText)
        .replaceAll(PromptPlaceholders.style, styleT)
        .replaceAll(PromptPlaceholders.personas, personaText)
        .replaceAll(PromptPlaceholders.current, numbered);

    return template.map((m) => TplMessage(role: m.role, content: sub(m.content))).toList();
  }

  /// 解析 LLM 输出 → insertions。
  /// 容错：剥离 ``` 围栏；截取首个平衡 JSON 对象；[IMG_GEN]…[/IMG_GEN] 取内部纯标签。
  List<Insertion> parseInsertions(String raw, {int maxParagraph = 1 << 30}) {
    final obj = _extractJsonObject(raw);
    if (obj == null) {
      throw const FormatException('未找到 JSON 对象');
    }
    final j = jsonDecode(obj);
    if (j is! Map<String, dynamic> || j['insertions'] is! List) {
      throw const FormatException('JSON 缺少 insertions 数组');
    }
    final out = <Insertion>[];
    for (final e in j['insertions'] as List) {
      if (e is! Map<String, dynamic>) continue;
      final n = (e['after_paragraph'] as num?)?.toInt();
      final p = (e['prompt'] ?? '').toString().trim();
      if (n == null || p.isEmpty) continue;
      if (n < 1 || n > maxParagraph) continue;
      out.add(Insertion(afterParagraph: n, prompt: _cleanPrompt(p)));
    }
    if (out.isEmpty) {
      throw const FormatException('insertions 为空');
    }
    return out;
  }

  String _cleanPrompt(String p) {
    var s = p.trim();
    final m = RegExp(r'\[IMG_GEN\]([\s\S]*?)\[/IMG_GEN\]').firstMatch(s);
    if (m != null) s = m.group(1)!.trim();
    s = s.replaceAll(RegExp(r'\\n'), ' ').replaceAll('\n', ' ').trim();
    return s;
  }

  /// 从文本中截取首个平衡的 {...}（考虑字符串与转义）
  String? _extractJsonObject(String raw) {
    var s = raw.trim();
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(s);
    if (fence != null) s = fence.group(1)!.trim();
    final start = s.indexOf('{');
    if (start < 0) return null;
    var depth = 0;
    var inStr = false;
    var esc = false;
    for (var i = start; i < s.length; i++) {
      final c = s[i];
      if (esc) {
        esc = false;
        continue;
      }
      if (c == '\\') {
        esc = true;
        continue;
      }
      if (c == '"') inStr = !inStr;
      if (inStr) continue;
      if (c == '{') depth++;
      if (c == '}') {
        depth--;
        if (depth == 0) return s.substring(start, i + 1);
      }
    }
    return null;
  }
}
