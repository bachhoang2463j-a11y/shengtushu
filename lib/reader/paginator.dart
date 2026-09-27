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
  final List<String> history; // 历史版本图片路径（旧→新），排版缓存快照
  const ImageBlock(super.paragraphIndex, {required this.illustrationId, required this.status,
      required this.aspect, this.imagePath, this.error = '', this.prompt = '', this.history = const []});
}

class ReaderPage {
  final List<PageBlock> blocks;
  const ReaderPage(this.blocks);
}

/// 版面输入项
sealed class LayoutItem {
  const LayoutItem();

  /// 该项所属的章节段落序号（0-based）
  int get paragraphIndex;
}

class TextItem extends LayoutItem {
  @override
  final int paragraphIndex;
  final String text;
  const TextItem(this.paragraphIndex, this.text);
}

class ImageItem extends LayoutItem {
  final ImageBlock block;
  const ImageItem(this.block);

  @override
  int get paragraphIndex => block.paragraphIndex;
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

class LayoutBatch {
  final List<ReaderPage> pages;
  final List<double> flowHeights;
  final bool isComplete;
  const LayoutBatch(this.pages, this.flowHeights, {this.isComplete = false});
}

class Paginator {
  static Stream<List<ReaderPage>> paginateStream({
    required List<LayoutItem> items,
    required PageLayoutConfig config,
    int chunkSize = 80,
  }) async* {
    await for (final batch in layoutStream(items: items, config: config, chunkSize: chunkSize)) {
      if (batch.pages.isNotEmpty) yield batch.pages;
    }
  }

  /// 每次测量同时产出分页与连续流高度；批次只含增量，不保留全章快照。
  static Stream<LayoutBatch> layoutStream({
    required List<LayoutItem> items,
    required PageLayoutConfig config,
    int chunkSize = 16,
  }) async* {
    final style = TextStyle(
      fontSize: config.fontSize,
      height: config.lineHeight,
      fontFamily: config.fontFamily.isEmpty ? null : config.fontFamily,
      color: const ui.Color(0xFF000000),
    );
    var ready = <ReaderPage>[];
    var heights = <double>[];
    var current = <PageBlock>[];
    var used = 0.0;
    var prevPar = -1;
    var sinceYield = 0;
    final clock = Stopwatch()..start();

    void newPage() {
      if (current.isNotEmpty) ready.add(ReaderPage(current));
      current = <PageBlock>[];
      used = 0;
    }

    LayoutBatch takeBatch({bool complete = false}) {
      final batch = LayoutBatch(ready, heights, isComplete: complete);
      ready = <ReaderPage>[];
      heights = <double>[];
      sinceYield = 0;
      clock.reset();
      return batch;
    }

    for (final item in items) {
      if (item is ImageItem) {
        final h = (config.width / item.block.aspect.clamp(0.2, 5.0))
            .clamp(60.0, config.height - 12);
        heights.add(h + 12);
        if (used > 0 && used + h + 12 > config.height) newPage();
        if (current.isEmpty && h + 12 > config.height) {
          current.add(item.block);
          newPage();
        } else {
          current.add(item.block);
          used += h + 12 + config.paragraphSpacing * 0.5;
        }
      } else {
        final par = item as TextItem;
        if (config.height - used < config.fontSize * config.lineHeight) newPage();
        final painted = _paint(par.text, style, config.width);
        try {
          heights.add((par.paragraphIndex > prevPar ? config.paragraphSpacing : 0) +
              (par.text.isEmpty ? config.fontSize * config.lineHeight : painted.height));
          final metrics = painted.computeLineMetrics();
          final lineCount = metrics.length;
          var fromLine = 0;
          var firstChunk = true;
          while (fromLine < lineCount || (lineCount == 0 && firstChunk)) {
            final avail = config.height - used;
            final spacing = firstChunk && (current.isEmpty || par.paragraphIndex > current.last.paragraphIndex)
                ? config.paragraphSpacing : 0.0;
            final nextLineHeight = lineCount == 0 ? config.fontSize * config.lineHeight : metrics[fromLine].height;
            if (avail < nextLineHeight + spacing && current.isNotEmpty) {
              newPage();
              continue;
            }
            if (lineCount == 0 && firstChunk) {
              current.add(TextBlock(par.paragraphIndex, text: '', isFirst: true, isLast: true));
              used += config.fontSize * config.lineHeight + spacing;
              break;
            }
            var endLine = fromLine;
            double acc = 0;
            while (endLine < lineCount) {
              final lh = metrics[endLine].height +
                  (endLine == fromLine ? spacing : 0);
              if (acc + lh > avail && acc > 0) break;
              acc += lh;
              endLine++;
            }
            if (endLine == fromLine) {
              endLine = fromLine + 1;
              acc = metrics[fromLine].height;
            }
            final fromChar = fromLine == 0 ? 0 : _charOffsetAtLine(metrics, painted, fromLine);
            final toChar = endLine >= lineCount ? par.text.length : _charOffsetAtLine(metrics, painted, endLine);
            current.add(TextBlock(par.paragraphIndex,
                text: par.text.substring(fromChar, toChar),
                isFirst: fromLine == 0, isLast: endLine >= lineCount));
            used += acc;
            fromLine = endLine;
            firstChunk = false;
            if (used >= config.height - 0.5) newPage();
            if (ready.isNotEmpty && clock.elapsedMilliseconds >= 8) {
              yield takeBatch();
              await Future<void>.delayed(Duration.zero);
              clock.reset();
            }
          }
        } finally {
          painted.dispose();
        }
      }
      prevPar = item.paragraphIndex;
      sinceYield++;
      if (sinceYield >= chunkSize || clock.elapsedMilliseconds >= 8) {
        yield takeBatch();
        await Future<void>.delayed(Duration.zero);
        clock.reset();
      }
    }
    newPage();
    yield takeBatch(complete: true);
  }

