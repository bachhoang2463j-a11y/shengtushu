// 朗读服务：MiMo（OpenAI 风格 /chat/completions 音频模态）与豆包（unidirectional NDJSON）
// 请求构造移植自 Conversation_avatar/emotion-avatar.js（synthesizeMimo / synthesizeDoubao）
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import 'settings_service.dart';

class TtsService extends ChangeNotifier {
  TtsService._() {
    // 播放自然结束的信号源（audioplayers 的 play() 在开始播放后即完成，不等播完）
    _player.onPlayerComplete.listen((_) {
      _pendingDone?.complete();
      _pendingDone = null;
      if (_playing) {
        _playing = false;
        notifyListeners();
      }
    });
  }
  static final TtsService instance = TtsService._();

  final _player = AudioPlayer();
  Completer<void>? _pendingDone;
  bool _playing = false;
  int _seq = 0; // 每次 speak 递增；被停止/新朗读取代后旧结果作废
  File? _lastFile;

  bool get isPlaying => _playing;

  /// 停止当前播放/作废进行中的合成
  Future<void> stop() async {
    _seq++;
    _pendingDone?.complete();
    _pendingDone = null;
    try {
      await _player.stop();
    } catch (_) {}
    if (_playing) {
      _playing = false;
      notifyListeners();
    }
  }

  /// 合成并朗读；失败抛 Exception（中文消息，可直接展示给用户）
  Future<void> speak(String text) async {
    final t = text.trim();
    if (t.isEmpty) throw const TtsException('没有可朗读的文本');
    await stop();
    final seq = ++_seq;

    final cfg = SettingsService.instance.tts;
    final Uint8List bytes;
    final String mime;
    if (cfg.engine == 'doubao') {
      bytes = await _synthesizeDoubao(t, cfg.doubao);
      mime = 'audio/mpeg';
    } else {
      bytes = await _synthesizeMimo(t, cfg.mimo);
      mime = cfg.mimo.format == 'mp3' ? 'audio/mpeg' : 'audio/wav';
    }
    if (seq != _seq) return; // 合成期间已被停止/取代

    // 落临时文件再播（DeviceFileSource 兼容性最好）；只保留最近一份
    try {
      await _lastFile?.delete();
    } catch (_) {}
    final dir = await getTemporaryDirectory();
    final f = File('${dir.path}/tts_read_${DateTime.now().millisecondsSinceEpoch}.${mime == 'audio/mpeg' ? 'mp3' : 'wav'}');
    await f.writeAsBytes(bytes);
    _lastFile = f;
    if (seq != _seq) {
      try { await f.delete(); } catch (_) {}
      return;
    }

    final done = Completer<void>();
    _pendingDone = done;
    _playing = true;
    notifyListeners();
    try {
      await _player.play(DeviceFileSource(f.path, mimeType: mime));
      // 等播放结束（自然播完 or stop() 解除）；30 分钟兜底防悬挂
      await done.future.timeout(const Duration(minutes: 30), onTimeout: () {});
    } finally {
      if (identical(_pendingDone, done)) _pendingDone = null;
      if (seq == _seq) {
        _playing = false;
        notifyListeners();
      }
    }
  }

  // ---------- MiMo（小米）：POST {baseUrl}/chat/completions，base64 在 choices[0].message.audio.data ----------
  Future<Uint8List> _synthesizeMimo(String text, TtsMimoConfig cfg) async {
    final key = cfg.apiKey.trim();
    if (key.isEmpty) throw const TtsException('MiMo API Key 未配置：设置 → 朗读音色');
    final base = cfg.baseUrl.trim().isEmpty
        ? 'https://api.xiaomimimo.com/v1'
        : cfg.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final format = cfg.format == 'mp3' ? 'mp3' : 'wav';
    var voice = cfg.voice.trim().isEmpty ? 'mimo_default' : cfg.voice.trim();
    var model = cfg.model.trim().isEmpty ? 'mimo-v2.5-tts' : cfg.model.trim();
    if (voice == TtsMimoConfig.cloneVoiceId) {
      // 音色复刻：voice 传参考音频 data URL，换专用克隆模型（同一 endpoint，响应结构不变）
      voice = await _cloneVoiceDataUrl(cfg);
      model = 'mimo-v2.5-tts-voiceclone';
    }
    final body = jsonEncode({
      'model': model,
      'messages': [
        {'role': 'assistant', 'content': text},
      ],
      'audio': {'format': format, 'voice': voice},
    });
    http.Response resp;
    try {
      resp = await http.post(
        Uri.parse('$base/chat/completions'),
        headers: {
          'Content-Type': 'application/json',
          'api-key': key,
          'Authorization': 'Bearer $key',
        },
        body: body,
      ).timeout(const Duration(seconds: 60));
    } catch (e) {
      throw TtsException('MiMo 网络请求失败：$e');
    }
    if (resp.statusCode != 200) {
      throw TtsException('MiMo HTTP ${resp.statusCode}：${_brief(resp.body)}');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(resp.body) as Map<String, dynamic>;
    } catch (_) {
      throw const TtsException('MiMo 返回了无法解析的内容');
    }
    final choices = data['choices'] as List?;
    final choice = (choices != null && choices.isNotEmpty && choices[0] is Map<String, dynamic>)
        ? choices[0] as Map<String, dynamic>
        : null;
    final message = choice?['message'] as Map<String, dynamic>?;
    if ('${choice?['finish_reason']}' == 'content_filter') {
      throw const TtsException('MiMo 内容过滤拦截了这段文本');
    }
    final audio = message?['audio'] as Map<String, dynamic>?;
    final b64 = audio?['data'] as String?;
    if (b64 == null || b64.isEmpty) {
      final err = data['error'];
      final msg = err is Map<String, dynamic> ? err['message'] : null;
      throw TtsException(msg == null || '$msg'.isEmpty ? 'MiMo 未返回音频数据' : 'MiMo：$msg');
    }
    return base64Decode(b64);
  }

