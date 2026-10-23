import 'package:intl/intl.dart';

import '../localization/currencies.dart';
import '../localization/date_patterns.dart';

/// Symbol (or the ISO code itself when no symbol is known) for [currency].
String currencySymbol(String currency) {
  final code = currency.trim().toUpperCase();
  return currencyByCode(code)?.symbol ?? code;
}

/// Resolves a stored code for display: missing/empty means the app default
/// (JPY), while an unknown code keeps its own ISO code as the symbol so the
/// amount is never silently re-labelled as yen.
Currency _displayCurrency(String? currency) {
  final code = currency?.trim().toUpperCase() ?? '';
  final known = currencyByCode(code);
  if (known != null) return known;
  if (code.isEmpty) return kFallbackCurrency;
  return Currency(
    code: code,
    symbol: code,
    decimalDigits: 2,
    nameJa: code,
    nameEn: code,
    nameAr: code,
  );
}

String _groupDigits(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Formats [amount] in [currency] (ISO 4217 code) with locale-aware grouping,
/// the currency's decimal digits and its localized symbol.
///
/// Zero-decimal currencies (JPY, KRW, ...) omit the fraction when the amount
/// is whole, but still show it when the receipt carries a decimal value.
String formatMoney(
  num amount, {
  String currency = kFallbackCurrencyCode,
  bool withSymbol = true,
}) {
  final c = _displayCurrency(currency);
  final value = amount.toDouble();
  final hasFraction = (value - value.roundToDouble()).abs() > 1e-9;
  final digits = hasFraction && c.decimalDigits == 0 ? 2 : c.decimalDigits;
  final locale = _dateLanguage;
  final number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(value);
  if (!withSymbol) return number;
  // Unknown codes fall back to the ISO code as the symbol, separated by a
  // space so `XYZ 99.00` stays unambiguous.
  final unknown = c.symbol == c.code;
  if (unknown) return '${c.code} $number';
  return NumberFormat.currency(
    locale: locale,
    symbol: c.symbol,
    decimalDigits: digits,
  ).format(value);
}

/// Formats [amount] using an explicit [Currency] object.
String formatCurrencyAmount(
  num amount, {
  required Currency currency,
  bool withSymbol = true,
}) =>
    formatMoney(amount, currency: currency.code, withSymbol: withSymbol);

/// Formats a JPY amount (no decimals unless the value is fractional).
String formatYen(num amount, {bool withSymbol = true}) =>
    formatMoney(amount, currency: kFallbackCurrencyCode, withSymbol: withSymbol);

/// Compact label for charts, e.g. 1.2万 / 1.2M.
String formatCompactMoney(
  num amount, {
  String currency = kFallbackCurrencyCode,
}) {
  final c = _displayCurrency(currency);
  final format = NumberFormat.compactCurrency(
    locale: _dateLanguage,
    symbol: c.symbol,
    decimalDigits: c.decimalDigits,
  );
  return format.format(amount);
}

/// Backwards-compatible JPY compact label for charts.
String formatCompactYen(num amount) => formatCompactMoney(amount);

/// Editable amount text without the currency symbol. Decimals are preserved
/// only when they are non-zero so whole amounts stay easy to read.
///
/// Editable text always uses Western digits and `,` grouping so that the
/// parser accepts it on every platform, independent of the display locale.
String formatAmountDigits(num amount, {int decimalDigits = 2}) {
  final value = amount.toDouble();
  final whole = value == value.roundToDouble();
  final fixed = whole
      ? value.abs().round().toString()
      : value.abs().toStringAsFixed(decimalDigits);
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

/// Parses user input such as `1,234`, `12.50` or full-width digits into a
/// decimal amount. Currency-agnostic and decimal-aware.
double? parseAmountInput(String input) {
  final normalized = _normalizeNumberInput(input);
  if (normalized == null) return null;
  return double.tryParse(normalized);
}

/// Parses user input such as `1,234` or full-width digits into an integer.
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
// which is updated by the language provider. Patterns live in date_patterns.dart.
// ---------------------------------------------------------------------------

String get _dateLanguage => Intl.defaultLocale ?? 'ja';

String get _languageCode {
  final locale = _dateLanguage.toLowerCase();
  if (locale.startsWith('ar')) return 'ar';
  if (locale.startsWith('en')) return 'en';
  return 'ja';
}

String _pattern(String key) =>
    kDatePatterns[key]?[_languageCode] ?? kDatePatterns[key]!['ja']!;

String formatDateJa(DateTime date) =>
    DateFormat(_pattern('full'), _dateLanguage).format(date);

String formatDateShortJa(DateTime date) =>
    DateFormat(_pattern('short'), _dateLanguage).format(date);

String formatMonthJa(DateTime date) =>
    DateFormat(_pattern('month'), _dateLanguage).format(date);

String formatDayJa(DateTime date) =>
    DateFormat(_pattern('day'), _dateLanguage).format(date);

String formatTimeJa(DateTime date) => DateFormat('HH:mm').format(date);

/// Localized weekday name for [weekday] (1 = Monday … 7 = Sunday).
///
/// 2026-01-04 is a Sunday, so `DateTime(2026, 1, 4 + weekday)` lands on the
/// requested weekday without DST-sensitive duration math.
String formatWeekdayJa(int weekday, {bool short = false}) {
  final date = DateTime(2026, 1, 4 + weekday.clamp(1, 7));
  return DateFormat(short ? _pattern('weekday_short') : _pattern('weekday_full'),
          _dateLanguage)
      .format(date);
}

String formatDateTimeJa(DateTime date) =>
    '${formatDateJa(date)} ${formatTimeJa(date)}';

String formatYearJa(DateTime date) =>
    DateFormat(_pattern('year'), _dateLanguage).format(date);

String formatMonthShortJa(DateTime date) =>
    DateFormat(_pattern('month_short'), _dateLanguage).format(date);

String formatRangeJa(DateTime start, DateTime endInclusive) {
  final sameDay = start.year == endInclusive.year &&
      start.month == endInclusive.month &&
      start.day == endInclusive.day;
  if (sameDay) return formatDateJa(start);
  final separator = _pattern('range_separator');
  return '${formatDateShortJa(start)}$separator${formatDateShortJa(endInclusive)}';
}