  /// 用于独立高度估算；阅读器走 layoutStream，避免再次测量相同正文。
  static List<double> estimateFlowHeights(
    List<LayoutItem> items,
    PageLayoutConfig config, {
    double imageMarginV = 12,
    double minImageH = 60,
    double maxImageH = double.infinity,
  }) {
    final style = TextStyle(
      fontSize: config.fontSize,
      height: config.lineHeight,
      fontFamily: config.fontFamily.isEmpty ? null : config.fontFamily,
      color: const ui.Color(0xFF000000),
    );
    final heights = <double>[];
    var prevPar = -1;
    for (final item in items) {
      if (item is ImageItem) {
        final h = (config.width / item.block.aspect.clamp(0.2, 5.0)).clamp(minImageH, maxImageH);
        heights.add(h + imageMarginV);
      } else {
        final par = item as TextItem;
        double h;
        if (par.text.isEmpty) {
          h = config.fontSize * config.lineHeight;
        } else {
          final painted = _paint(par.text, style, config.width);
          h = painted.height;
          painted.dispose();
        }
        heights.add((par.paragraphIndex > prevPar ? config.paragraphSpacing : 0) + h);
      }
      prevPar = item.paragraphIndex;
    }
    return heights;
  }

  static List<double> cumulativeOffsets(List<double> heights) {
    final offsets = List<double>.filled(heights.length, 0);
    var acc = 0.0;
    for (var i = 0; i < heights.length; i++) {
      offsets[i] = acc;
      acc += heights[i];
    }
    return offsets;
  }

  static int flowIndexAtOffset(List<double> offsets, double y) {
    if (offsets.isEmpty) return -1;
    if (y < offsets[0]) return 0;
    var lo = 0, hi = offsets.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (offsets[mid] <= y) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  static TextPainter _paint(String text, TextStyle style, double width) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style), textDirection: ui.TextDirection.ltr,
    );
    tp.layout(maxWidth: width);
    return tp;
  }

  static int _charOffsetAtLine(List<ui.LineMetrics> metrics, TextPainter tp, int line) {
    if (line < 0 || line >= metrics.length) return 0;
    final m = metrics[line];
    return tp.getPositionForOffset(ui.Offset(0, m.baseline - m.ascent + m.height * 0.5)).offset;
  }
}
