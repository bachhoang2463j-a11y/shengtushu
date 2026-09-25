// ComfyUI 客户端：连接层核心。
// 提交/轮询/下载流程移植自 NEKOparapa/ReaDreamAI 的 comfyui_platform.dart（GPL-3.0），
// 改造点：工作流与节点映射来自本地数据库；%变量% 替换语法（移植自生图助手脚本）；
// WebSocket 失败自动降级轮询 /history；进度以 Stream 暴露给 UI。
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
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

  /// 脚本语法：把工作流 JSON 里字符串值中的 %prompt% %negative% %width% %height% %seed% %batch%
  /// 替换为实际值；若整个字符串就是单个数值型变量则转为 num。
  /// 注意：只有含 %占位符% 的字符串才参与转换——连接线引用等普通字符串（如 "10"）必须原样保留。
  Map<String, dynamic> replaceVariables(
      Map<String, dynamic> workflow, Map<String, Object?> vars) {
    Object? walk(Object? node) {
      if (node is Map) {
        return node.map((k, v) => MapEntry(k.toString(), walk(v)));
      }
      if (node is List) {
        return node.map(walk).toList();
      }
      if (node is String) {
        if (!node.contains('%')) return node; // 链接引用等原样保留
        var s = node;
        for (final e in vars.entries) {
          s = s.replaceAll('%${e.key}%', '${e.value}');
        }
        if (s.contains('%')) return s; // 还有未识别的变量，保持原样
        final trimmed = s.trim();
        final n = num.tryParse(trimmed);
        if (n != null && RegExp(r'^-?\d+(\.\d+)?$').hasMatch(trimmed)) return n;
        return s;
      }
      return node;
    }

    return (walk(workflow) as Map).cast<String, dynamic>();
  }

  /// 按映射克隆工作流并替换节点输入值。
  /// 先做 %变量% 替换（脚本语法），再做节点映射覆盖（映射优先级更高）。
  Map<String, dynamic> prepareWorkflow({
    required Map<String, dynamic> workflow,
    required WorkflowMapping mapping,
    required String positive,
    String? negative,
    int? width,
    int? height,
    int? batch,
    int? seed,
    bool autoRandomSeed = true,
  }) {
    // 种子：显式指定优先；未指定时随机。ComfyUI 同种子产出完全相同的图，
    // 映射缺种子节点或工作流用 %seed% 时若落到固定 0，会导致「重新生图」返回原图。
    final actualSeed = seed ??
        ((autoRandomSeed || mapping.seed == null)
            ? Random().nextInt(1 << 30) * 4294967296 + Random().nextInt(1 << 30)
            : null);
    var wf = replaceVariables(workflow, {
      'prompt': positive,
      'negative': negative ?? '',
      'width': width ?? 0,
      'height': height ?? 0,
      'seed': actualSeed ?? 0,
      'batch': batch ?? 1,
    });

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
    if (actualSeed != null) setByRole(mapping.seed, actualSeed, '种子');
    return wf;
  }

  /// 提交 → 监听进度 → 完成后取历史 → 下载图片，返回本地保存路径。
  /// [onProgress] 每个事件回调（进度/阶段提示）。
  /// [saveFile]：完整的本地保存路径（含文件名）。传入时用它保存，避免沿用
  /// ComfyUI 端输出文件名导致同名覆盖、旧图路径指向新内容（历史版本错乱）。
  Future<String> generate({
    required String baseUrl,
    required Map<String, dynamic> workflow,
    required WorkflowMapping mapping,
    required String positive,
    String? negative,
    required String saveDir,
    String? saveFile,
    int? width,
    int? height,
    int? batch,
    bool autoRandomSeed = true,
    void Function(ComfyProgress p)? onProgress,
  }) async {
    final base = normalizeUrl(baseUrl);
    final clientId = const Uuid().v4();

    void say(String m) {
      debugPrint('[ComfyUI] $m');
      onProgress?.call(ComfyProgress(message: m));
    }

    say('提交工作流…');
    final promptId = await _queuePrompt(base, workflow, mapping, clientId, positive, negative, width, height, batch, autoRandomSeed);
    say('已入队（任务 $promptId）…');

    await _waitForCompletion(base, promptId, clientId, onProgress);
    say('执行完成，获取结果…');

    Map<String, dynamic> history;
    try {
      history = await _getHistory(base, promptId);
    } on ComfyUIException {
      say('结果未就绪，轮询等待…');
      await _pollHistory(base, promptId);
      history = await _getHistory(base, promptId);
    }
    final paths = await _downloadImages(base, history, saveDir, saveFile);
    debugPrint('[ComfyUI] 图片已保存: $paths');
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
    try {
      await _waitForCompletionWs(base, promptId, clientId, onProgress);
    } on ComfyUIException catch (e) {
      // WS 不可用（如被代理/服务器拒绝）→ 降级为轮询 /history
      if (e.message.startsWith('WebSocket')) {
        debugPrint('[ComfyUI] WebSocket 不可用，降级轮询 /history：${e.message}');
        await _pollHistory(base, promptId);
      } else {
        rethrow;
      }
    }
  }

  Future<void> _pollHistory(String base, String promptId) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(seconds: 2));
      try {
        final r = await client.get(Uri.parse('$base/history/$promptId')).timeout(const Duration(seconds: 10));
        if (r.statusCode != 200) continue;
        final history = jsonDecode(r.body) as Map<String, dynamic>;
        final entry = history[promptId];
        if (entry is! Map<String, dynamic>) continue;
        final status = entry['status'];
        if (status is Map && status['status_str'] == 'error') {
          throw const ComfyUIException('执行出错（历史状态 error）');
        }
        return; // 有记录即视为完成
      } on ComfyUIException {
        rethrow;
      } catch (_) {
        continue; // 网络抖动继续轮询
      }
    }
    throw const ComfyUIException('轮询超时：任务未完成');
  }

  Future<void> _waitForCompletionWs(String base, String promptId, String clientId,
      void Function(ComfyProgress)? onProgress) async {
    final wsUri = Uri.parse('${base.replaceFirst('http', 'ws')}/ws?clientId=$clientId');
    final completer = Completer<void>();
    WebSocketChannel? channel;
    StreamSubscription? sub;
    Timer? watchdog;

    try {
      channel = WebSocketChannel.connect(wsUri);
      // ready 失败与 stream onError 同源；不 catch 会成为未处理异步错误（污染全局 Zone）
      unawaited(channel.ready.catchError((Object _) {}));
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

  Future<String> _downloadImages(
      String base, Map<String, dynamic> history, String saveDir, String? saveFile) async {
    final outputs = history['outputs'];
    if (outputs is! Map<String, dynamic>) {
      throw const ComfyUIException('历史记录无输出节点');
    }
    if (saveFile == null) {
      final dir = Directory(saveDir);
      if (!await dir.exists()) await dir.create(recursive: true);
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
        final path = saveFile ?? '${Directory(saveDir).path}${Platform.pathSeparator}$filename';
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
