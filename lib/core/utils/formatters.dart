import 'package:intl/intl.dart';

/// Currencies that are conventionally printed without a decimal part.
const Set<String> _zeroDecimalCurrencies = <String>{
  'JPY',
  'KRW',
  'VND',
  'CLP',
  'ISK',
  'HUF',
};

const Map<String, String> _currencySymbols = <String, String>{
  'JPY': '¥',
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'CNY': '¥',
  'KRW': '₩',
  'INR': '₹',
  'SAR': '﷼',
  'AED': 'د.إ',
  'EGP': 'E£',
  'TRY': '₺',
  'THB': '฿',
  'VND': '₫',
  'RUB': '₽',
  'AUD': r'A$',
  'CAD': r'C$',
  'CHF': 'CHF',
  'TWD': r'NT$',
  'HKD': r'HK$',
  'SGD': r'S$',
  'BRL': r'R$',
  'MXN': r'MX$',
  'IDR': 'Rp',
  'MYR': 'RM',
  'PHP': '₱',
  'NZD': r'NZ$',
};

/// Symbol (or the ISO code itself when no symbol is known) for [currency].
String currencySymbol(String currency) {
  final code = currency.trim().toUpperCase();
  return _currencySymbols[code] ?? code;
}

String _groupDigits(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats [amount] in [currency] (ISO 4217 code) with grouping and decimals.
///
/// Zero-decimal currencies (JPY, KRW, ...) omit the fraction when the amount
/// is whole, but still show it when the receipt carries a decimal value.
String formatMoney(
  num amount, {
  String currency = 'JPY',
  bool withSymbol = true,
}) {
  final code = currency.trim().toUpperCase();
  final value = amount.toDouble();
  final hasFraction = (value - value.roundToDouble()).abs() > 1e-9;
  final fractionDigits =
      hasFraction ? 2 : (_zeroDecimalCurrencies.contains(code) ? 0 : 2);

  final fixed = value.abs().toStringAsFixed(fractionDigits);
  final parts = fixed.split('.');
  final grouped = _groupDigits(parts[0]);
  final number = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  final sign = value < 0 ? '-' : '';
  if (!withSymbol) return '$sign$number';
  final symbol = currencySymbol(code);
  // Unknown currencies fall back to the ISO code, separated by a space.
  final separator = symbol == code ? ' ' : '';
  return '$sign$symbol$separator$number';
}

/// `¥1,234` (JPY is displayed without decimals unless the value has a
/// fractional part).
String formatYen(num amount, {bool withSymbol = true}) =>
    formatMoney(amount, currency: 'JPY', withSymbol: withSymbol);

/// `1.2万円` style compact label for charts.
String formatCompactYen(num amount) {
  final value = amount.round();
  if (value.abs() >= 10000) {
    final language = _dateLanguage;
    if (language == 'ja') {
      final man = value / 10000;
      final text = man.abs() >= 100
          ? man.round().toString()
          : man.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
      return '$text万円';
    }
    if (value.abs() >= 1000000) {
      return '¥${(value / 1000000).toStringAsFixed(1)}M';
    }
    return '¥${(value / 1000).toStringAsFixed(0)}k';
  }
  return formatYen(value);
}

/// Editable amount text without the currency symbol. Decimals are preserved
/// only when they are non-zero so whole amounts stay easy to read.
String formatAmountDigits(num amount) {
  final value = amount.toDouble();
  final whole = value == value.roundToDouble();
  final fixed =
      whole ? value.abs().round().toString() : value.abs().toStringAsFixed(2);
  final parts = fixed.split('.');
  final grouped = _groupDigits(parts[0]);
  final number = parts.length > 1 ? '$grouped.${parts[1]}' : grouped;
  final sign = value < 0 ? '-' : '';
  return '$sign$number';
}

/// Strips full-width characters, currency symbols and separators from [input]
/// and normalises either `1,234.56` or `1.234,56` into a decimal string.
String? _normalizeNumberInput(String input) {
  final normalized = StringBuffer();
  for (final rune in input.runes) {
    // Full-width digits / punctuation -> ASCII so IME input works too.
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      normalized.writeCharCode(rune - 0xFEE0);
    } else if (rune == 0xFF0E) {
      normalized.write('.');
    } else if (rune == 0xFF0C) {
      normalized.write(',');
    } else {
      normalized.writeCharCode(rune);
    }
  }

  var text = normalized.toString().replaceAll(RegExp(r'[^0-9.,\-]'), '').trim();
  if (text.isEmpty || text == '-' || text == '.' || text == ',') return null;

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      // European style: 1.234,56 -> 1234.56
      text = text.replaceAll('.', '').replaceAll(',', '.');
    } else {
      // US style: 1,234.56 -> 1234.56
      text = text.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    final digitsAfter = text.length - lastComma - 1;
    final commaCount = RegExp(',').allMatches(text).length;
    if (commaCount == 1 && digitsAfter > 0 && digitsAfter <= 2) {
      text = text.replaceAll(',', '.');
    } else {
      text = text.replaceAll(',', '');
    }
  }
  return text;
}

