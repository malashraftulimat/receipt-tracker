import 'package:intl/intl.dart';

/// `¥1,234` (JPY is always displayed without decimals).
String formatYen(num amount, {bool withSymbol = true}) {
  final value = amount.round();
  final digits = value.abs().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final sign = value < 0 ? '-' : '';
  return withSymbol ? '$sign¥$buffer' : '$sign$buffer';
}

/// `1.2万円` style compact label for charts.
String formatCompactYen(num amount) {
  final value = amount.round();
  if (value.abs() >= 10000) {
    final man = value / 10000;
    final text = man.abs() >= 100
        ? man.round().toString()
        : man.toStringAsFixed(1).replaceAll(RegExp(r'\.0$'), '');
    return '$text万円';
  }
  return formatYen(value);
}

/// `1,234` without the currency symbol.
String formatAmountDigits(num amount) => formatYen(amount, withSymbol: false);

/// Parses user input such as `¥1,234` or `１２３４` into an integer yen value.
int? parseYenInput(String input) {
  final normalized = StringBuffer();
  for (final rune in input.runes) {
    // Full-width digits -> ASCII digits, so IME input works too.
    if (rune >= 0xFF10 && rune <= 0xFF19) {
      normalized.writeCharCode(rune - 0xFEE0);
    } else {
      normalized.writeCharCode(rune);
    }
  }
  final digits = normalized.toString().replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return null;
  return int.tryParse(digits);
}

// ---------------------------------------------------------------------------
// Dates — `ja` locale symbol data must be loaded in main() via
// initializeDateFormatting('ja').
// ---------------------------------------------------------------------------

String formatDateJa(DateTime date) =>
    DateFormat('yyyy年M月d日(E)', 'ja').format(date);

String formatDateShortJa(DateTime date) =>
    DateFormat('yyyy/M/d(E)', 'ja').format(date);

String formatMonthJa(DateTime date) =>
    DateFormat('yyyy年M月', 'ja').format(date);

String formatDayJa(DateTime date) => DateFormat('M月d日(E)', 'ja').format(date);

String formatTimeJa(DateTime date) => DateFormat('HH:mm').format(date);

String formatDateTimeJa(DateTime date) =>
    DateFormat('yyyy年M月d日(E) HH:mm', 'ja').format(date);

String formatYearJa(DateTime date) => DateFormat('yyyy年', 'ja').format(date);

String formatMonthShortJa(DateTime date) => DateFormat('M月', 'ja').format(date);

String formatRangeJa(DateTime start, DateTime endInclusive) {
  final sameDay = start.year == endInclusive.year &&
      start.month == endInclusive.month &&
      start.day == endInclusive.day;
  if (sameDay) return formatDateJa(start);
  return '${formatDateShortJa(start)} 〜 ${formatDateShortJa(endInclusive)}';
}
