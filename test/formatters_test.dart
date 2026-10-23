import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:receipt_tracker/core/localization/currencies.dart';
import 'package:receipt_tracker/core/utils/barcode_utils.dart';
import 'package:receipt_tracker/core/utils/formatters.dart';

/// Removes bidi control characters and normalises non-breaking spaces so
/// RTL-formatted numbers can be compared as plain text.
String _plain(String value) => value
    .replaceAll('\u200e', '')
    .replaceAll('\u200f', '')
    .replaceAll('\u00a0', ' ')
    .trim();

void main() {
  setUpAll(() async {
    await initializeDateFormatting('ja');
    await initializeDateFormatting('en');
    await initializeDateFormatting('ar');
  });

  setUp(() {
    Intl.defaultLocale = 'ja';
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
      expect(formatCompactYen(12000), '¥1.2万');
      expect(formatCompactYen(1200000), '¥120万');
      expect(formatCompactYen(980), '¥980');
    });
  });

  group('formatMoney decimals', () {
    test('zero-decimal currencies omit whole fractions only', () {
      expect(formatMoney(1234, currency: 'JPY'), '¥1,234');
      expect(formatMoney(1234.5, currency: 'JPY'), '¥1,234.50');
      expect(formatMoney(1234, currency: 'KWD'), 'د.ك1,234.000');
      expect(formatMoney(1234.567, currency: 'KWD'), 'د.ك1,234.567');
      expect(formatMoney(1234.5, currency: 'USD'), r'$1,234.50');
      expect(formatMoney(1234.5, currency: 'EUR'), '€1,234.50');
      expect(formatMoney(12.5, currency: 'SAR'), 'ر.س12.50');
    });

    test('unknown codes keep the ISO code as the symbol', () {
      expect(formatMoney(99, currency: 'XYZ'), 'XYZ 99.00');
      expect(currencySymbol('XYZ'), 'XYZ');
      expect(currencySymbol('eur'), '€');
    });

    test('explicit Currency object formatting', () {
      final kwd = currencyByCode('KWD')!;
      expect(formatCurrencyAmount(1234.567, currency: kwd), 'د.ك1,234.567');
      expect(
        formatCurrencyAmount(1234.567, currency: kwd, withSymbol: false),
        '1,234.567',
      );
    });

    test('locale-aware grouping and symbol placement', () {
      Intl.defaultLocale = 'en';
      expect(formatMoney(1234.5, currency: 'USD'), r'$1,234.50');
      expect(formatMoney(1234.567, currency: 'KWD'), 'د.ك1,234.567');

      Intl.defaultLocale = 'ar';
      expect(_plain(formatMoney(1234.5, currency: 'USD')), r'1,234.50 $');
      expect(_plain(formatMoney(1234.567, currency: 'KWD')), '1,234.567 د.ك');
      expect(_plain(formatMoney(1234, currency: 'JPY')), '1,234 ¥');
    });
  });

  group('required currency examples', () {
    test('JPY 1080 renders with the yen symbol and no decimals', () {
      expect(formatMoney(1080, currency: 'JPY'), '¥1,080');
    });

    test('USD 12.5 renders two decimals', () {
      expect(formatMoney(12.5, currency: 'USD'), r'$12.50');
    });

    test('KWD 3.250 renders three decimals', () {
      expect(formatMoney(3.25, currency: 'KWD'), 'د.ك3.250');
    });

    test('SOS uses its own symbol, not yen', () {
      final value = formatMoney(1000, currency: 'SOS');
      expect(value, contains('Sh'));
      expect(value, contains('1,000.00'));
      expect(value, isNot(contains('¥')));
    });

    test('Arabic / RTL output keeps the currency symbol and decimals', () {
      Intl.defaultLocale = 'ar';
      final usd = _plain(formatMoney(12.5, currency: 'USD'));
      final kwd = _plain(formatMoney(3.25, currency: 'KWD'));
      expect(usd, contains(r'$'));
      expect(usd, contains('12.50'));
      expect(kwd, contains('3.250'));
      expect(kwd, contains('د.ك'));
    });

    test('XCG is available with the guilder symbol', () {
      expect(currencyByCode('XCG')?.symbol, 'ƒ');
      expect(formatMoney(10, currency: 'XCG'), contains('ƒ'));
    });
  });

  test('parseYenInput strips symbols and separators', () {
    expect(parseYenInput('¥1,234'), 1234);
    expect(parseYenInput('１２３４'), 1234);
    expect(parseYenInput(''), isNull);
  });

  test('parseAmountInput accepts decimals and currency symbols', () {
    expect(parseAmountInput(r'$1,234.50'), 1234.5);
    expect(parseAmountInput('1.234,56'), 1234.56);
    expect(parseAmountInput('12,50'), 12.5);
    expect(parseAmountInput('¥1,234'), 1234);
    expect(parseAmountInput(''), isNull);
  });

  group('date labels', () {
    test('Japanese date labels', () {
      expect(formatDateJa(DateTime(2026, 10, 19)), '2026年10月19日(月)');
      expect(formatMonthJa(DateTime(2026, 10, 1)), '2026年10月');
      expect(
        formatRangeJa(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        '2026/10/1(木) 〜 2026/10/31(土)',
      );
    });

    test('English date labels', () {
      Intl.defaultLocale = 'en';
      expect(formatDateJa(DateTime(2026, 10, 19)), 'Mon, Oct 19, 2026');
      expect(formatMonthJa(DateTime(2026, 10, 1)), 'October 2026');
      expect(
        formatRangeJa(DateTime(2026, 10, 1), DateTime(2026, 10, 31)),
        '10/1/26 (Thu) – 10/31/26 (Sat)',
      );
    });

    test('Arabic date labels', () {
      Intl.defaultLocale = 'ar';
      expect(formatDateJa(DateTime(2026, 10, 19)), 'الاثنين، 19 أكتوبر 2026');
      expect(formatMonthJa(DateTime(2026, 10, 1)), 'أكتوبر 2026');
    });
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
