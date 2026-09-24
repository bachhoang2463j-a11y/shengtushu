// LLM 客户端：OpenAI 兼容 /chat/completions（与脚本 buildLLMRequestBody 同构）
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'settings_service.dart';

class LlmException implements Exception {
  final String message;
  const LlmException(this.message);
  @override
  String toString() => message;
}

class LlmClient {
  LlmClient({http.Client? client}) : client = client ?? http.Client();
  final http.Client client;

  Future<String> chat(LlmConfig cfg, List<TplMessage> messages, {int? maxTokensOverride}) async {
    var base = cfg.baseUrl.trim();
    if (base.isEmpty) throw const LlmException('LLM baseUrl 为空');
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    if (!base.endsWith('/v1')) base = '$base/v1';

    final body = {
      'model': cfg.model,
      'messages': messages.map((m) => {'role': m.role, 'content': m.content}).toList(),
      'stream': false,
      'max_tokens': maxTokensOverride ?? cfg.maxTokens,
      'temperature': cfg.temperature,
    };

    final r = await client.post(
      Uri.parse('$base/chat/completions'),
      headers: {
        'Content-Type': 'application/json',
        if (cfg.apiKey.isNotEmpty) 'Authorization': 'Bearer ${cfg.apiKey}',
      },
      body: jsonEncode(body),
    ).timeout(const Duration(minutes: 3));

    if (r.statusCode != 200) {
      throw LlmException('LLM HTTP ${r.statusCode}：${_truncate(r.body)}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) {
      throw const LlmException('LLM 响应缺少 choices');
    }
    final msg = (choices[0] as Map<String, dynamic>)['message'];
    if (msg is! Map || msg['content'] == null) {
      throw const LlmException('LLM 响应缺少 message.content');
    }
    return (msg['content'] as String).trim();
  }

  String _truncate(String s, [int n = 300]) => s.length <= n ? s : '${s.substring(0, n)}…';
}
