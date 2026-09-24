// ComfyUI 客户端：连接层核心。
// 提交/轮询/下载流程移植自 NEKOparapa/ReaDreamAI 的 comfyui_platform.dart（GPL-3.0），
// 改造点：工作流与节点映射来自本地数据库；进度以 Stream 暴露给 UI。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// 工作流节点映射：角色 → (节点ID, 字段名)
class WorkflowMapping {
  final String? positive; // "nodeId:field"
  final String? negative;
  final String? width;
  final String? height;
  final String? seed;
  final String? batch;

  const WorkflowMapping({this.positive, this.negative, this.width, this.height, this.seed, this.batch});

  static String? _enc(Map<String, dynamic>? m) =>
      (m == null || m['node'] == null || m['field'] == null) ? null : '${m['node']}:${m['field']}';

  factory WorkflowMapping.fromJson(String raw) {
    if (raw.trim().isEmpty) return const WorkflowMapping();
    try {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      return WorkflowMapping(
        positive: _enc(j['positive'] as Map<String, dynamic>?),
        negative: _enc(j['negative'] as Map<String, dynamic>?),
        width: _enc(j['width'] as Map<String, dynamic>?),
        height: _enc(j['height'] as Map<String, dynamic>?),
        seed: _enc(j['seed'] as Map<String, dynamic>?),
        batch: _enc(j['batch'] as Map<String, dynamic>?),
      );
    } catch (_) {
      return const WorkflowMapping();
    }
  }

  static Map<String, dynamic>? _dec(String? v) {
    if (v == null) return null;
    final i = v.indexOf(':');
    if (i <= 0) return null;
    return {'node': v.substring(0, i), 'field': v.substring(i + 1)};
  }

  Map<String, dynamic> toJson() => {
    'positive': _dec(positive), 'negative': _dec(negative),
    'width': _dec(width), 'height': _dec(height),
    'seed': _dec(seed), 'batch': _dec(batch),
  }..removeWhere((k, v) => v == null);
}

class ComfyProgress {
  final double? ratio; // 0..1（progress 事件）
  final String message;
  const ComfyProgress({this.ratio, required this.message});
}

class ComfyUIException implements Exception {
  final String message;
  const ComfyUIException(this.message);
  @override
  String toString() => message;
}

class ComfyUIClient {
  ComfyUIClient({http.Client? client, this.timeout = const Duration(minutes: 15)})
      : client = client ?? http.Client();
  final http.Client client;
  final Duration timeout;

