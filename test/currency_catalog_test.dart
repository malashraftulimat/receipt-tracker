import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/core/localization/currencies.dart';

/// Codes the app must always offer (plus XCG, added below).
const List<String> requiredCurrencyCodes = <String>[
  'AED', 'AFN', 'ALL', 'AMD', 'ANG', 'AOA', 'ARS', 'AUD', 'AWG', 'AZN',
  'BAM', 'BBD', 'BDT', 'BGN', 'BHD', 'BIF', 'BMD', 'BND', 'BOB', 'BRL',
  'BSD', 'BTN', 'BWP', 'BYN', 'BZD', 'CAD', 'CDF', 'CHF', 'CLP', 'CNY',
  'COP', 'CRC', 'CUP', 'CVE', 'CZK', 'DJF', 'DKK', 'DOP', 'DZD', 'EGP',
  'ERN', 'ETB', 'EUR', 'FJD', 'FKP', 'GBP', 'GEL', 'GHS', 'GIP', 'GMD',
  'GNF', 'GTQ', 'GYD', 'HKD', 'HNL', 'HTG', 'HUF', 'IDR', 'ILS', 'INR',
  'IQD', 'IRR', 'ISK', 'JMD', 'JOD', 'JPY', 'KES', 'KGS', 'KHR', 'KMF',
  'KPW', 'KRW', 'KWD', 'KYD', 'KZT', 'LAK', 'LBP', 'LKR', 'LRD', 'LSL',
  'LYD', 'MAD', 'MDL', 'MGA', 'MKD', 'MMK', 'MNT', 'MOP', 'MRU', 'MUR',
  'MVR', 'MWK', 'MXN', 'MYR', 'MZN', 'NAD', 'NGN', 'NIO', 'NOK', 'NPR',
  'NZD', 'OMR', 'PAB', 'PEN', 'PGK', 'PHP', 'PKR', 'PLN', 'PYG', 'QAR',
  'RON', 'RSD', 'RUB', 'RWF', 'SAR', 'SBD', 'SCR', 'SDG', 'SEK', 'SGD',
  'SHP', 'SLE', 'SOS', 'SRD', 'SSP', 'STN', 'SVC', 'SYP', 'SZL', 'THB',
  'TJS', 'TMT', 'TND', 'TOP', 'TRY', 'TTD', 'TWD', 'TZS', 'UAH', 'UGX',
  'USD', 'UYU', 'UZS', 'VES', 'VND', 'VUV', 'WST', 'XAF', 'XCD', 'XOF',
  'XPF', 'YER', 'ZAR', 'ZMW', 'ZWG',
];

const Set<String> zeroDecimalCodes = <String>{
  'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG', 'RWF',
  'UGX', 'UYI', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
};

const Set<String> threeDecimalCodes = <String>{
  'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND',
};

void main() {
  final byCode = <String, Currency>{
    for (final currency in kCurrencies) currency.code: currency,
  };

  test('every required ISO 4217 code is present', () {
    for (final code in <String>[...requiredCurrencyCodes, 'XCG']) {
      expect(byCode.containsKey(code), isTrue, reason: 'missing $code');
    }
  });

  test('the catalog contains no duplicate codes', () {
    final codes = kCurrencies.map((currency) => currency.code).toList();
    expect(codes.toSet().length, codes.length);
  });

  test('every entry has a symbol and real ja / en / ar names', () {
    final arabic = RegExp(r'[\u0600-\u06ff]');
    final japanese = RegExp(r'[\u3000-\u30ff\u3400-\u9fff]');
    for (final currency in kCurrencies) {
      expect(currency.symbol.trim(), isNotEmpty,
          reason: '${currency.code} symbol');
      expect(currency.nameJa.trim(), isNotEmpty,
          reason: '${currency.code} nameJa');
      expect(currency.nameEn.trim(), isNotEmpty,
          reason: '${currency.code} nameEn');
      expect(currency.nameAr.trim(), isNotEmpty,
          reason: '${currency.code} nameAr');
      expect(japanese.hasMatch(currency.nameJa), isTrue,
          reason: '${currency.code} nameJa must be Japanese');
      expect(arabic.hasMatch(currency.nameAr), isTrue,
          reason: '${currency.code} nameAr must be Arabic');
    }
  });

  test('decimal digits follow the required rules', () {
    for (final currency in kCurrencies) {
      final expected = zeroDecimalCodes.contains(currency.code)
          ? 0
          : threeDecimalCodes.contains(currency.code)
              ? 3
              : 2;
      expect(currency.decimalDigits, expected,
          reason: '${currency.code} decimal digits');
    }
  });

  test('common currencies and helpers resolve correctly', () {
    expect(kCommonCurrencyCodes.take(3), <String>['JPY', 'USD', 'EUR']);
    expect(kCommonCurrencyCodes, contains('SOS'));
    expect(currencyByCode('jpy')?.symbol, '¥');
    expect(currencyOrDefault('bogus').code, 'JPY');
    expect(currencyCodeForSymbol('¥'), 'JPY');
    expect(currencyCodeForSymbol('د.ك'), 'KWD');
    expect(commonCurrencies(), isNotEmpty);
  });
}
