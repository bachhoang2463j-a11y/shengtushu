// 导入解析：TXT / DOCX → 章节 + 段落
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart' as gbk;
import 'package:xml/xml.dart';

import '../../services/text_cleaner.dart';

/// 章节分割结果
class ImportedChapter {
  final String title;
  final String content; // 段落以 \n 连接
  const ImportedChapter({required this.title, required this.content});
}

/// 默认章节正则：第X章/回/节/卷/集/部/篇（含序号），行首允许空白
const String kDefaultChapterRegex = r'^\s*(第[0-9〇零一二三四五六七八九十百千万两]+[章回节卷集部篇].*)$';

/// 解码 TXT 字节：优先 UTF-8（含 BOM），失败回退 GBK
String decodeTxtBytes(Uint8List bytes) {
  if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
    return utf8.decode(bytes.sublist(3));
  }
  try {
    return utf8.decode(bytes); // utf8.allowMalformed = false，失败抛异常
  } on FormatException {
    return gbk.gbk.decode(bytes);
  }
}

/// 把整本文本切成段落（按空行/换行归并；正文段首加两格全角缩进）
List<String> splitParagraphs(String text) {
  final lines = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final paras = <String>[];
  final buf = StringBuffer();
  for (final line in lines) {
    if (line.trim().isEmpty) {
      if (buf.isNotEmpty) {
        paras.add(buf.toString().trim());
        buf.clear();
      }
    } else {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(line.trim());
    }
  }
  if (buf.isNotEmpty) paras.add(buf.toString().trim());
  // 中文阅读惯例：段首两个全角空格（同时参与分页测量，保证渲染一致）
  return [for (final p in paras) p.startsWith('　') ? p : '　　$p'];
}

/// 按正则切章节；无匹配（<2 章）时整本作为单章
List<ImportedChapter> splitChapters(String fullText, {String? regexStr}) {
  final paras = splitParagraphs(fullText);
  RegExp? re;
  if (regexStr != null && regexStr.trim().isNotEmpty) {
    try {
      re = RegExp(regexStr, multiLine: false);
    } on FormatException {
      re = null;
    }
  }
  re ??= RegExp(kDefaultChapterRegex);

  final chapters = <ImportedChapter>[];
  String curTitle = '正文';
  final curParas = <String>[];
  var matched = false;

  void flush() {
    if (curParas.isNotEmpty) {
      chapters.add(ImportedChapter(title: curTitle, content: curParas.join('\n')));
      curParas.clear();
    }
  }

  for (final p in paras) {
    if (re.firstMatch(p) != null && p.length < 80) {
      flush();
      curTitle = p.trim();
      matched = true;
    } else {
      curParas.add(p);
    }
  }
  flush();

  if (!matched || chapters.length < 2) {
    return [ImportedChapter(title: '正文', content: paras.join('\n'))];
  }
  return chapters;
}

/// DOCX → 段落文本（解压 word/document.xml，提取 w:p 下的 w:t 文本）
String extractDocxText(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final docFile = archive.findFile('word/document.xml');
  if (docFile == null) {
    throw const FormatException('不是有效的 DOCX 文件（缺少 word/document.xml）');
  }
  final xmlStr = utf8.decode(docFile.content as List<int>);
  final doc = XmlDocument.parse(xmlStr);

  final body = doc.rootElement.findElements('body').firstOrNull;
  final node = body ?? doc.rootElement;
  final paras = <String>[];
  for (final p in node.descendantElements.where((e) => e.name.local == 'p')) {
    final sb = StringBuffer();
    for (final t in p.descendantElements.where((e) => e.name.local == 't')) {
      sb.write(t.innerText);
    }
    final s = sb.toString().trim();
    if (s.isNotEmpty) paras.add(s);
  }
  return paras.join('\n\n');
}

/// 统一入口：按格式解析文件 →（可选文本清洗）→ 章节。
/// [cleanOptionsJson] 为 CleanOptions.toJson() 的 JSON 串（isolate 间传递用）。
List<ImportedChapter> importBookFile(String path,
    {String? chapterRegex, String? cleanOptionsJson}) {
  final bytes = File(path).readAsBytesSync();
  final lower = path.toLowerCase();
  var text = lower.endsWith('.docx') ? extractDocxText(bytes) : decodeTxtBytes(bytes);
  if (cleanOptionsJson != null && cleanOptionsJson.isNotEmpty) {
    text = TextCleaner.cleanRawText(text, CleanOptions.decode(cleanOptionsJson));
  }
  return splitChapters(text, regexStr: chapterRegex);
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