  /// 克隆音色：读参考音频文件编码为 data URL（mimo-v2.5-tts-voiceclone 的 voice 参数）
  Future<String> _cloneVoiceDataUrl(TtsMimoConfig cfg) async {
    if (cfg.cloneAudioPath.isEmpty) {
      throw const TtsException('克隆音色未上传参考音频：设置 → 朗读音色 → 克隆参考音频');
    }
    final f = File(cfg.cloneAudioPath);
    if (!await f.exists()) {
      throw const TtsException('克隆参考音频文件已不存在，请到设置重新上传');
    }
    final ext = cfg.cloneAudioPath.split('.').last.toLowerCase();
    const mimes = {
      'wav': 'audio/wav',
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'ogg': 'audio/ogg',
      'flac': 'audio/flac',
    };
    final mime = mimes[ext] ?? 'audio/wav';
    return 'data:$mime;base64,${base64Encode(await f.readAsBytes())}';
  }

  // ---------- 豆包（火山引擎）：POST unidirectional，NDJSON 逐行 data base64 分片 ----------
  Future<Uint8List> _synthesizeDoubao(String text, TtsDoubaoConfig cfg) async {
    final appId = cfg.appId.trim();
    final accessKey = cfg.accessKey.trim();
    if (appId.isEmpty || accessKey.isEmpty) {
      throw const TtsException('豆包 App ID / Access Key 未配置：设置 → 朗读音色');
    }
    if (cfg.voice.trim().isEmpty) throw const TtsException('豆包音色未配置：设置 → 朗读音色');
    final resourceId = cfg.resourceId.trim().isEmpty ? 'seed-tts-2.0' : cfg.resourceId.trim();
    final uid = cfg.uid.trim().isEmpty ? '1222356' : cfg.uid.trim();
    final body = jsonEncode({
      'user': {'uid': uid},
      'req_params': {
        'text': text,
        'speaker': cfg.voice.trim(),
        'audio_params': {'format': 'mp3', 'sample_rate': 24000},
      },
    });
    http.Response resp;
    try {
      resp = await http.post(
        Uri.parse('https://openspeech.bytedance.com/api/v3/tts/unidirectional'),
        headers: {
          'Content-Type': 'application/json',
          'X-Api-App-Key': appId,
          'X-Api-Access-Key': accessKey,
          'X-Api-Resource-Id': resourceId,
        },
        body: body,
      ).timeout(const Duration(seconds: 60));
    } catch (e) {
      throw TtsException('豆包网络请求失败：$e');
    }
    if (resp.statusCode != 200) {
      throw TtsException('豆包 HTTP ${resp.statusCode}：${_brief(resp.body)}');
    }
    final chunks = <int>[];
    for (final line in resp.body.split(RegExp(r'\r?\n'))) {
      if (line.trim().isEmpty) continue;
      Map<String, dynamic> item;
      try {
        item = jsonDecode(line) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      final code = item['code'];
      if (code is num && code != 0 && code != 20000000) {
        throw TtsException('豆包合成失败：${item['message'] ?? code}');
      }
      final data = item['data'];
      if (data is String && data.isNotEmpty) chunks.addAll(base64Decode(data));
    }
    if (chunks.isEmpty) throw const TtsException('豆包未返回可用音频');
    return Uint8List.fromList(chunks);
  }

  static String _brief(String s) {
    final t = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t.length <= 120 ? t : '${t.substring(0, 120)}…';
  }
}

/// 带中文可读消息的 TTS 异常（与生图 GenerationException 同风格）
class TtsException implements Exception {
  final String message;
  const TtsException(this.message);
  @override
  String toString() => message;
}
