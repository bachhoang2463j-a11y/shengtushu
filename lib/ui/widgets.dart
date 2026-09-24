// 共享小部件与工具
import 'package:flutter/material.dart';

Color colorFor(int id) {
  const palette = [
    Color(0xFF5B7CB6), Color(0xFFB0745B), Color(0xFF6FAF7C), Color(0xFF9B6FAF),
    Color(0xFFB6A05B), Color(0xFF5BAFB0), Color(0xFFAF5B74), Color(0xFF7C85A6),
  ];
  return palette[id % palette.length];
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
      child: Text(title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
    );
  }
}

/// 设置页通用行容器
class SettingRow extends StatelessWidget {
  const SettingRow({super.key, required this.title, this.subtitle, this.trailing, this.onTap});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle!, style: const TextStyle(fontSize: 12)),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// 带保存的文本输入对话框
Future<String?> textInputDialog(
  BuildContext context, {
  required String title,
  String initial = '',
  int maxLines = 1,
  String hint = '',
  bool obscure = false,
}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctrl,
        maxLines: maxLines,
        obscureText: obscure,
        decoration: InputDecoration(hintText: hint, border: const OutlineInputBorder()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('取消')),
        FilledButton(onPressed: () => Navigator.pop(c, ctrl.text), child: const Text('确定')),
      ],
    ),
  );
}
