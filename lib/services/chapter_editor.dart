// 选区编辑：定位选区起止 → 精确替换 → 插图锚点哈希重定位
import 'package:drift/drift.dart' show Value;

import '../data/database.dart';

class ChapterEditor {
  /// 定位选区起点：用选区头部（前 ≤16 个非空白字符）在视口附近扩散匹配，
  /// 返回 (段落序号, 段内字符偏移)——偏移为头部首字符的位置；找不到返回 (-1, -1)。
  static (int, int) locateSelectionStart(List<String> paras, String selection, {int hintParagraph = 0}) {
    final target = strip(selection);
    if (target.isEmpty || paras.isEmpty) return (-1, -1);
    var head = target.length < 16 ? target : target.substring(0, 16);
    final clampedHint = hintParagraph.clamp(0, paras.length - 1);
    for (var l = head.length; l >= 1; l--) {
      if (l < head.length) head = target.substring(0, l);
      for (var dist = 0; dist < paras.length; dist++) {
        for (final i in {clampedHint - dist, clampedHint + dist}) {
          if (i < 0 || i >= paras.length) continue;
          final idx = strip(paras[i]).indexOf(head);
          if (idx >= 0) return (i, _mapStrippedToOriginal(paras[i], idx));
        }
      }
    }
    return (-1, -1);
  }

  /// 把选中范围 [startPara/startOffset, endPara/endOffset) 的文本替换为
  /// [editedText]（可含换行=拆分段落），更新章节并按内容哈希重定位插图。
  static Future<void> replaceSelection(
    AppDatabase db,
    Chapter chapter, {
    required int startPara,
    required int startOffset,
    required int endPara,
    required int endOffset,
    required String editedText,
  }) async {
    final paras = chapter.content.split('\n');
    if (startPara < 0 || endPara >= paras.length || startPara > endPara) {
      throw ArgumentError('选区范围越界');
    }
    final startLine = paras[startPara];
    final endLine = paras[endPara];
    final prefix = startLine.substring(0, startOffset.clamp(0, startLine.length));
    final suffix = endOffset <= endLine.length ? endLine.substring(endOffset) : '';
    final merged = (prefix + editedText + suffix).split('\n');
    final newParas = [
      ...paras.sublist(0, startPara),
      ...merged,
      ...paras.sublist(endPara + 1),
    ];
    await rewriteContent(db, chapter.id, newParas.join('\n'));
  }

  /// 整章重写正文并重锚定插图（选区编辑、文本清洗共用同一套口径）。
  static Future<void> rewriteContent(AppDatabase db, int chapterId, String newContent) async {
    final newParas = newContent.split('\n');
    final newHashes = {for (var i = 0; i < newParas.length; i++) hash(newParas[i]): i};

    await db.transaction(() async {
      await (db.update(db.chapters)..where((t) => t.id.equals(chapterId)))
          .write(ChaptersCompanion(content: Value(newContent)));
      // 重锚定：段落文本哈希一致 → 迁移；不一致（本段被编辑）→ 夹紧到有效范围
      final ills = await (db.select(db.illustrations)
            ..where((t) => t.chapterId.equals(chapterId)))
          .get();
      for (final ill in ills) {
        var newIdx = newHashes[ill.anchorHash];
        newIdx ??= ill.afterParagraph.clamp(0, newParas.length - 1);
        if (newIdx != ill.afterParagraph) {
          await (db.update(db.illustrations)..where((t) => t.id.equals(ill.id)))
              .write(IllustrationsCompanion(afterParagraph: Value(newIdx)));
        }
      }
    });
  }

  static String strip(String s) => s.replaceAll(RegExp(r'\s+'), '');

  /// 把「去空白后的字符序号」映射回原文字符偏移（该字符之前的位置）
  static int _mapStrippedToOriginal(String original, int strippedIndex) {
    if (strippedIndex <= 0) return 0;
    var count = 0;
    for (var i = 0; i < original.length; i++) {
      if (RegExp(r'\s').hasMatch(original[i])) continue;
      count++;
      if (count == strippedIndex) return i + 1;
    }
    return original.length;
  }

  /// FNV-1a 32bit 段落哈希（与 GenerationService 保持一致）
  static String hash(String s) {
    var h = 0x811c9dc5;
    for (final code in s.runes) {
      h ^= code & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
      h ^= (code >> 8) & 0xFF;
      h = (h * 0x01000193) & 0xFFFFFFFF;
    }
    return h.toRadixString(16).padLeft(8, '0');
  }
}
