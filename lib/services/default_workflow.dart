// 内置默认工作流：Z-Image Turbo（用户提供，%变量% 语法）
import 'package:drift/drift.dart' show Value;
import 'package:flutter/services.dart' show rootBundle;

import '../data/database.dart';
import 'comfyui_client.dart';

/// 默认工作流节点映射（与 assets/workflows/zimage_default.json 对应）：
/// 正向 8:text / 负向 3:text / 宽高 5:width,5:height / 种子 10:seed / 批次 5:batch_size
const String kDefaultZImageMapping = '{"positive":{"node":"8","field":"text"},'
    '"negative":{"node":"3","field":"text"},'
    '"width":{"node":"5","field":"width"},'
    '"height":{"node":"5","field":"height"},'
    '"seed":{"node":"10","field":"seed"},'
    '"batch":{"node":"5","field":"batch_size"}}';

const String kDefaultWorkflowAsset = 'assets/workflows/zimage_default.json';
const String kDefaultWorkflowName = 'Z-Image 默认（内置）';

/// 若工作流表为空则自动载入内置默认并启用；返回是否插入了默认工作流
Future<bool> seedDefaultWorkflow(AppDatabase db) async {
  final count = await db.select(db.workflows).get();
  if (count.isNotEmpty) return false;
  await loadDefaultWorkflow(db);
  return true;
}

/// 载入（或重复载入）内置默认工作流并启用它
Future<void> loadDefaultWorkflow(AppDatabase db) async {
  final json = await rootBundle.loadString(kDefaultWorkflowAsset);
  await db.transaction(() async {
    await db.update(db.workflows).write(const WorkflowsCompanion(isActive: Value(false)));
    await db.into(db.workflows).insert(WorkflowsCompanion.insert(
          name: kDefaultWorkflowName,
          apiJson: json,
          mapping: const Value(kDefaultZImageMapping),
          isActive: const Value(true),
        ));
  });
}

/// 校验默认工作流映射完整性（供测试）
bool validateDefaultMapping(String mappingJson) {
  final m = WorkflowMapping.fromJson(mappingJson);
  return m.positive == '8:text' &&
      m.negative == '3:text' &&
      m.width == '5:width' &&
      m.height == '5:height' &&
      m.seed == '10:seed' &&
      m.batch == '5:batch_size';
}
