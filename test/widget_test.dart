// 基础单元测试：默认模板 / 章节分割 / 变量替换 / 默认映射
import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/data/import/book_importer.dart';
import 'package:shengtushu/services/comfyui_client.dart';
import 'package:shengtushu/services/generation_service.dart';
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

  test('%变量% 替换：文本/数值生效，未识别变量保留原样', () {
    final client = ComfyUIClient();
    final wf = {
      '8': {'inputs': {'text': '%prompt%'}, 'class_type': 'CLIPTextEncode'},
      '3': {'inputs': {'text': '%negative%'}, 'class_type': 'CLIPTextEncode'},
      '5': {'inputs': {'width': '%width%', 'height': '%height%', 'batch_size': 1}},
      '10': {'inputs': {'seed': '%seed%', 'steps': 8}},
      'x': {'inputs': {'keep': '%unknown_var%'}},
      '6': {'inputs': {'samples': ['10', 0], 'vae': ['4', 0]}},
    };
    final out = client.prepareWorkflow(
      workflow: wf,
      mapping: const WorkflowMapping(),
      positive: 'masterpiece, 1girl',
      negative: 'bad quality',
      width: 1280,
      height: 720,
      batch: 1,
      autoRandomSeed: true,
    );
    dynamic inp(String node) => (out[node] as Map)['inputs'];
    expect(inp('8')['text'], 'masterpiece, 1girl');
    expect(inp('3')['text'], 'bad quality');
    expect(inp('5')['width'], 1280);
    expect(inp('5')['height'], 720);
    expect(inp('10')['seed'], isA<num>());
    expect(inp('x')['keep'], '%unknown_var%');
    // 连接线引用必须保持字符串（曾因转成 int 导致 ComfyUI KeyError）
    expect(inp('6')['samples'], ['10', 0]);
    expect(inp('6')['vae'], ['4', 0]);
    // 原工作流不被修改
    expect((wf['8'] as Map)['inputs']['text'], '%prompt%');
  });

  test('选区末尾定位：短选区优先视口附近，跨段选区尾部截短匹配', () {
    final paras = [
      '　　张飞倒提着丈八蛇矛走向大营。', // 0
      '　　营帐连绵十里。', // 1
      '　　他停下脚步，看向远方。', // 2
      '　　远处尘土飞扬。', // 3
      '　　他再次停下，观察四周。', // 4
    ];
    // 短选区「下」在 hint=2 附近 → 应命中第 2 段而非更远段
    final (p1, o1) = GenerationService.locateSelectionEnd(paras, '下', hintParagraph: 2);
    expect(p1, 2);
    expect(o1, greaterThan(0));
    // 跨段选区（尾部落在第 4 段）→ 尾部截短后命中第 4 段
    final (p2, o2) = GenerationService.locateSelectionEnd(
        paras, '营帐连绵十里。远处尘土飞扬。他再次停下，', hintParagraph: 1);
    expect(p2, 4);
    expect(o2, greaterThan(0));
  });
}
