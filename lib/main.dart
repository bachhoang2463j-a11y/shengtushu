import 'package:flutter/material.dart';

import 'data/database.dart';
import 'services/default_workflow.dart';
import 'services/generation_service.dart';
import 'services/settings_service.dart';
import 'ui/bookshelf_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SettingsService.instance.init();
  final db = AppDatabase();
  GenerationService.instance.attachDb(db);
  await seedDefaultWorkflow(db); // 首次启动内置 Z-Image 默认工作流
  runApp(ShengTuShuApp(db: db));
}

class ShengTuShuApp extends StatelessWidget {
  const ShengTuShuApp({super.key, required this.db});
  final AppDatabase db;

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final theme = settings.themeMode;
        return MaterialApp(
          title: '生图书',
          debugShowCheckedModeBanner: false,
          themeMode: switch (theme) {
            'dark' => ThemeMode.dark,
            _ => ThemeMode.light,
          },
          theme: _lightTheme(),
          darkTheme: _darkTheme(),
          home: Theme(
            data: theme == 'sepia' ? _sepiaTheme() : (theme == 'dark' ? _darkTheme() : _lightTheme()),
            child: BookshelfScreen(db: db),
          ),
        );
      },
    );
  }

  ThemeData _lightTheme() => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4A6DA7)),
      );

  ThemeData _darkTheme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF4A6DA7), brightness: Brightness.dark),
      );

  ThemeData _sepiaTheme() => ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF5ECD9),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF8B7355))
            .copyWith(surface: const Color(0xFFF5ECD9)),
      );
}
