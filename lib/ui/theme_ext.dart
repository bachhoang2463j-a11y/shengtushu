// 主题扩展：阅读器取背景/正文/次级颜色（随设置实时读取），配色对齐 demo 原型
import 'package:flutter/material.dart';

import '../services/settings_service.dart';

extension AppThemeX on BuildContext {
  Color get readerBackground => switch (SettingsService.instance.themeMode) {
        'dark' => const Color(0xFF151719), // 夜间
        'sepia' => const Color(0xFFF5EEDB), // 羊皮纸
        'green' => const Color(0xFFE3EDE4), // 护眼绿
        _ => const Color(0xFFFAFAFA), // 纯白
      };

  Color get readerText => switch (SettingsService.instance.themeMode) {
        'dark' => const Color(0xFFD1D5DB),
        'sepia' => const Color(0xFF2C2723),
        'green' => const Color(0xFF203523),
        _ => const Color(0xFF1F2937),
      };

  Color get readerSub => switch (SettingsService.instance.themeMode) {
        'dark' => const Color(0xFF6B7280),
        'sepia' => const Color(0xFF7A7267),
        'green' => const Color(0xFF657D68),
        _ => const Color(0xFF9CA3AF),
      };
}
