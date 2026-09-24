// 主题扩展：阅读器取背景/正文颜色（随设置实时读取）
import 'package:flutter/material.dart';

import '../services/settings_service.dart';

extension AppThemeX on BuildContext {
  Color get readerBackground => switch (SettingsService.instance.themeMode) {
        'dark' => const Color(0xFF121212),
        'sepia' => const Color(0xFFF5ECD9),
        _ => Colors.white,
      };

  Color get readerText => switch (SettingsService.instance.themeMode) {
        'dark' => const Color(0xFFC8C8C8),
        'sepia' => const Color(0xFF3E3322),
        _ => const Color(0xFF222222),
      };
}
