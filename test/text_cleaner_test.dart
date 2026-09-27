// 文本清洗：乱码片段判定正反例 / 莫忘码 / 头尾锚点规则生成与命中 / 导入链路
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/data/import/book_importer.dart';
import 'package:shengtushu/services/text_cleaner.dart';

void main() {
  group('去乱码碎片', () {
    test('示例碎片串被整体删除（成行/成段）', () {
      expect(TextCleaner.stripNoiseRuns('z u E w9 c w I8 a'), '');
      expect(TextCleaner.stripNoiseRuns('　　z u E w9 c w I8 a'), '　　');
    });

    test('夹在中文句子中间的碎片被删除，正文保留', () {
      expect(TextCleaner.stripNoiseRuns('张三z u E w9 c w I8 a走进房间'), '张三走进房间');
    });

    test('正常英文不被误伤', () {
      const keep = [
        'I am a boy',
        'to be or not to be',
        'OK, good job',
        '第 3 章',
        '他说：hello world，然后走了',
        'A B',
      ];
      for (final s in keep) {
        expect(TextCleaner.stripNoiseRuns(s), s, reason: '不该删：$s');
      }
    });

    test('阈值边界：3 片无数字不删，4 片删', () {
      expect(TextCleaner.stripNoiseRuns('a b c'), 'a b c');
      expect(TextCleaner.stripNoiseRuns('a b c d'), '');
      expect(TextCleaner.stripNoiseRuns('q w 9'), '');
    });

    test('跨行不合并（换行分隔的碎片不算同一串）', () {
      const s = 'a b c\nd e f';
      expect(TextCleaner.stripNoiseRuns(s), s);
    });
  });

  group('莫忘码', () {
    test('替换字符 / 锟斤拷 / 烫烫烫 / ??? / □□□', () {
      expect(TextCleaner.stripMojibake('张三\uFFFD走了'), '张三走了');
      expect(TextCleaner.stripMojibake('正文锟斤拷结束'), '正文结束');
      expect(TextCleaner.stripMojibake('正文烫烫烫结束'), '正文结束');
      expect(TextCleaner.stripMojibake('正文?????结束'), '正文结束');
      expect(TextCleaner.stripMojibake('正文□□□结束'), '正文结束');
      // 单个问号是正常标点
      expect(TextCleaner.stripMojibake('他走了?真的吗'), '他走了?真的吗');
    });
  });

  group('头尾锚点规则', () {
    const junk = '签名\n\n广告正文\n\n3.5万阅读\n\n152回复倒序';
    const chapter = '第一章 开始\n　　$junk\n　　真正的正文开始。\n　　正文第二段。';

    test('由选区整段生成跨行正则并命中整块', () {
      final rule = TextCleaner.buildRuleFromSelection(junk, head: '签名', tail: '152回复倒序');
      final p = TextCleaner.previewRule(chapter, rule.pattern);
      expect(p.invalid, isFalse);
      expect(p.hits, 1);
      expect(p.removed, greaterThan(junk.length - 8));
      expect(rule.name.startsWith('签名'), isTrue);
      // 应用后正文保留
      final cleaned = TextCleaner.cleanChapterContent(chapter, CleanOptions(rules: [rule]));
      expect(cleaned.contains('真正的正文开始。'), isTrue);
      expect(cleaned.contains('152回复倒序'), isFalse);
      expect(cleaned.contains('签名'), isFalse);
    });

    test('单行选区退化为整行删除', () {
      final rule = TextCleaner.buildRuleFromSelection('广告正文', head: '广告正文', tail: '广告正文');
      final p = TextCleaner.previewRule('　　$junk', rule.pattern);
      expect(p.hits, 1);
    });

    test('正则元字符被转义', () {
      final rule = TextCleaner.buildRuleFromSelection('a.b(c)[d]', head: 'a.b(c)[d]', tail: 'a.b(c)[d]');
      expect(TextCleaner.previewRule('a.b(c)[d]', rule.pattern).hits, 1);
      expect(TextCleaner.previewRule('aXbYcZd', rule.pattern).hits, 0);
    });

    test('非法正则报告 invalid', () {
      expect(TextCleaner.previewRule('任意', r'^\s*[').invalid, isTrue);
    });

    test('规则序列化往返', () {
      final o = CleanOptions(
        stripNoise: false,
        stripMojibake: true,
        rules: [CleanRule(name: '签名', pattern: r'^\s*签名\s*$', enabled: false)],
      );
      final back = CleanOptions.decode(jsonEncode(o.toJson()));
      expect(back.stripNoise, isFalse);
      expect(back.stripMojibake, isTrue);
      expect(back.rules.single.name, '签名');
      expect(back.rules.single.enabled, isFalse);
    });
  });

  group('导入链路', () {
    late File f;
    setUp(() {
      f = File('${Directory.systemTemp.path}/clean_import_test.txt');
    });
    tearDown(() {
      if (f.existsSync()) f.deleteSync();
    });

    test('带清洗选项导入：碎片删除、章节切分正常', () {
      f.writeAsStringSync(
        '第一章 起\n\n　　z u E w9 c w I8 a\n\n　　张三走进房间锟斤拷。\n\n第二章 承\n\n　　第二天。\n',
        encoding: utf8,
      );
      final chapters = importBookFile(f.path, cleanOptionsJson: jsonEncode(const CleanOptions().toJson()));
      expect(chapters.length, 2);
      expect(chapters[0].title, '第一章 起');
      expect(chapters[0].content.contains('z u'), isFalse);
      expect(chapters[0].content.contains('锟斤拷'), isFalse);
      expect(chapters[0].content.contains('张三走进房间'), isTrue);
      expect(chapters[1].content.contains('第二天'), isTrue);
    });

    test('不带清洗选项时保持原样', () {
      f.writeAsStringSync('第一章 起\n\n　　z u E w9 c w I8 a\n\n第二章 承\n\n　　第二天。\n', encoding: utf8);
      final chapters = importBookFile(f.path);
      expect(chapters[0].content.contains('z u E w9'), isTrue);
    });
  });
}
