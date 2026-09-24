// 基础单元测试：默认模板与章节分割
import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/data/import/book_importer.dart';
import 'package:shengtushu/services/prompt_service.dart';
import 'package:shengtushu/services/settings_service.dart';

void main() {
  test('默认独立生图模板包含全部占位符', () {
    final tpl = defaultIndepTemplate();
    expect(tpl, isNotEmpty);
    final all = tpl.map((m) => m.content).join('\n');
    for (final ph in [
      PromptPlaceholders.history,
      PromptPlaceholders.current,
      PromptPlaceholders.style,
      PromptPlaceholders.personas,
      PromptPlaceholders.lore,
    ]) {
      expect(all.contains(ph), isTrue, reason: '缺少占位符 $ph');
    }
  });

  test('insertions 解析：围栏/IMG_GEN/越界过滤', () {
    final svc = PromptService();
    final raw = '''
一些前缀文字
```json
{"insertions": [
  {"after_paragraph": 1, "prompt": "分析：xxx\\n[IMG_GEN]masterpiece, 1girl[/IMG_GEN]"},
  {"after_paragraph": 2, "prompt": "outdoor, sunset"},
  {"after_paragraph": 9, "prompt": "should be dropped"}
]}
```
''';
    final result = svc.parseInsertions(raw, maxParagraph: 2);
    expect(result.length, 2);
    expect(result[0].prompt, 'masterpiece, 1girl');
    expect(result[1].prompt, 'outdoor, sunset');
  });

  test('TXT 章节分割与段首缩进', () {
    final text = '''
第一章 开端

　　这是第一段。

　　这是第二段。

第二章 转折

　　新的内容。
''';
    final chapters = splitChapters(text);
    expect(chapters.length, 2);
    expect(chapters[0].title, '第一章 开端');
    expect(chapters[0].content.split('\n').first.startsWith('　　'), isTrue);
  });
}
