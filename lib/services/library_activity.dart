class LibraryBusyException implements Exception {
  final String message;
  const LibraryBusyException(this.message);
  @override
  String toString() => message;
}

/// 数据库事务不能保护图片文件；备份期间必须同时隔离文件和数据写入。
class LibraryActivity {
  LibraryActivity._();
  static final instance = LibraryActivity._();

  int _writers = 0;
  bool _transferring = false;
  bool get isTransferring => _transferring;

  Future<T> write<T>(Future<T> Function() action) async {
    if (_transferring) throw const LibraryBusyException('正在导出或恢复书库，请完成后重试');
    _writers++;
    try {
      return await action();
    } finally {
      _writers--;
    }
  }

  Future<T> transfer<T>(Future<T> Function() action) async {
    if (_transferring || _writers > 0) {
      throw const LibraryBusyException('书库仍有导入、编辑或生成任务，请等待完成后重试');
    }
    _transferring = true;
    try {
      return await action();
    } finally {
      _transferring = false;
    }
  }
}
