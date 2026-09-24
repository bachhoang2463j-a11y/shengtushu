// 分页引擎：把「段落 + 插图占位」流切成页。
// 流式产出：先出前几批页立即可读，其余继续在事件循环间隙排版（不冻结 UI）。
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// 版面单元
sealed class PageBlock {
  final int paragraphIndex; // 对应章节段落序号（0-based）
  const PageBlock(this.paragraphIndex);
}

/// 文本块：段落的某个行区间（用于跨页长段落）
class TextBlock extends PageBlock {
  final String text;
  final bool isFirst; // 该段在本页起始（决定段前距/首行缩进样式）
  final bool isLast;
  const TextBlock(super.paragraphIndex, {required this.text, required this.isFirst, required this.isLast});
}

/// 插图块（占位符或成图）
class ImageBlock extends PageBlock {
  final int illustrationId;
  final String status; // pending|running|done|failed
  final String? imagePath;
  final double aspect; // width / height
  final String error;
  final String prompt;
  const ImageBlock(super.paragraphIndex, {required this.illustrationId, required this.status,
      required this.aspect, this.imagePath, this.error = '', this.prompt = ''});
}

class ReaderPage {
  final List<PageBlock> blocks;
  const ReaderPage(this.blocks);
}

/// 版面输入项
sealed class LayoutItem {
  const LayoutItem();
}

class TextItem extends LayoutItem {
  final int paragraphIndex;
  final String text;
  const TextItem(this.paragraphIndex, this.text);
}

class ImageItem extends LayoutItem {
  final ImageBlock block;
  const ImageItem(this.block);
}

class PageLayoutConfig {
  final double width; // 正文内容宽度（px, logical）
  final double height; // 正文内容高度
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final double paragraphSpacing;

  const PageLayoutConfig({
    required this.width,
    required this.height,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily = '',
    this.paragraphSpacing = 10,
  });
}

class Paginator {
  /// 流式分页：每处理 [chunkSize] 个版面项让出一次事件循环并产出已完成的新页。
  static Stream<List<ReaderPage>> paginateStream({
    required List<LayoutItem> items,
    required PageLayoutConfig config,
    int chunkSize = 80,
  }) async* {
    final style = TextStyle(
      fontSize: config.fontSize,
      height: config.lineHeight,
      fontFamily: config.fontFamily.isEmpty ? null : config.fontFamily,
      color: const ui.Color(0xFF000000),
    );

    final pages = <List<PageBlock>>[];
    var current = <PageBlock>[];
    var used = 0.0;
    var sinceYield = 0;
    var yieldedCount = 0; // 已产出的页数（每次只产出增量，严禁全量快照）

    void newPage() {
      if (current.isNotEmpty) pages.add(current);
      current = <PageBlock>[];
      used = 0.0;
    }

    for (final item in items) {
      if (item is ImageItem) {
        final h = config.width / item.block.aspect.clamp(0.2, 5.0);
        if (used > 0 && used + h > config.height) newPage();
        if (used + h > config.height && current.isEmpty) {
          // 单图高于整页：缩到整页高度
          current.add(item.block);
          used = config.height;
          newPage();
          continue;
        }
        current.add(item.block);
        used += h + config.paragraphSpacing * 0.5;
        continue;
      }

      final par = item as TextItem;
      final remaining = config.height - used;
      if (remaining < config.fontSize * config.lineHeight) {
        newPage();
      }
      // 整段测量
      final painted = _paint(par.text, style, config.width);
      final lineMetrics = painted.computeLineMetrics();
      final lineCount = lineMetrics.length;
      var fromLine = 0;
      var lineIdx = 0;
      var firstChunk = true;

      while (lineIdx < lineCount || (lineCount == 0 && firstChunk)) {
        final avail = config.height - used;
        if (avail < config.fontSize * config.lineHeight && current.isNotEmpty) {
          newPage();
          continue;
        }
        if (lineCount == 0 && firstChunk) {
          // 空段
          current.add(TextBlock(par.paragraphIndex, text: '', isFirst: true, isLast: true));
          used += config.fontSize * config.lineHeight;
          firstChunk = false;
          break;
        }
        // 从 fromLine 起累积行，直到放不下
        var endLine = fromLine;
        double acc = 0;
        while (endLine < lineCount) {
          final lh = lineMetrics[endLine].height + (endLine == 0 && firstChunk ? config.paragraphSpacing : 0);
          if (acc + lh > avail && acc > 0) break;
          acc += lh;
          endLine++;
        }
        if (endLine == fromLine) {
          // 单行都放不下且页为空（极端字号），强制放一行防死循环
          endLine = fromLine + 1;
          acc = lineMetrics[fromLine].height;
        }
        // 计算该行区间对应的字符区间
        final fromChar = fromLine == 0 ? 0 : _charOffsetAtLine(lineMetrics, painted, fromLine);
        final toChar = endLine >= lineCount ? par.text.length : _charOffsetAtLine(lineMetrics, painted, endLine);
        final slice = par.text.substring(fromChar, toChar);
        current.add(TextBlock(par.paragraphIndex,
            text: slice, isFirst: fromLine == 0, isLast: endLine >= lineCount));
        used += acc;
        lineIdx = endLine;
        fromLine = endLine;
        firstChunk = false;
        if (used >= config.height - 0.5) newPage();
      }
      painted.dispose();

      sinceYield++;
      if (sinceYield >= chunkSize) {
        sinceYield = 0;
        await Future<void>.delayed(Duration.zero);
        if (pages.length > yieldedCount) {
          final delta = pages.sublist(yieldedCount);
          yieldedCount = pages.length;
          yield [for (final b in delta) ReaderPage(b)];
        }
      }
    }
    if (current.isNotEmpty) pages.add(current);
    if (pages.length > yieldedCount) {
      yield [for (final b in pages.sublist(yieldedCount)) ReaderPage(b)];
    }
  }

  static TextPainter _paint(String text, TextStyle style, double width) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout(maxWidth: width);
    return tp;
  }

  /// 第 [line] 行（0-based）起始字符偏移
  static int _charOffsetAtLine(List<ui.LineMetrics> metrics, TextPainter tp, int line) {
    if (line < 0 || line >= metrics.length) return 0;
    final m = metrics[line];
    final pos = tp.getPositionForOffset(ui.Offset(0, m.baseline - m.ascent + m.height * 0.5));
    return pos.offset;
  }
}