  String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) throw const ComfyUIException('ComfyUI 地址为空');
    if (!u.startsWith('http://') && !u.startsWith('https://')) u = 'http://$u';
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  /// 连通测试：GET /system_stats
  Future<(bool ok, String detail)> testConnection(String rawUrl) async {
    final base = normalizeUrl(rawUrl);
    try {
      final r = await client.get(Uri.parse('$base/system_stats')).timeout(const Duration(seconds: 8));
      if (r.statusCode == 200) {
        return (true, '连接成功：$base');
      }
      return (false, 'HTTP ${r.statusCode}：$base');
    } catch (e) {
      return (false, '无法连接 $base（$e）');
    }
  }

  /// 按映射克隆工作流并替换节点输入值
  Map<String, dynamic> prepareWorkflow({
    required Map<String, dynamic> workflow,
    required WorkflowMapping mapping,
    required String positive,
    String? negative,
    int? width,
    int? height,
    int? batch,
    bool autoRandomSeed = true,
  }) {
    final wf = jsonDecode(jsonEncode(workflow)) as Map<String, dynamic>; // 深拷贝

    void setByRole(String? ref, Object value, String role) {
      if (ref == null) return;
      final i = ref.indexOf(':');
      if (i <= 0) return;
      final node = ref.substring(0, i);
      final field = ref.substring(i + 1);
      final n = wf[node];
      if (n is Map<String, dynamic> && n['inputs'] is Map<String, dynamic>) {
        (n['inputs'] as Map<String, dynamic>)[field] = value;
      } else {
        throw ComfyUIException('工作流中找不到节点 $node（$role 映射无效）');
      }
    }

    setByRole(mapping.positive, positive, '正向提示词');
    if (negative != null) setByRole(mapping.negative, negative, '负向提示词');
    if (width != null) setByRole(mapping.width, width, '宽度');
    if (height != null) setByRole(mapping.height, height, '高度');
    if (batch != null) setByRole(mapping.batch, batch, '批次数');
    if (autoRandomSeed && mapping.seed != null) {
      setByRole(mapping.seed, Random().nextInt(1 << 30), '种子');
    }
    return wf;
  }

  /// 提交 → 监听进度 → 完成后取历史 → 下载图片，返回本地保存路径。
  /// [onProgress] 每个事件回调（进度/阶段提示）。
  Future<String> generate({
    required String baseUrl,
    required Map<String, dynamic> workflow,
    required WorkflowMapping mapping,
    required String positive,
    String? negative,
    required String saveDir,
    int? width,
    int? height,
    int? batch,
    bool autoRandomSeed = true,
    void Function(ComfyProgress p)? onProgress,
  }) async {
    final base = normalizeUrl(baseUrl);
    final clientId = const Uuid().v4();

    void say(String m) => onProgress?.call(ComfyProgress(message: m));

    say('提交工作流…');
    final promptId = await _queuePrompt(base, workflow, mapping, clientId, positive, negative, width, height, batch, autoRandomSeed);
    say('已入队（任务 $promptId）…');

    await _waitForCompletion(base, promptId, clientId, onProgress);
    say('执行完成，获取结果…');

    final history = await _getHistory(base, promptId);
    final paths = await _downloadImages(base, history, saveDir);
    return paths;
  }

  Future<String> _queuePrompt(
      String base, Map<String, dynamic> workflow, WorkflowMapping mapping,
      String clientId, String positive, String? negative, int? width, int? height, int? batch,
      bool autoRandomSeed) async {
    final wf = prepareWorkflow(
      workflow: workflow, mapping: mapping, positive: positive, negative: negative,
      width: width, height: height, batch: batch, autoRandomSeed: autoRandomSeed);
    final r = await client.post(
      Uri.parse('$base/prompt'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'prompt': wf, 'client_id': clientId}),
    ).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw ComfyUIException('提交失败 HTTP ${r.statusCode}：${_truncate(r.body)}');
    }
    final data = jsonDecode(r.body) as Map<String, dynamic>;
    final err = data['node_errors'];
    if (err is Map && err.isNotEmpty) {
      throw ComfyUIException('工作流节点校验失败：${_truncate(jsonEncode(err))}');
    }
    final id = data['prompt_id'];
    if (id is! String || id.isEmpty) {
      throw const ComfyUIException('提交响应缺少 prompt_id');
    }
    return id;
  }

  Future<void> _waitForCompletion(String base, String promptId, String clientId,
      void Function(ComfyProgress)? onProgress) async {
    final wsUri = Uri.parse('${base.replaceFirst('http', 'ws')}/ws?clientId=$clientId');
    final completer = Completer<void>();
    WebSocketChannel? channel;
    StreamSubscription? sub;
    Timer? watchdog;

    try {
      channel = WebSocketChannel.connect(wsUri);
      sub = channel.stream.listen(
        (message) {
          if (message is! String) return;
          try {
            final data = jsonDecode(message) as Map<String, dynamic>;
            final type = data['type'] as String?;
            final eventData = data['data'];
            if (eventData is Map && eventData['prompt_id'] != null && eventData['prompt_id'] != promptId) {
              return; // 其他任务的事件
            }
            switch (type) {
              case 'progress':
                final v = (eventData['value'] as num?)?.toDouble() ?? 0;
                final max = (eventData['max'] as num?)?.toDouble() ?? 1;
                if (max > 0) onProgress?.call(ComfyProgress(ratio: v / max, message: '采样中 ${(v).toInt()}/${(max).toInt()}'));
                break;
              case 'executing':
                if (eventData is Map && eventData['node'] == null) {
                  if (!completer.isCompleted) completer.complete();
                }
                break;
              case 'execution_error':
              case 'execution_interrupted':
                if (!completer.isCompleted) {
                  completer.completeError(ComfyUIException('执行出错：${_truncate(jsonEncode(eventData))}'));
                }
                break;
            }
          } catch (_) {/* 忽略无法解析的心跳/二进制 */}
        },
        onError: (Object e) {
          if (!completer.isCompleted) completer.completeError(ComfyUIException('WebSocket 连接出错：$e'));
        },
        onDone: () {
          // 与 ReaDreamAI 相同策略：连接先行关闭时假定可能已完成，交由历史记录验证
          if (!completer.isCompleted) completer.complete();
        },
      );
      watchdog = Timer(timeout, () {
        if (!completer.isCompleted) completer.completeError(const ComfyUIException('等待执行超时'));
      });
      await completer.future;
    } finally {
      watchdog?.cancel();
      await sub?.cancel();
      try {
        await channel?.sink.close();
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>> _getHistory(String base, String promptId) async {
    final r = await client.get(Uri.parse('$base/history/$promptId')).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) {
      throw ComfyUIException('获取历史失败 HTTP ${r.statusCode}');
    }
    final history = jsonDecode(r.body) as Map<String, dynamic>;
    final entry = history[promptId];
    if (entry is! Map<String, dynamic>) {
      throw const ComfyUIException('历史记录中找不到该任务（可能被中断）');
    }
    return entry;
  }

  Future<String> _downloadImages(String base, Map<String, dynamic> history, String saveDir) async {
    final outputs = history['outputs'];
    if (outputs is! Map<String, dynamic>) {
      throw const ComfyUIException('历史记录无输出节点');
    }
    String? saved;
    for (final nodeOutput in outputs.values) {
      if (nodeOutput is! Map || !nodeOutput.containsKey('images')) continue;
      for (final imageInfo in (nodeOutput['images'] as List)) {
        if (imageInfo is! Map) continue;
        final filename = imageInfo['filename'] as String?;
        if (filename == null) continue;
        final subfolder = imageInfo['subfolder'] ?? '';
        final type = imageInfo['type'] ?? 'output';
        final uri = Uri.parse('$base/view?filename=$filename&subfolder=$subfolder&type=$type');
        final r = await client.get(uri).timeout(const Duration(seconds: 120));
        if (r.statusCode != 200) {
          throw ComfyUIException('下载图片 $filename 失败 HTTP ${r.statusCode}');
        }
        final dir = Directory(saveDir);
        if (!await dir.exists()) await dir.create(recursive: true);
        final path = '${dir.path}${Platform.pathSeparator}$filename';
        await File(path).writeAsBytes(r.bodyBytes);
        saved = path; // 多张时取最后一张
      }
    }
    if (saved == null) {
      throw const ComfyUIException('输出中未找到图片');
    }
    return saved;
  }

  String _truncate(String s, [int n = 300]) => s.length <= n ? s : '${s.substring(0, n)}…';
}
