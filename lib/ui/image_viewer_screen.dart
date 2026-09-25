// 插图查看器：缩放浏览 + 保存到相册 + 查看提示词
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:photo_view/photo_view.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.imagePath, required this.prompt, this.onDelete});
  final String imagePath;
  final String prompt;

  /// 传入则在顶栏显示「删除当前图」按钮（回调负责确认与关闭本页）
  final VoidCallback? onDelete;

  Future<void> _saveToGallery(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await Gal.putImage(imagePath);
      messenger.showSnackBar(const SnackBar(content: Text('已保存到相册')));
    } on GalException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：${e.type.message}')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('插图'),
        actions: [
          if (onDelete != null)
            IconButton(
              tooltip: '删除这张图',
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('删除这张图'),
                    content: const Text('只删除当前查看的这张，其他版本保留，确定？'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
                      FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('删除')),
                    ],
                  ),
                );
                if (ok == true) onDelete!();
              },
            ),
          IconButton(
            tooltip: '保存到相册',
            icon: const Icon(Icons.save_alt),
            onPressed: file.existsSync() ? () => _saveToGallery(context) : null,
          ),
        ],
      ),
      body: Column(children: [
        Expanded(
          child: PhotoView(
            imageProvider: FileImage(file),
            minScale: PhotoViewComputedScale.contained,
            backgroundDecoration: const BoxDecoration(color: Colors.black),
          ),
        ),
        SafeArea(
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            color: Colors.black87,
            child: Text(
              prompt,
              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.5),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ]),
    );
  }
}
