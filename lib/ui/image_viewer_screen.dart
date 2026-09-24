// 插图查看器：缩放浏览 + 保存到相册 + 查看提示词
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:photo_view/photo_view.dart';

class ImageViewerScreen extends StatelessWidget {
  const ImageViewerScreen({super.key, required this.imagePath, required this.prompt});
  final String imagePath;
  final String prompt;

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
