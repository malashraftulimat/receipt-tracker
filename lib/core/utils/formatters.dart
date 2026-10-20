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
  final pattern = _isJapanese
      ? 'yyyy年M月'
      : (_isArabic ? 'MMMM y' : 'MMMM y');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatDayJa(DateTime date) {
  final pattern = _isJapanese
      ? 'M月d日(E)'
      : (_isArabic ? 'EEEE، d MMMM' : 'EEE, MMM d');
  return DateFormat(pattern, _dateLanguage).format(date);
}

String formatTimeJa(DateTime date) => DateFormat('HH:mm').format(date);

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
