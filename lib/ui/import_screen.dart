// 静读天下式导入套件：智能全盘/常用目录扫描 + 目录文件树浏览 + 系统文件选择器
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/database.dart';
import '../data/import/book_importer.dart';
import '../services/settings_service.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.db});
  final AppDatabase db;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _scanning = false;
  bool _importing = false;
  double _importProgress = 0.0;
  String _importStatus = '';

  // 扫描结果列表
  List<ScannedBookFile> _scannedFiles = [];
  final Set<String> _selectedPaths = {};
  Set<String> _existingPaths = {};

  // 目录浏览状态
  Directory? _currentDir;
  List<FileSystemEntity> _dirEntries = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _initExistingAndScan();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  static List<ImportedChapter> _importTask((String, String) args) {
    return importBookFile(args.$1, chapterRegex: args.$2);
  }

  Future<void> _initExistingAndScan() async {
    final books = await widget.db.select(widget.db.books).get();
    _existingPaths = books.map((b) => b.sourcePath).whereType<String>().toSet();
    await _startScan();
    await _initFolderBrowser();
  }

  /// 智能扫描常用存储目录
  Future<void> _startScan() async {
    setState(() {
      _scanning = true;
      _scannedFiles = [];
      _selectedPaths.clear();
    });

    final targetDirs = <Directory>[];

    // Android 典型外部存储目录
    final candidatePaths = [
      '/storage/emulated/0/Download',
      '/storage/emulated/0/Documents',
      '/storage/emulated/0/Books',
      '/storage/emulated/0/Novel',
    ];

    for (final path in candidatePaths) {
      final dir = Directory(path);
      if (await dir.exists()) targetDirs.add(dir);
    }

    try {
      final appExt = await getExternalStorageDirectory();
      if (appExt != null && await appExt.exists()) targetDirs.add(appExt);
      final appDoc = await getApplicationDocumentsDirectory();
      if (await appDoc.exists()) targetDirs.add(appDoc);
    } catch (_) {}

    final found = <ScannedBookFile>[];
    for (final dir in targetDirs) {
      try {
        await for (final entity in dir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext == '.txt' || ext == '.docx') {
              final stat = await entity.stat();
              // 过滤小于 5KB 的微小临时文件
              if (stat.size >= 5 * 1024) {
                final isExisting = _existingPaths.contains(entity.path);
                found.add(ScannedBookFile(
                  path: entity.path,
                  name: p.basename(entity.path),
                  sizeBytes: stat.size,
                  modified: stat.modified,
                  isExisting: isExisting,
                ));
              }
            }
          }
        }
      } catch (_) {}
    }

    // 按修改时间降序排序
    found.sort((a, b) => b.modified.compareTo(a.modified));

    if (mounted) {
      setState(() {
        _scannedFiles = found;
        _scanning = false;
        // 默认勾选未入库的文件（前 10 本以内）
        for (final f in found.where((f) => !f.isExisting).take(10)) {
          _selectedPaths.add(f.path);
        }
      });
    }
  }

  /// 初始化目录树浏览器
  Future<void> _initFolderBrowser() async {
    Directory? initial;
    final download = Directory('/storage/emulated/0/Download');
    if (await download.exists()) {
      initial = download;
    } else {
      try {
        initial = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
      } catch (_) {}
    }
    if (initial != null) {
      await _navigateTo(initial);
    }
  }

  Future<void> _navigateTo(Directory dir) async {
    try {
      final list = await dir.list().toList();
      list.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path).toLowerCase().compareTo(p.basename(b.path).toLowerCase());
      });
      if (mounted) {
        setState(() {
          _currentDir = dir;
          _dirEntries = list;
        });
      }
    } catch (_) {}
  }

  Future<void> _navigateUp() async {
    if (_currentDir == null) return;
    final parent = _currentDir!.parent;
    if (await parent.exists() && parent.path != _currentDir!.path) {
      await _navigateTo(parent);
    }
  }

  /// 批量导入选中的书籍
  Future<void> _importSelected() async {
    if (_importing || _selectedPaths.isEmpty) return;
    final toImport = _scannedFiles.where((f) => _selectedPaths.contains(f.path)).toList();
    if (toImport.isEmpty) return;

    setState(() {
      _importing = true;
      _importProgress = 0.0;
      _importStatus = '准备导入 ${toImport.length} 本书籍…';
    });

    int successCount = 0;
    for (int i = 0; i < toImport.length; i++) {
      final item = toImport[i];
      setState(() {
        _importProgress = (i + 1) / toImport.length;
        _importStatus = '正在解析：${item.name} (${i + 1}/${toImport.length})';
      });

      try {
        final chapters = await compute(_importTask, (item.path, SettingsService.instance.chapterRegex));
        if (chapters.isNotEmpty) {
          final title = p.basenameWithoutExtension(item.path);
          await widget.db.transaction(() async {
            final bookId = await widget.db.into(widget.db.books).insert(BooksCompanion.insert(
                  title: title,
                  format: item.path.toLowerCase().endsWith('.docx') ? 'docx' : 'txt',
                  sourcePath: Value(item.path),
                ));
            for (var ci = 0; ci < chapters.length; ci++) {
              await widget.db.into(widget.db.chapters).insert(ChaptersCompanion.insert(
                    bookId: bookId,
                    idx: ci,
                    title: chapters[ci].title,
                    content: chapters[ci].content,
                  ));
            }
          });
          _existingPaths.add(item.path);
          successCount++;
        }
      } catch (e) {
        // 单本书解析失败不中断整体流程
      }
    }

    if (mounted) {
      setState(() => _importing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('批量导入完成：成功 $successCount 本')),
      );
      Navigator.pop(context, true);
    }
  }

  /// 快捷调用系统文件选择器单选/多选导入
  Future<void> _pickViaSystemPicker() async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'docx'],
    );
    if (files.isEmpty) return;

    for (final f in files) {
      if (f.path != null) {
        _selectedPaths.add(f.path!);
        if (!_scannedFiles.any((s) => s.path == f.path)) {
          _scannedFiles.insert(
            0,
            ScannedBookFile(
              path: f.path!,
              name: f.name,
              sizeBytes: f.lengthSync() ?? 0,
              modified: DateTime.now(),
              isExisting: false,
            ),
          );
        }
      }
    }
    setState(() {});
    await _importSelected();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final validSelectedCount = _selectedPaths.where((p) {
      final f = _scannedFiles.firstWhere((s) => s.path == p, orElse: () => ScannedBookFile.dummy);
      return !f.isExisting;
    }).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('导入本地书籍'),
        actions: [
          IconButton(
            tooltip: '调用系统文件选择器',
            icon: const Icon(Icons.folder_open),
            onPressed: _importing ? null : _pickViaSystemPicker,
          ),
          IconButton(
            tooltip: '重新扫描',
            icon: const Icon(Icons.refresh),
            onPressed: _importing || _scanning ? null : _startScan,
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: '智能扫描 (${_scannedFiles.length})'),
            const Tab(text: '目录浏览'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _buildScanTab(theme),
          _buildFolderTab(theme),
        ],
      ),
      bottomNavigationBar: _importing
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: theme.colorScheme.surfaceContainerHighest,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  LinearProgressIndicator(value: _importProgress),
                  const SizedBox(height: 6),
                  Text(_importStatus, style: const TextStyle(fontSize: 12)),
                ],
              ),
            )
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: Colors.grey.shade300, width: 0.5)),
                ),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: _scanning || _scannedFiles.isEmpty
                          ? null
                          : () {
                              setState(() {
                                final unimported = _scannedFiles.where((f) => !f.isExisting).map((f) => f.path);
                                if (_selectedPaths.length >= unimported.length) {
                                  _selectedPaths.clear();
                                } else {
                                  _selectedPaths.addAll(unimported);
                                }
                              });
                            },
                      icon: Icon(
                        _selectedPaths.isNotEmpty && _selectedPaths.length >= _scannedFiles.where((f) => !f.isExisting).length
                            ? Icons.check_box
                            : Icons.check_box_outline_blank,
                        size: 20,
                      ),
                      label: const Text('全选'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: validSelectedCount > 0 ? _importSelected : null,
                      icon: const Icon(Icons.download, size: 18),
                      label: Text('立即导入 ($validSelectedCount 本)'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildScanTab(ThemeData theme) {
    if (_scanning) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 14),
            Text('正在智能检索本地 TXT / DOCX 小说…', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_scannedFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.find_in_page_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text('常用目录下未检索到可用书籍', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            const Text('可切换至「目录浏览」或右上角「系统选择器」进行查找', style: TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _scannedFiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
      itemBuilder: (context, idx) {
        final f = _scannedFiles[idx];
        final isChecked = _selectedPaths.contains(f.path);
        return CheckboxListTile(
          value: isChecked,
          enabled: !f.isExisting,
          onChanged: (val) {
            setState(() {
              if (val == true) {
                _selectedPaths.add(f.path);
              } else {
                _selectedPaths.remove(f.path);
              }
            });
          },
          secondary: Icon(
            f.path.toLowerCase().endsWith('.docx') ? Icons.description_outlined : Icons.article_outlined,
            color: f.isExisting ? Colors.grey : theme.colorScheme.primary,
          ),
          title: Text(
            f.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: f.isExisting ? Colors.grey : null,
              decoration: f.isExisting ? TextDecoration.lineThrough : null,
            ),
          ),
          subtitle: Row(
            children: [
              Text(_formatSize(f.sizeBytes), style: const TextStyle(fontSize: 11)),
              const SizedBox(width: 8),
              if (f.isExisting)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('已在书架', style: TextStyle(fontSize: 10, color: Colors.grey)),
                )
              else
                Text(
                  p.dirname(f.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFolderTab(ThemeData theme) {
    if (_currentDir == null) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // 路径导航条
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 20),
                tooltip: '上一级',
                onPressed: _navigateUp,
              ),
              Expanded(
                child: Text(
                  _currentDir!.path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _dirEntries.isEmpty
            ? const Center(child: Text('当前目录为空', style: TextStyle(color: Colors.grey)))
            : ListView.builder(
                itemCount: _dirEntries.length,
                itemBuilder: (context, idx) {
                  final entity = _dirEntries[idx];
                  final isDir = entity is Directory;
                  final name = p.basename(entity.path);
                  final ext = p.extension(name).toLowerCase();
                  final isBook = ext == '.txt' || ext == '.docx';

                  return ListTile(
                    leading: Icon(
                      isDir
                          ? Icons.folder
                          : (ext == '.docx' ? Icons.description_outlined : Icons.article_outlined),
                      color: isDir
                          ? Colors.amber.shade700
                          : (isBook ? theme.colorScheme.primary : Colors.grey),
                    ),
                    title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: isBook
                        ? TextButton(
                            child: const Text('导入'),
                            onPressed: () {
                              _selectedPaths.clear();
                              _selectedPaths.add(entity.path);
                              _scannedFiles = [
                                ScannedBookFile(
                                  path: entity.path,
                                  name: name,
                                  sizeBytes: 0,
                                  modified: DateTime.now(),
                                  isExisting: false,
                                )
                              ];
                              _importSelected();
                            },
                          )
                        : null,
                    onTap: () {
                      if (isDir) {
                        _navigateTo(entity);
                      }
                    },
                  );
                },
              ),
        ),
      ],
    );
  }
}

class ScannedBookFile {
  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;
  final bool isExisting;

  const ScannedBookFile({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
    required this.isExisting,
  });

  static const dummy = ScannedBookFile(
    path: '',
    name: '',
    sizeBytes: 0,
    modified: _dummyDate,
    isExisting: false,
  );
}

const _dummyDate = _DummyDateTime();
class _DummyDateTime implements DateTime {
  const _DummyDateTime();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
