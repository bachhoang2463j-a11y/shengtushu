// PDF 导出：章节文字 + 已生成插图，中文字体内嵌
import 'dart:io';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/database.dart';

class PdfExporter {
  pw.Font? _font;

  /// 加载内嵌中文字体（assets/fonts/NotoSansSC-Regular.ttf）
  Future<void> _ensureFont() async {
    if (_font != null) return;
    final bytes = await rootBundle.load('assets/fonts/NotoSansSC-Regular.ttf');
    _font = pw.Font.ttf(bytes);
  }

  /// 导出整本书（含已生成插图），返回输出文件路径。
  /// [outputPath] 由调用方用 path_provider 解析（如 Download/Documents 目录）。
  Future<String> export(AppDatabase db, Book book, {required String outputPath}) async {
    await _ensureFont();
    final chapters = await (db.select(db.chapters)
          ..where((t) => t.bookId.equals(book.id))
          ..orderBy([(t) => OrderingTerm.asc(t.idx)]))
        .get();
    final ills = await (db.select(db.illustrations)
          ..where((t) => t.bookId.equals(book.id))
          ..where((t) => t.status.equals('done')))
        .get();
    // chapterId → (afterParagraph → 插图列表)
    final illsByChapter = <int, Map<int, List<Illustration>>>{};
    for (final i in ills) {
      final map = illsByChapter[i.chapterId] ??= {};
      (map[i.afterParagraph] ??= []).add(i);
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: _font, bold: _font),
    );

    // 书名页
    doc.addPage(pw.Page(
      pageFormat: PdfPageFormat.a5,
      build: (context) => pw.Center(
        child: pw.Column(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
          pw.Text(book.title, style: pw.TextStyle(fontSize: 28, font: _font)),
          if (book.author.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 12),
              child: pw.Text(book.author, style: pw.TextStyle(fontSize: 14, font: _font)),
            ),
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 24),
            child: pw.Text('生图书 · 导出于 ${DateTime.now().toIso8601String().split('T').first}',
                style: pw.TextStyle(
                    fontSize: 10, font: _font, color: const PdfColor(0.5, 0.5, 0.5))),
          ),
        ]),
      ),
    ));

    for (final ch in chapters) {
      final paras = ch.content.split('\n');
      final byPara = illsByChapter[ch.id] ?? const <int, List<Illustration>>{};

      doc.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 44),
        build: (context) => [
          pw.Header(
            level: 1,
            child: pw.Text(ch.title, style: pw.TextStyle(fontSize: 18, font: _font)),
          ),
          for (var i = 0; i < paras.length; i++) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(paras[i], style: pw.TextStyle(fontSize: 11, font: _font)),
            ),
            for (final ill in byPara[i] ?? const <Illustration>[])
              if (ill.imagePath != null && File(ill.imagePath!).existsSync())
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(vertical: 8),
                  child: pw.Image(
                    pw.MemoryImage(File(ill.imagePath!).readAsBytesSync()),
                    fit: pw.BoxFit.contain,
                  ),
                ),
          ],
        ],
      ));
    }

    final file = File(outputPath);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(await doc.save());
    return outputPath;
  }
}
