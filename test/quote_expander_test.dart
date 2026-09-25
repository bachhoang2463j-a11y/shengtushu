// QuoteExpander 引号扩展单测（引号统一用 \u201C\u201D 显式转义，避免编辑器写成 ASCII 引号）
import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/services/quote_expander.dart';

void main() {
  const open = '\u201C'; // "
  const close = '\u201D'; // "

  group('QuoteExpander.expand', () {
    test('长按引号内的词 → 扩展为整句引文', () {
      final paras = ['他说：$open你好呀，今天天气不错。$close然后转身离开。'];
      expect(QuoteExpander.expand(paras, '你好呀'), '你好呀，今天天气不错。');
    });

    test('选中带首尾引号的整句 → 剥离引号', () {
      final paras = ['他说：$open你好呀。$close'];
      expect(QuoteExpander.expand(paras, '$open你好呀。$close'), '你好呀。');
    });

    test('同段多组对话 → 扩展到所在那一对引号', () {
      final paras = ['A说：$open第一句。$close，B说：$open第二句来了。$close末尾'];
      expect(QuoteExpander.expand(paras, '第二'), '第二句来了。');
      expect(QuoteExpander.expand(paras, '第一'), '第一句。');
    });

    test('无引号 → 原样返回', () {
      final paras = ['平淡叙述没有引号。'];
      expect(QuoteExpander.expand(paras, '平淡叙述'), '平淡叙述');
    });

    test('只有闭引号在左侧（选区在引号外）→ 不扩展', () {
      final paras = ['A说：$open一${close}B 二 C$open二${close}D'];
      expect(QuoteExpander.expand(paras, '二'), '二');
    });

    test('闭引号之后没有开引号配对 → 不扩展', () {
      final paras = ['他说：$open你好呀'];
      expect(QuoteExpander.expand(paras, '你好'), '你好');
    });

    test('选区本身含引号（单侧）→ 不扩展', () {
      final paras = ['他说：$open你好呀。$close然后离开。'];
      expect(QuoteExpander.expand(paras, '说：$open你好呀'), '说：$open你好呀');
    });

    test('选区与原文空白差异不影响定位', () {
      final paras = ['他 说：$open你好呀，来玩啊。$close走了'];
      expect(QuoteExpander.expand(paras, '你 好 呀'), '你好呀，来玩啊。');
    });

    test('空选区 → 空', () {
      expect(QuoteExpander.expand(['正文'], ''), '');
    });
  });
}
