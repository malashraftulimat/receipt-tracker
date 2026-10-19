import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/parser/receipt_parser.dart';
import 'package:receipt_tracker/domain/parser/receipt_text_merger.dart';

void main() {
  const merger = ReceiptTextMerger();

  test('removes the overlapping lines at a seam', () {
    const top = '''
イオンスーパー
2026年10月19日
牛乳 ¥198
パン ¥158
卵 ¥258''';
    const bottom = '''
パン ¥158
卵 ¥258
洗剤 ¥398
合計 ¥1,012''';

    final merged = merger.merge(<String>[top, bottom]);
    final lines = merged.split('\n');

    expect(lines.where((l) => l.startsWith('パン')).length, 1);
    expect(lines.where((l) => l.startsWith('卵')).length, 1);
    expect(merged.contains('イオンスーパー'), isTrue);
    expect(merged.contains('合計 ¥1,012'), isTrue);
  });

  test('handles full-width and spacing differences when aligning', () {
    final merged = merger.merge(<String>[
      '店舗\n合計 １，２３４',
      '合計  1,234\nお預り 2,000',
    ]);
    expect(merged.split('\n').where((l) => l.contains('合計')).length, 1);
    expect(merged.contains('お預り 2,000'), isTrue);
  });

  test('merges three chunks into one document', () {
    final merged = merger.merge(<String>[
      'A店\nりんご 100',
      'りんご 100\nみかん 200',
      'みかん 200\n合計 300',
    ]);
    expect(
      merged,
      'A店\nりんご 100\nみかん 200\n合計 300',
    );
  });

  test('collapses duplicated OCR lines inside a chunk', () {
    final merged = merger.merge(<String>['A店\nA店\n合計 500']);
    expect(merged, 'A店\n合計 500');
  });

  test('merged text parses as a normal receipt', () {
    const parser = ReceiptParser();
    final merged = merger.merge(<String>[
      'スーパーマルエツ\n2026年10月19日\n牛乳 ¥198 ※\nパン ¥158 ※',
      'パン ¥158 ※\n8%対象 ¥356\n合計 ¥356',
    ]);
    final parsed = parser.parse(merged);
    expect(parsed.totalAmount, 356);
    expect(parsed.tax8ItemsTotal, 356);
    expect(parsed.purchasedAt?.day, 19);
  });
}
