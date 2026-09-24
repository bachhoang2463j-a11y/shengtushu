// PDF 导出页：整书导出（文字+插图）→ 分享/保存
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../services/pdf_exporter.dart';

class PdfExportScreen extends StatefulWidget {
  const PdfExportScreen({super.key, required this.db, required this.book});
  final AppDatabase db;
  final Book book;

  @override
  State<PdfExportScreen> createState() => _PdfExportScreenState();
}

class _PdfExportScreenState extends State<PdfExportScreen> {
  bool _exporting = false;
  String? _resultPath;
  String? _error;

  Future<void> _export() async {
    setState(() {
      _exporting = true;
      _error = null;
      _resultPath = null;
    });
    try {
      final docs = await getApplicationDocumentsDirectory();
      final outDir = Directory(p.join(docs.path, 'export'));
      await outDir.create(recursive: true);
      final safeName = widget.book.title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final path = p.join(outDir.path, '$safeName.pdf');
      final exporter = PdfExporter();
      final saved = await exporter.export(widget.db, widget.book, outputPath: path);
      setState(() => _resultPath = saved);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _share() async {
    if (_resultPath == null) return;
    await SharePlus.instance.share(ShareParams(files: [XFile(_resultPath!)], text: widget.book.title));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('导出 PDF')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('《${widget.book.title}》',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  const Text('· 包含全部章节文字\n· 包含已生成成功的插图\n· 中文字体内嵌，任何设备可读',
                      style: TextStyle(height: 1.8)),
                ]),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _exporting ? null : _export,
              icon: _exporting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined),
              label: Text(_exporting ? '正在导出…' : '导出 PDF'),
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text('导出失败：$_error', style: const TextStyle(color: Colors.red)),
            ],
            if (_resultPath != null) ...[
              const SizedBox(height: 16),
              Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('✅ 导出成功'),
                    const SizedBox(height: 6),
                    Text(_resultPath!, style: const TextStyle(fontSize: 11)),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonalIcon(
                onPressed: _share,
                icon: const Icon(Icons.share_outlined),
                label: const Text('分享 / 另存'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
