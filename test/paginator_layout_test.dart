import 'package:flutter_test/flutter_test.dart';
import 'package:shengtushu/reader/paginator.dart';

void main() {
  const config = PageLayoutConfig(width: 360, height: 580,
      fontSize: 17, lineHeight: 1.85, paragraphSpacing: 16);

  test('统一排版：每项只产出一次高度，最终页与单批分页一致', () async {
    final items = <LayoutItem>[
      for (var i = 0; i < 160; i++) ...[
        TextItem(i, i % 9 == 0 ? '' : List.filled(3, '　　第$i段正文，长河落日，山间微风。').join()),
        if (i % 7 == 0) ImageItem(ImageBlock(i, illustrationId: i, status: 'done', aspect: 1.7)),
      ],
    ];
    final pages = <ReaderPage>[];
    final heights = <double>[];
    var completed = 0;
    var earlyPages = false;
    await for (final batch in Paginator.layoutStream(items: items, config: config, chunkSize: 2)) {
      pages.addAll(batch.pages);
      heights.addAll(batch.flowHeights);
      if (batch.isComplete) completed++;
      if (pages.isNotEmpty && heights.length < items.length) earlyPages = true;
    }
    expect(completed, 1);
    expect(earlyPages, isTrue);
    expect(heights, orderedEquals(Paginator.estimateFlowHeights(items, config,
        maxImageH: config.height - 12)));
    final comparison = <ReaderPage>[];
    await for (final batch in Paginator.paginateStream(items: items, config: config, chunkSize: 100000)) {
      comparison.addAll(batch);
    }
    expect(pages.length, comparison.length);
    for (var i = 0; i < pages.length; i++) {
      expect(pages[i].blocks.length, comparison[i].blocks.length);
    }
    final allText = pages.expand((p) => p.blocks).whereType<TextBlock>().map((b) => b.text).join();
    expect(allText, items.whereType<TextItem>().map((t) => t.text).join());
  });

  test('单个超长段落可跨批产页，无重复正文和重复流高度', () async {
    final text = List.filled(4000, '山间微风，继续阅读。').join();
    final pages = <ReaderPage>[];
    final heights = <double>[];
    var batches = 0;
    await for (final batch in Paginator.layoutStream(items: [TextItem(0, text)], config: config)) {
      pages.addAll(batch.pages);
      heights.addAll(batch.flowHeights);
      batches++;
    }
    expect(batches, greaterThan(1));
    expect(heights, hasLength(1));
    expect(pages.expand((p) => p.blocks).whereType<TextBlock>().map((b) => b.text).join(), text);
  });
}
