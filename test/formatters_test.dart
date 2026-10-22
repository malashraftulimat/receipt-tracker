import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:receipt_tracker/core/utils/barcode_utils.dart';
import 'package:receipt_tracker/core/utils/formatters.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
  });

  group('formatYen', () {
    test('groups thousands', () {
      expect(formatYen(0), '¥0');
      expect(formatYen(980), '¥980');
      expect(formatYen(1234), '¥1,234');
      expect(formatYen(1234567), '¥1,234,567');
    });

    test('handles negatives and symbol toggle', () {
      expect(formatYen(-1500), '-¥1,500');
      expect(formatYen(1500, withSymbol: false), '1,500');
    });

    test('compact notation', () {
      expect(formatCompactYen(12000), '1.2万円');
      expect(formatCompactYen(1200000), '120万円');
      expect(formatCompactYen(980), '¥980');
    });
  });

  test('parseYenInput strips symbols and separators', () {
    expect(parseYenInput('¥1,234'), 1234);
    expect(parseYenInput('１２３４'), 1234);
    expect(parseYenInput(''), isNull);
  });

  test('currency-aware decimal formatting', () {
    expect(formatMoney(1234, currency: 'JPY'), '¥1,234');
    expect(formatMoney(1234.5, currency: 'USD'), r'$1,234.50');
    expect(formatMoney(12.5, currency: 'SAR'), '﷼12.50');
    expect(formatMoney(99, currency: 'XYZ'), 'XYZ 99.00');
    expect(currencySymbol('eur'), '€');
  });

  test('parseAmountInput accepts decimals and currency symbols', () {
    expect(parseAmountInput(r'$1,234.50'), 1234.5);
    expect(parseAmountInput('1.234,56'), 1234.56);
    expect(parseAmountInput('12,50'), 12.5);
    expect(parseAmountInput('¥1,234'), 1234);
    expect(parseAmountInput(''), isNull);
  });

  test('Japanese date labels', () {
    expect(formatDateJa(DateTime(2026, 10, 19)), '2026年10月19日(月)');
    expect(formatMonthJa(DateTime(2026, 10, 1)), '2026年10月');
  });

  group('barcode utils', () {
    test('validates JAN-13 check digits', () {
      expect(BarcodeUtils.isValidEan13('4901234567894'), isTrue);
      expect(BarcodeUtils.isValidEan13('4901234567890'), isFalse);
      expect(BarcodeUtils.isValidEan13('123'), isFalse);
    });

    test('formats 13-digit codes', () {
      expect(BarcodeUtils.format('4901234567894'), '490 12345 67894');
    });
  });
}
