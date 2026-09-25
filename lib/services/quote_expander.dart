// 引号自动扩展：把选区扩展到所在 "…" 引号内的文本（朗读用）。
// 规则：从选区起点向左、终点向右各找最近的中文引号字符，
// 左为开引号 "、右为闭引号 " → 判定选区在引号内，扩展为引号内的整句文本；
// 选区自身首尾恰好是一对引号 → 剥离引号；其余情况原样返回（仅 trim）。
// 定位复用选区生图同款「去空白回定位」（locateSelectionStart / locateSelectionEnd）。
import 'chapter_editor.dart';
import 'generation_service.dart';

class QuoteExpander {
  static const String _open = '\u201C'; // "
  static const String _close = '\u201D'; // "

  static String expand(List<String> paras, String selection, {int hintParagraph = 0}) {
    final sel = selection.trim();
    if (sel.isEmpty || paras.isEmpty) return sel;
    final stripped = stripEdges(sel);
    if (containsQuote(sel)) return stripped; // 选区自身含引号：最多做边缘剥离，不再扩展
    final (sp, so) = ChapterEditor.locateSelectionStart(paras, sel, hintParagraph: hintParagraph);
    final (ep, eo) = GenerationService.locateSelectionEnd(paras, sel, hintParagraph: hintParagraph);
    if (sp < 0 || ep < 0 || sp > ep) return stripped;

    final left = _scanQuote(paras[sp], so - 1, -1); // 起点（含 so-1）向左
    final right = _scanQuote(paras[ep], eo, 1); // 终点（含 eo）向右
    if (left == null || right == null) return stripped;
    if (left.$2 != _open || right.$2 != _close) return stripped;

    // 跨段时中间段落不得含引号（同段时两侧最近性已保证配对干净）
    for (var p = sp + 1; p < ep; p++) {
      if (containsQuote(paras[p])) return stripped;
    }

    if (sp == ep) {
      if (right.$1 <= left.$1) return stripped;
      return paras[sp].substring(left.$1 + 1, right.$1);
    }
    // 跨段引文（少见）：开引号之后到闭引号之前的全部内容
    return [
      paras[sp].substring(left.$1 + 1),
      ...[for (var p = sp + 1; p < ep; p++) paras[p]],
      paras[ep].substring(0, right.$1),
    ].join('\n');
  }

  /// 选区首尾恰为一对引号时剥离（可嵌套一层剥离）
  static String stripEdges(String s) {
    var t = s.trim();
    while (t.length >= 2 && t.startsWith(_open) && t.endsWith(_close)) {
      t = t.substring(1, t.length - 1).trim();
    }
    return t;
  }

  static bool containsQuote(String s) => s.contains(_open) || s.contains(_close);

  /// 从 [from] 起沿 [step]（-1 向左 / +1 向右）找最近的引号字符，返回 (下标, 字符)
  static (int, String)? _scanQuote(String s, int from, int step) {
    var i = from;
    while (i >= 0 && i < s.length) {
      final c = s[i];
      if (c == _open || c == _close) return (i, c);
      i += step;
    }
    return null;
  }
}
