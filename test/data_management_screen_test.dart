import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shengtushu/data/database.dart';
import 'package:shengtushu/services/document_export.dart';
import 'package:shengtushu/services/generation_service.dart';
import 'package:shengtushu/services/library_activity.dart';
import 'package:shengtushu/services/settings_service.dart';
import 'package:shengtushu/ui/data_management_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('另存通过系统文档接口传文件路径，不传整包字节；取消返回null', () async {
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(DocumentExport.channel, (call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(DocumentExport.channel, null));
    final file = File(p.join(Directory.systemTemp.path, '书库.zip'));
    expect(await DocumentExport.save(file), isNull);
    expect(calls.single.method, 'saveDocument');
    expect(calls.single.arguments, {
      'path': file.path, 'name': '书库.zip', 'mimeType': 'application/zip',
    });
  });

  testWidgets('数据管理提供整库备份入口，忙碌写入时明确提示且不创建备份', (tester) async {
    SharedPreferences.setMockInitialValues({'demoLayoutV1': true});
    await SettingsService.instance.init();
    final db = AppDatabase.forTest(NativeDatabase.memory());
    GenerationService.instance.attachDb(db);
    GenerationService.instance.queue.clear();
    await tester.pumpWidget(MaterialApp(home: DataManagementScreen(db: db)));
    expect(find.text('备份全部书籍'), findsOneWidget);
    expect(find.text('从备份导入'), findsOneWidget);
    await LibraryActivity.instance.write(() async {
      await tester.tap(find.text('备份全部书籍'));
      await tester.pumpAndSettle();
      expect(find.textContaining('书库仍有导入'), findsOneWidget);
    });
    expect(find.text('另存到…'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 50));
    await db.close();
  });
}