/// Parses user input such as `¥1,234`, `12.50` or `１２３４` into a decimal
/// amount. Currency-agnostic and decimal-aware.
double? parseAmountInput(String input) {
  final normalized = _normalizeNumberInput(input);
  if (normalized == null) return null;
  return double.tryParse(normalized);
}

/// Parses user input such as `¥1,234` or `１２３４` into an integer value.
int? parseYenInput(String input) {
  final normalized = _normalizeNumberInput(input);
  if (normalized == null) return null;
  final value = double.tryParse(normalized);
  if (value == null) return null;
  return value.round();
}

// ---------------------------------------------------------------------------
// Dates — symbol data for ja / en / ar is loaded in main() via
// initializeDateFormatting(). The active language comes from Intl.defaultLocale,
// which is updated by the language provider.
// ---------------------------------------------------------------------------

String get _dateLanguage => Intl.defaultLocale ?? 'ja';

bool get _isJapanese => _dateLanguage.startsWith('ja');
bool get _isArabic => _dateLanguage.startsWith('ar');

String formatDateJa(DateTime date) {
  final pattern = _isJapanese
      ? 'yyyy年M月d日(E)'
      : (_isArabic ? 'EEEE، d MMMM y' : 'EEE, MMM d, y');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatDateShortJa(DateTime date) {
  final pattern = _isJapanese
      ? 'yyyy/M/d(E)'
      : (_isArabic ? 'd/M/y (EEE)' : 'M/d/yy (EEE)');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatMonthJa(DateTime date) {
  final pattern = _isJapanese ? 'yyyy年M月' : (_isArabic ? 'MMMM y' : 'MMMM y');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatDayJa(DateTime date) {
  final pattern =
      _isJapanese ? 'M月d日(E)' : (_isArabic ? 'EEEE، d MMMM' : 'EEE, MMM d');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatTimeJa(DateTime date) => DateFormat('HH:mm').format(date);

/// Localized weekday name for [weekday] (1 = Monday … 7 = Sunday).
///
/// 2026-01-04 is a Sunday, so `DateTime(2026, 1, 4 + weekday)` lands on the
/// requested weekday without DST-sensitive duration math.
String formatWeekdayJa(int weekday, {bool short = false}) {
  final date = DateTime(2026, 1, 4 + weekday.clamp(1, 7));
  return DateFormat(short ? 'E' : 'EEEE', _dateLanguage).format(date);
}

String formatDateTimeJa(DateTime date) =>
    '${formatDateJa(date)} ${formatTimeJa(date)}';

String formatYearJa(DateTime date) =>
    DateFormat(_isJapanese ? 'yyyy年' : 'y', _dateLanguage).format(date);

String formatMonthShortJa(DateTime date) =>
    DateFormat(_isJapanese ? 'M月' : 'MMM', _dateLanguage).format(date);

String formatRangeJa(DateTime start, DateTime endInclusive) {
  final sameDay = start.year == endInclusive.year &&
      start.month == endInclusive.month &&
      start.day == endInclusive.day;
  if (sameDay) return formatDateJa(start);
  final separator = _isJapanese ? ' 〜 ' : ' – ';
  return '${formatDateShortJa(start)}$separator${formatDateShortJa(endInclusive)}';
}
