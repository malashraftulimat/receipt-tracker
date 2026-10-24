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
      const text = '''
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

    test('detects currency and decimal amounts in English receipts', () {
      final result = parser.parse('Corner Cafe\nCoffee \$3.50\nTotal \$12.99');
      expect(result.currency, 'USD');
      expect(result.totalAmount, 12.99);
      expect(result.items.single.name, 'Coffee');
      expect(result.items.single.totalPrice, 3.5);
    });
  });

  group('tax detection', () {
    test('detects 8% and 10% simultaneously', () {
      const text = '''
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
      expect(result.receiptNumber, '4901234567894');
    });

    test('reads a receipt number from OCR text', () {
      final result = parser.parse('店舗\nレシートNo: 1234567890\n合計 980');
      expect(result.receiptNumber, '1234567890');
    });

    test('reads qualified invoice registration numbers separately', () {
      final result = parser.parse('登録番号 T1234567890123\n合計 1,100');
      expect(result.registrationNumber, 'T1234567890123');
      expect(result.receiptNumber, isNull);
      expect(result.barcodeId, isNull);
    });

    test('keeps the receipt number and registration number apart', () {
      final result = parser.parse('''
店舗
レシートNo: 0100000001
登録番号 T1234567890123
合計 980
''');
      expect(result.receiptNumber, '0100000001');
      expect(result.registrationNumber, 'T1234567890123');
    });

    test('ignores coupon numbers printed under a coupon block', () {
      final result = parser.parse('''
店舗
クーポン
No.1234567890123
利用期限 2026/11/30
レシートNo: 00042
合計 980
''');
      expect(result.receiptNumber, '00042');
      expect(result.registrationNumber, isNull);
    });

    test('a scanned T-number is a registration number, not a receipt number', () {
      final result = parser.parse(
        '店舗\n合計 980',
        scannedBarcode: 'T8012402001708',
      );
      expect(result.receiptNumber, isNull);
      expect(result.registrationNumber, 'T8012402001708');
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

  group('Japanese financial extras', () {
    test('detects the payment deadline on a utility bill', () {
      final result = parser.parse('''
東京電力パワーグリッド
2026年10月5日
ご請求金額 6,540円
支払期限 2026年10月31日
''');
      expect(result.totalAmount, 6540);
      expect(result.dueDate, DateTime(2026, 10, 31));
    });

    test('accepts a deadline without a year', () {
      final result = parser.parse(
        '払込票\nご請求金額 3,200円\n支払期限 10月31日',
      );
      expect(result.dueDate?.month, 10);
      expect(result.dueDate?.day, 31);
    });

    test('detects loyalty points and their brand', () {
      final result = parser.parse(
        'イオン\n合計 1,200円\ndポイント 今回 15ポイント',
      );
      expect(result.pointBrand, 'dポイント');
      expect(result.pointAmount, 15);
    });

    test('detects generic earned points', () {
      final result = parser.parse(
        '店舗\n合計 980円\n獲得ポイント 120',
      );
      expect(result.pointAmount, 120);
    });

    test('sums reduced-rate (※) items separately', () {
      final result = parser.parse('''
スーパー
牛乳 ¥198 ※
パン ¥158 ※
洗剤 (10%) ¥398
合計 ¥754
''');
      expect(result.tax8ItemsTotal, 356);
      expect(result.tax10ItemsTotal, 398);
    });
  });

  itemTests();

  group('amount consistency', () {
    test('accepts items that match the tax-excluded subtotal', () {
      final result = parser.parse('''
スーパー
2026年10月19日
商品A 170
商品B 41
小計 211
消費税 16
合計 227
''');
      expect(result.items.length, 2);
      expect(
        result.items.fold<double>(0, (sum, item) => sum + item.totalPrice),
        211,
      );
      expect(result.subtotalAmount, 211);
      expect(result.tax10Amount, 16);
      expect(result.totalAmount, 227);
      expect(
        result.warnings.where((w) => w.contains('明細の合計')),
        isEmpty,
      );
    });

    test('warns when items match neither the subtotal nor the total', () {
      final result = parser.parse('''
スーパー
2026年10月19日
商品A 170
商品B 20
小計 211
消費税 16
合計 227
''');
      expect(
        result.warnings.where((w) => w.contains('明細の合計')),
        isNotEmpty,
      );
    });
  });

  test('returns warnings when nothing can be parsed', () {
    final result = parser.parse('読み取り失敗');
    expect(result.totalAmount, isNull);
    expect(result.warnings, isNotEmpty);
  });
}

// ---------------------------------------------------------------------------
// Itemized receipts
// ---------------------------------------------------------------------------

void itemTests() {
  const parser = ReceiptParser();

  group('Japanese 領収書 fixture', () {
    const receipt = '''
ソニックストア株式会社東京店
會計日 202552088268 (A)
会計日 2025年08月26日
伝票 No.0100000001
登録番号 T5010001238914
(8%対象税 (税抜)) ¥1,000
(消費税等 8%) ¥80
支払 ¥1,080
〒150-0002 東京都渋谷区南5条東1丁目3-5-1
TEL 03-1234-5678
''';

    test('reads store, date, invoice, totals and tax without item noise', () {
      final parsed = parser.parse(receipt);
      expect(parsed.merchant, 'ソニックストア株式会社東京店');
      expect(parsed.purchasedAt, DateTime(2025, 8, 26));
      expect(parsed.registrationNumber, 'T5010001238914');
      expect(parsed.receiptNumber, '0100000001');
      expect(parsed.totalAmount, 1080);
      expect(parsed.subtotalAmount, 1000);
      expect(parsed.tax8Amount, 80);
      expect(parsed.tax8Base, 1000);
      expect(parsed.items, isEmpty);
    });

    test('normalises simplified Chinese tax labels from OCR', () {
      final parsed = parser.parse('''
店
会計日 2025年08月26日
(8%对象税 (税抜)) ¥1,000
(消费税等 8%) ¥80
支払 ¥1,080
''');
      expect(parsed.tax8Base, 1000);
      expect(parsed.tax8Amount, 80);
      expect(parsed.totalAmount, 1080);
      expect(parsed.items, isEmpty);
    });
  });

  group('line items', () {
    test('extracts item name, quantity and tax markers', () {
      final parsed = parser.parse('''
スーパーマルエツ
2026年10月19日
牛乳 198 ※
パン 2個 396 ※
洗剤 398
合計 992
''');

      expect(parsed.items.length, 3);
      expect(parsed.items[0].name, '牛乳');
      expect(parsed.items[0].totalPrice, 198);
      expect(parsed.items[0].taxRate, 8);
      expect(parsed.items[0].quantity, 1);

      expect(parsed.items[1].name, 'パン');
      expect(parsed.items[1].quantity, 2);
      expect(parsed.items[1].totalPrice, 396);
      expect(parsed.items[1].unitPrice, 198);

      expect(parsed.items[2].name, '洗剤');
      expect(parsed.items[2].totalPrice, 398);
      expect(parsed.items[2].taxRate, isNull);
    });

    test('parses the 2 x 198 format', () {
      final parsed = parser.parse('店\nお茶 2×198\n合計 396');
      expect(parsed.items.single.name, 'お茶');
      expect(parsed.items.single.quantity, 2);
      expect(parsed.items.single.unitPrice, 198);
      expect(parsed.items.single.totalPrice, 396);
    });

    test('ignores totals, tax summaries and payment lines', () {
      final parsed = parser.parse('''
店
商品A 500
消費税(10%) 50
合計 550
お預り 1000
お釣 450
''');
      expect(parsed.items.length, 1);
      expect(parsed.items.single.name, '商品A');
    });
  });
}
