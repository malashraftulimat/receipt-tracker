import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/parser/receipt_parser.dart';

void main() {
  const parser = ReceiptParser();

  group('date detection', () {
    test('handles Japanese era-free format', () {
      final result = parser.parse('スーパーABC\n2026年10月19日 14:32\n合計 ¥1,080');
      expect(result.purchasedAt, DateTime(2026, 10, 19, 14, 32));
    });

    test('handles slash format', () {
      final result = parser.parse('2026/10/19\nお会計 500円');
      expect(result.purchasedAt, DateTime(2026, 10, 19));
    });

    test('handles Reiwa era', () {
      final result = parser.parse('令和8年10月19日\n合計 1,000円');
      expect(result.purchasedAt?.year, 2026);
      expect(result.purchasedAt?.month, 10);
      expect(result.purchasedAt?.day, 19);
    });

    test('handles compact R notation', () {
      final result = parser.parse('R8.10.19 12:05');
      expect(result.purchasedAt, DateTime(2026, 10, 19, 12, 5));
    });
  });

  group('total detection', () {
    test('prefers 税込合計 over line items', () {
      final text = '''
セブン-イレブン 渋谷店
2026年10月19日
おにぎり ¥150
お茶 ¥120
小計 ¥270
消費税(8%) ¥21
合計 ¥291
お預り ¥1,000
お釣 ¥709
''';
      final result = parser.parse(text);
      expect(result.merchant, 'セブン-イレブン 渋谷店');
      expect(result.totalAmount, 291);
      expect(result.subtotalAmount, 270);
      expect(result.tax8Amount, 21);
      expect(result.tax8Base, 270);
    });

    test('handles 合計金額 keyword', () {
      final result = parser.parse('イオン\n合計金額 3,045円\n（内消費税 225円）');
      expect(result.totalAmount, 3045);
    });

    test('ignores change and payment lines in fallback', () {
      final result = parser.parse('店舗\n商品 1,200円\nお預り 5,000円\nお釣 3,800円');
      expect(result.totalAmount, 1200);
    });

    test('full-width digits are normalised', () {
      final result = parser.parse('テスト店\n２０２６年１０月１９日\n合計 ￥１，２３４');
      expect(result.totalAmount, 1234);
      expect(result.purchasedAt?.year, 2026);
    });
  });

  group('tax detection', () {
    test('detects 8% and 10% simultaneously', () {
      final text = '''
スーパーマルエツ
2026年10月19日 19:41
（8%対象 ¥1,080） 消費税 ¥80
（10%対象 ¥550） 消費税 ¥50
合計 ¥1,630
''';
      final result = parser.parse(text);
      expect(result.totalAmount, 1630);
      expect(result.tax8Amount, 80);
      expect(result.tax10Amount, 50);
      expect(result.tax8Base, 1080);
      expect(result.tax10Base, 550);
    });

    test('derives tax from tax-inclusive base', () {
      final result = parser.parse('店\n8%対象 1,080\n合計 1,080');
      expect(result.tax8Amount, 80);
      expect(result.tax8Base, 1080);
    });

    test('rejects tax larger than the total', () {
      final result = parser.parse('店\n合計 500\n消費税 5,000');
      expect(result.tax10Amount, isNull);
      expect(result.warnings, isNotEmpty);
    });
  });

  group('barcode / reference', () {
    test('uses the scanned barcode when provided', () {
      final result = parser.parse(
        '店舗\n合計 100',
        scannedBarcode: '4901234567894',
      );
      expect(result.barcodeId, '4901234567894');
    });

    test('reads a receipt number from OCR text', () {
      final result = parser.parse('店舗\nレシートNo: 1234567890\n合計 980');
      expect(result.barcodeId, '1234567890');
    });

    test('reads qualified invoice registration numbers', () {
      final result = parser.parse('登録番号 T1234567890123\n合計 1,100');
      expect(result.barcodeId, 'T1234567890123');
    });
  });

  group('merchant detection', () {
    test('skips receipt boilerplate', () {
      final result = parser.parse('''
領収書
サイゼリヤ 新宿店
2026年10月19日
合計 ¥1,090
''');
      expect(result.merchant, 'サイゼリヤ 新宿店');
    });

    test('does not pick a date line as the merchant', () {
      final result = parser.parse('2026年10月19日\nスターバックス\n合計 540');
      expect(result.merchant, 'スターバックス');
    });
  });

  test('returns warnings when nothing can be parsed', () {
    final result = parser.parse('読み取り失敗');
    expect(result.totalAmount, isNull);
    expect(result.warnings, isNotEmpty);
  });
}
