import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

class DocumentExport {
  static const channel = MethodChannel('shengtushu/document_export');

  static Future<String?> save(File file) => channel.invokeMethod<String>('saveDocument', {
    'path': file.path,
    'name': p.basename(file.path),
    'mimeType': file.path.toLowerCase().endsWith('.txt') ? 'text/plain' : 'application/zip',
  });
}
