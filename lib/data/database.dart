// 数据层：drift 数据库定义
import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

/// 书籍表
class Books extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get author => text().withDefault(const Constant(''))();
  TextColumn get format => text()(); // txt | docx
  TextColumn get sourcePath => text().withDefault(const Constant(''))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get lastChapter => integer().withDefault(const Constant(0))();
  IntColumn get lastParagraph => integer().withDefault(const Constant(0))();
  // 设定说明（脚本「世界书」位的阅读版：人物设定/文风说明，注入 <!--设定说明-->）
  TextColumn get lore => text().withDefault(const Constant(''))();
}

/// 章节表：content 为段落文本，以单个 \n 分隔
class Chapters extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer().references(Books, #id)();
  IntColumn get idx => integer()();
  TextColumn get title => text()();
  TextColumn get content => text()();
}

/// 插图表：锚定到「章节 + 段落序号 + 段内偏移 + 段落内容哈希」
class Illustrations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get bookId => integer()();
  IntColumn get chapterId => integer()();
  IntColumn get afterParagraph => integer()();
  // 段内字符偏移：-1 = 段末（旧行为）；≥0 = 插在该段第 N 个字符之后（段中插图）
  IntColumn get anchorOffset => integer().withDefault(const Constant(-1))();
  TextColumn get anchorHash => text()();
  TextColumn get prompt => text()();
  TextColumn get imagePath => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('pending'))(); // pending|running|done|failed
  TextColumn get error => text().withDefault(const Constant(''))();
  // 占位符宽高比：pending 阶段用生成参数预估，完成后写入实际尺寸
  IntColumn get imgWidth => integer().withDefault(const Constant(1280))();
  IntColumn get imgHeight => integer().withDefault(const Constant(720))();
  // 历史版本图片路径（JSON 数组，旧→新）；imagePath 为当前展示图。
  // 重新生图时旧图移入这里，不删除；阅读器左右点按可在多张间切换。
  TextColumn get history => text().withDefault(const Constant('[]'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// ComfyUI 工作流预设（API 格式 JSON + 可替换节点映射）
class Workflows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get apiJson => text()();
  // JSON: {"positive":{"node":"6","field":"text"}, "negative":{...},
  //        "width":{...},"height":{...},"seed":{...},"batch":{...}}（除 positive 外均可缺省）
  TextColumn get mapping => text().withDefault(const Constant('{}'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [Books, Chapters, Illustrations, Workflows])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_open());

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.addColumn(illustrations, illustrations.anchorOffset);
      }
      if (from < 3) {
        await m.addColumn(illustrations, illustrations.history);
      }
    },
  );
}

DatabaseConnection _open() {
  return driftDatabase(name: 'shengtushu');
}
