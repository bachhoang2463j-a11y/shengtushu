import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../services/book_archive_service.dart';
import '../services/document_export.dart';
import '../services/generation_service.dart';
import '../services/image_store.dart';
import '../services/library_activity.dart';

enum DataTransferAction { text, backup, restore }

class DataManagementScreen extends StatefulWidget {
  const DataManagementScreen({super.key, required this.db, this.book, this.initialAction});
  final AppDatabase db;
  final Book? book;
  final DataTransferAction? initialAction;

  @override
  State<DataManagementScreen> createState() => _DataManagementScreenState();
}

class _DataManagementScreenState extends State<DataManagementScreen> {
  bool _busy = false;
  bool _cancelled = false;
  bool _saving = false;
  ArchiveProgress? _progress;
  File? _exported;
  String? _message;
  String? _error;
  final List<Directory> _temporaryExports = [];

  @override
  void initState() {
    super.initState();
    if (widget.initialAction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _run(widget.initialAction!);
      });
    }
  }

  @override
  void dispose() {
    _cancelled = true;
    for (final directory in _temporaryExports) {
      _cleanTemporary(directory);
    }
    super.dispose();
  }

  Future<void> _cleanTemporary(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // 系统分享目标尚持有文件时，交给系统清理应用临时目录。
    }
  }

  void _onProgress(ArchiveProgress progress) {
    if (mounted) setState(() => _progress = progress);
  }

  Future<void> _run(DataTransferAction action) async {
    if (_busy || _saving) return;
    File? source;
    if (action == DataTransferAction.restore) {
      setState(() => _saving = true);
      try {
      final selected = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['zip']);
      if (!mounted || selected.isEmpty || selected.first.path == null) return;
      source = File(selected.first.path!);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('从备份导入'),
          content: const Text('包内书籍将作为新书导入，不覆盖现有书籍，也不会自动生图。继续？'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('导入')),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      } catch (e) {
        if (mounted) setState(() => _error = '读取备份失败：$e');
        return;
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    setState(() {
      _busy = true;
      _cancelled = false;
      _error = null;
      _message = null;
      _progress = null;
    });
    try {
      if (GenerationService.instance.isBusy) {
        throw const LibraryBusyException('生成队列尚未结束，请等待完成后再导出或恢复');
      }
      await LibraryActivity.instance.transfer(() async {
        final service = BookArchiveService(widget.db,
            imagesRoot: await ImageStore.instance.baseDir(),
            temporaryRoot: Directory(p.join((await getTemporaryDirectory()).path, 'library_transfer')));
        bool cancelled() => _cancelled || !mounted;
        if (action == DataTransferAction.restore) {
          final result = await service.importArchive(source!, onProgress: _onProgress, isCancelled: cancelled);
          if (mounted) setState(() => _message = '已导入 ${result.bookCount} 本新书、${result.imageCount} 张图片，原书库保持不变');
        } else {
          final file = action == DataTransferAction.text
              ? await service.exportText(widget.book!.id, onProgress: _onProgress, isCancelled: cancelled)
              : await service.exportArchive(bookId: widget.book?.id, onProgress: _onProgress, isCancelled: cancelled);
          _temporaryExports.add(file.parent);
          if (!mounted) {
            await _cleanTemporary(file.parent);
            return;
          }
          setState(() {
            _exported = file;
            _message = '导出文件已准备好，请另存到应用外或通过系统分享保存';
          });
        }
      });
    } on ArchiveCancelledException {
      if (mounted) setState(() => _message = '已取消，本次临时数据已清理');
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save({required bool share}) async {
    final file = _exported;
    if (file == null || _saving || _busy) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (share) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)]));
      } else {
        final name = await DocumentExport.save(file);
        if (mounted) setState(() => _message = name == null ? '已取消另存，导出文件仍可保存' : '已另存：$name');
      }
    } catch (e) {
      if (mounted) setState(() => _error = '保存失败：$e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final disabled = _busy || _saving;
    return PopScope(
      canPop: !disabled,
      child: Scaffold(
        appBar: AppBar(title: const Text('数据管理')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            if (widget.book != null) ...[
              Text('《${widget.book!.title}》', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: disabled ? null : () => _run(DataTransferAction.text),
                icon: const Icon(Icons.description_outlined), label: const Text('导出 TXT'),
              ),
              const Text('导出当前正文，另存为 UTF-8 文本。不覆盖原文件，不含图片和阅读进度。'),
              const SizedBox(height: 20),
            ],
            FilledButton.icon(
              onPressed: disabled ? null : () => _run(DataTransferAction.backup),
              icon: const Icon(Icons.archive_outlined),
              label: Text(widget.book == null ? '备份全部书籍' : '备份本书'),
            ),
            const Text('ZIP 保留章节原文、设定说明、阅读进度、插图位置、当前图片及全部历史版本。\n不包含 API 凭据、工作流和应用配置。',
                style: TextStyle(height: 1.6)),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: disabled ? null : () => _run(DataTransferAction.restore),
              icon: const Icon(Icons.restore_page_outlined), label: const Text('从备份导入'),
            ),
            const Text('恢复为新书，同名也不覆盖。备份/恢复需等待正在进行的写入任务结束。'),
            if (_busy) ...[
              const SizedBox(height: 24),
              LinearProgressIndicator(value: progress == null || progress.total <= 0
                  ? null : (progress.completed / progress.total).clamp(0, 1)),
              const SizedBox(height: 8),
              Text(progress?.message ?? '正在准备…'),
              if (progress != null && progress.bytes > 0)
                Text('数据量：${(progress.bytes / 1024 / 1024).toStringAsFixed(1)} MB'),
              TextButton(
                onPressed: _cancelled ? null : () => setState(() => _cancelled = true),
                child: Text(_cancelled ? '正在取消…' : '取消操作'),
              ),
            ],
            if (_message != null) ...[
              const SizedBox(height: 20),
              Text(_message!, style: const TextStyle(height: 1.5)),
            ],
            if (_error != null) ...[
              const SizedBox(height: 20),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (_exported != null) ...[
              const SizedBox(height: 20),
              Text(p.basename(_exported!.path)),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: disabled ? null : () => _save(share: false),
                icon: const Icon(Icons.save_alt), label: const Text('另存到…'),
              ),
              OutlinedButton.icon(
                onPressed: disabled ? null : () => _save(share: true),
                icon: const Icon(Icons.share_outlined), label: const Text('系统分享'),
              ),
              const Text('离开页面后会清理本次临时导出文件，请先完成保存。'),
            ],
          ],
        ),
      ),
    );
  }
}
