// 预设（LLM / 生词模板）的序列化与持久化往返测试
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengtushu/services/settings_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await SettingsService.instance.init();
  });

  group('LlmPreset', () {
    test('JSON 往返保留全部字段', () {
      final p = LlmPreset(
        id: '1',
        name: 'DeepSeek',
        llm: LlmConfig(
          baseUrl: 'https://api.deepseek.com',
          apiKey: 'sk-test',
          model: 'deepseek-chat',
          temperature: 0.5,
          maxTokens: 4096,
        ),
      );
      final back = LlmPreset.fromJson(p.toJson());
      expect(back.id, '1');
      expect(back.name, 'DeepSeek');
      expect(back.llm.baseUrl, 'https://api.deepseek.com');
      expect(back.llm.apiKey, 'sk-test');
      expect(back.llm.model, 'deepseek-chat');
      expect(back.llm.temperature, 0.5);
      expect(back.llm.maxTokens, 4096);
    });

    test('缺省字段回落默认值', () {
      final back = LlmPreset.fromJson({});
      expect(back.id, '');
      expect(back.name, '');
      expect(back.llm.model, 'deepseek-chat');
    });
  });

  group('StylePreset', () {
    test('JSON 往返，workflowId 可空', () {
      final p = StylePreset(id: 'a', name: '动漫风', styleText: '画质：masterpiece', workflowId: 7);
      final back = StylePreset.fromJson(p.toJson());
      expect(back.id, 'a');
      expect(back.styleText, '画质：masterpiece');
      expect(back.workflowId, 7);

      final unbound = StylePreset(id: 'b', name: '未绑定', styleText: 'x');
      expect(StylePreset.fromJson(unbound.toJson()).workflowId, isNull);
    });
  });

  group('SettingsService 预设存取', () {
    test('llmPresets 持久化往返与清空', () async {
      final s = SettingsService.instance;
      expect(s.llmPresets, isEmpty);

      await s.setLlmPresets([
        LlmPreset(id: '1', name: 'A', llm: LlmConfig(model: 'm1')),
        LlmPreset(id: '2', name: 'B', llm: LlmConfig(model: 'm2')),
      ]);
      final back = s.llmPresets;
      expect(back.length, 2);
      expect(back[1].name, 'B');
      expect(back[1].llm.model, 'm2');

      await s.setLlmPresets([]);
      expect(s.llmPresets, isEmpty);
    });

    test('stylePresets 持久化往返', () async {
      final s = SettingsService.instance;
      await s.setStylePresets([
        StylePreset(id: '1', name: '写实', styleText: '画质：realistic', workflowId: 3),
      ]);
      final back = s.stylePresets;
      expect(back.single.name, '写实');
      expect(back.single.styleText, '画质：realistic');
      expect(back.single.workflowId, 3);
    });

    test('预设快照独立于当前 llm/styleText 配置', () async {
      final s = SettingsService.instance;
      await s.setLlm(LlmConfig(model: 'current-model', apiKey: 'k1'));
      await s.setLlmPresets(
          [LlmPreset(id: '1', name: 'A', llm: LlmConfig(model: 'preset-model'))]);
      await s.setStyleText('当前画风');

      // 改当前配置不影响预设快照
      await s.setLlm(LlmConfig(model: 'changed'));
      expect(s.llmPresets.single.llm.model, 'preset-model');
      expect(s.llm.model, 'changed');
      expect(s.stylePresets, isEmpty);
    });
  });
}
