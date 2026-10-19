import 'dart:math' as math;

/// Structured output of the OCR post-processor.
class ParsedReceipt {
  const ParsedReceipt({
    this.merchant,
    this.purchasedAt,
    this.totalAmount,
    this.subtotalAmount,
    this.tax8Amount,
    this.tax10Amount,
    this.tax8Base,
    this.tax10Base,
    this.barcodeId,
    this.rawText = '',
    this.warnings = const <String>[],
    this.confidence = const <String, double>{},
  });

  final String? merchant;
  final DateTime? purchasedAt;
  final int? totalAmount;
  final int? subtotalAmount;
  final int? tax8Amount;
  final int? tax10Amount;
  final int? tax8Base;
  final int? tax10Base;
  final String? barcodeId;
  final String rawText;
  final List<String> warnings;

  /// Per-field confidence in 0..1 (used to highlight uncertain fields).
  final Map<String, double> confidence;

  bool get isEmpty =>
      merchant == null &&
      totalAmount == null &&
      purchasedAt == null &&
      barcodeId == null;

  double get overallConfidence {
    if (confidence.isEmpty) return 0;
    return confidence.values.reduce((a, b) => a + b) / confidence.length;
  }
}

/// Extracts merchant / date / totals / Japanese consumption tax / reference
/// numbers from raw OCR text of a Japanese (or English) receipt.
class ReceiptParser {
  const ReceiptParser();

  // Keyword priority: the first keyword found wins the "total" slot.
  static const List<String> _totalKeywords = <String>[
    '税込合計',
    '合計金額',
    'ご合計',
    'お会計',
    'ご請求金額',
    '請求金額',
    'お支払金額',
    'お買上計',
    'お買い上げ計',
    '合計',
    '総計',
    '現計',
    '計',
  ];

  static const List<String> _subtotalKeywords = <String>[
    '小計',
    '税抜合計',
    '税抜金額',
    '税抜',
  ];

  /// Lines that contain money but must never be treated as the receipt total.
  static const List<String> _nonTotalHints = <String>[
    'お預り',
    'お預かり',
    '預り',
    'お釣',
    '釣銭',
    'つり',
    'おつり',
    '現金',
    'クレジット',
    'カード',
    'ポイント',
    '残高',
    '電子マネー',
    'お支払',
    '支払方法',
  ];

  static const List<String> _merchantNoise = <String>[
    '領収書',
    '領収証',
    'レシート',
    'ご来店',
    'ありがとう',
    'お問い合わせ',
    '電話',
    'TEL',
    '登録番号',
    'インボイス',
    '適格請求書',
    '事業者',
    'レジ',
    '担当',
    '日付',
    '時刻',
    '合計',
    '小計',
    '会計',
    'お支払',
    '支払',
    'お預り',
    'お預かり',
    '預り',
    '釣銭',
    'お釣',
    'つり',
    'おつり',
    '消費税',
    '税込',
    '税抜',
    '内税',
    '外税',
    '対象',
    'バーコード',
  ];

  static final RegExp _dateMask =
      RegExp(r'\d{2,4}\s*[年\/\.\-]\s*\d{1,2}\s*[月\/\.\-]\s*\d{1,2}\s*日?');
  static final RegExp _timeMask = RegExp(r'\d{1,2}\s*[時:]\s*\d{1,2}\s*分?');
  static final RegExp _phoneMask = RegExp(r'0\d{1,4}[\-ー]\d{1,4}[\-ー]\d{3,4}');
  static final RegExp _percentMask = RegExp(r'\d{1,3}\s*%');
  static final RegExp _invoiceMask = RegExp(r'[TＴ]\d{13}');
  static final RegExp _amountPattern =
      RegExp(r'[¥￥]?\s*(\d{1,3}(?:,\d{3})+|\d+)\s*円?');

  /// Main entry point.
  ///
  /// [scannedBarcode] wins over any reference number guessed from the text.
  ParsedReceipt parse(
    String rawText, {
    String? scannedBarcode,
    DateTime? now,
  }) {
    final normalized = _normalize(rawText);
    final lines = normalized
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    final warnings = <String>[];
    final confidence = <String, double>{};

    // --- merchant -----------------------------------------------------------
    final merchant = _detectMerchant(lines);
    if (merchant != null) {
      confidence['merchant'] = 0.7;
    } else {
      warnings.add('店舗名を検出できませんでした');
    }

    // --- date & time --------------------------------------------------------
    final purchasedAt = _detectDateTime(lines);
    if (purchasedAt != null) {
      confidence['date'] = 0.8;
    } else {
      warnings.add('日付を検出できませんでした');
    }

    // --- reference / barcode ------------------------------------------------
    final barcodeId = (scannedBarcode != null && scannedBarcode.trim().isNotEmpty)
        ? scannedBarcode.trim()
        : _detectReferenceNumber(lines);
    if (barcodeId != null) confidence['barcode'] = scannedBarcode != null ? 1.0 : 0.5;

    // --- amounts ------------------------------------------------------------
    final subtotal = _detectByKeywords(lines, _subtotalKeywords);
    var total = _detectByKeywords(lines, _totalKeywords, isTotal: true);
    if (total == null) {
      total = _fallbackTotal(lines);
      if (total != null) confidence['total'] = 0.45;
    } else {
      confidence['total'] = 0.85;
    }
    if (total == null) warnings.add('合計金額を検出できませんでした');

    // --- consumption tax ----------------------------------------------------
    final tax = _detectTax(lines);
    var tax8 = tax.tax8;
    var tax10 = tax.tax10;
    var base8 = tax.base8;
    var base10 = tax.base10;

    // Derive missing tax amounts from tax-inclusive taxable bases (内税).
    tax8 ??= base8 == null ? null : (base8 * 8 / 108).round();
    tax10 ??= base10 == null ? null : (base10 * 10 / 110).round();

    // Total is often only printed as "8%対象 / 10%対象" sums.
    if (total == null && (base8 != null || base10 != null)) {
      total = (base8 ?? 0) + (base10 ?? 0);
      confidence['total'] = 0.6;
      warnings.remove('合計金額を検出できませんでした');
    }

    // Single-rate receipt: infer the taxable base from total - tax.
    final onlyOneRate = (tax8 == null) != (tax10 == null);
    if (onlyOneRate && base8 == null && base10 == null && total != null) {
      final isEight = tax8 != null;
      final taxAmount = tax8 ?? tax10!;
      final base = total - taxAmount;
      if (base > 0) {
        if (isEight) {
          base8 = base;
        } else {
          base10 = base;
        }
      }
    }

    // Sanity checks — drop obviously mis-detected tax lines.
    if (tax8 != null && total != null && tax8 > total) {
      warnings.add('8%消費税の読み取り値が合計を超えたため破棄しました');
      tax8 = null;
    }
    if (tax10 != null && total != null && tax10 > total) {
      warnings.add('10%消費税の読み取り値が合計を超えたため破棄しました');
      tax10 = null;
    }
    if (subtotal != null && total != null && subtotal > total) {
      warnings.add('小計が合計を上回っています。読み取り値を確認してください');
    }
    if (tax8 != null || tax10 != null) confidence['tax'] = 0.6;

    return ParsedReceipt(
      merchant: merchant,
      purchasedAt: purchasedAt,
      totalAmount: total,
      subtotalAmount: subtotal,
      tax8Amount: tax8,
      tax10Amount: tax10,
      tax8Base: base8,
      tax10Base: base10,
      barcodeId: barcodeId,
      rawText: rawText,
      warnings: warnings,
      confidence: confidence,
    );
  }

  // -------------------------------------------------------------------------
  // Normalisation
  // -------------------------------------------------------------------------

  /// Full-width ASCII (U+FF01..U+FF5E) -> half-width, ideographic space -> ' ',
  /// full-width yen sign -> '¥'.
  String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune == 0xFFE5) {
        buffer.write('¥');
      } else {
        buffer.writeCharCode(rune);
      }
    }
    return buffer.toString();
  }

  // -------------------------------------------------------------------------
  // Money
  // -------------------------------------------------------------------------

  /// All plausible JPY amounts in [line], with dates / times / phone numbers /
  /// percentages / long codes masked out first.
  List<int> amountsIn(String line) {
    var masked = line;
    for (final pattern in <RegExp>[
      _dateMask,
      _timeMask,
      _phoneMask,
      _percentMask,
      _invoiceMask,
    ]) {
      masked = masked.replaceAll(pattern, ' ');
    }

    final result = <int>[];
    for (final match in _amountPattern.allMatches(masked)) {
      final token = match.group(0)!;
      final digits = match.group(1)!.replaceAll(',', '');
      final value = int.tryParse(digits);
      if (value == null) continue;

      final hasCurrency = token.contains('¥') ||
          token.contains('￥') ||
          token.contains('円');
      final before = match.start > 0 ? masked[match.start - 1] : ' ';
      final after = match.end < masked.length ? masked[match.end] : ' ';

      if (RegExp(r'[0-9]').hasMatch(before)) continue; // inside a longer number
      if (RegExp(r'[0-9A-Za-z]').hasMatch(after)) continue;
      if (!hasCurrency && value < 100) continue; // rates, counts, item index
      if (value > 10000000) continue;
      result.add(value);
    }
    return result;
  }

  int? _detectByKeywords(
    List<String> lines,
    List<String> keywords, {
    bool isTotal = false,
  }) {
    for (final keyword in keywords) {
      final values = <int>[];
      for (final line in lines) {
        if (!line.contains(keyword)) continue;

        if (keyword == '合計' && line.contains('税抜')) continue;
        if (keyword == '計') {
          // '計' is a substring of 合計 / 小計 / 会計 -> require a standalone use.
          if (line.contains('合計') || line.contains('小計') || line.contains('会計')) {
            continue;
          }
        }
        if (isTotal && _isPaymentLine(line)) continue;

        values.addAll(amountsIn(line).where((value) => value >= 100));
      }
      if (values.isNotEmpty) return values.reduce(math.max);
    }
    return null;
  }

  /// Largest plausible amount that is not a change / payment / balance line.
  int? _fallbackTotal(List<String> lines) {
    final candidates = <int>[];
    for (final line in lines) {
      if (_isPaymentLine(line)) continue;
      if (line.contains('対象') || line.contains('税率')) continue;
      candidates.addAll(amountsIn(line).where((value) => value >= 100));
    }
    if (candidates.isEmpty) return null;
    return candidates.reduce(math.max);
  }

  bool _isPaymentLine(String line) =>
      _nonTotalHints.any((hint) => line.contains(hint));

  // -------------------------------------------------------------------------
  // Tax
  // -------------------------------------------------------------------------

  _TaxDetection _detectTax(List<String> lines) {
    final tax = _TaxDetection();

    for (final line in lines) {
      final mentionsTax = line.contains('消費税') ||
          line.contains('内税') ||
          line.contains('外税') ||
          line.contains('税額');
      final mentionsBase = line.contains('対象') || line.contains('課税');
      if (!mentionsTax && !mentionsBase) continue;

      final values = amountsIn(line).where((value) => value >= 1).toList();
      if (values.isEmpty) continue;

      var rate = _extractRate(line);
      if (rate == null && line.contains('軽減')) rate = 8;

      if (mentionsTax && values.length >= 2) {
        // e.g. "8%対象 ¥1,000 消費税 ¥74"
        _assignBase(tax, rate, values.reduce(math.max));
        _assignTax(tax, rate, values.reduce(math.min));
      } else if (mentionsBase) {
        _assignBase(tax, rate, values.reduce(math.max));
      } else if (mentionsTax) {
        _assignTax(tax, rate, values.reduce(math.max));
      }
    }
    return tax;
  }

  int? _extractRate(String line) {
    final match = RegExp(r'(8|10)\s*%').firstMatch(line);
    if (match != null) return int.parse(match.group(1)!);
    return null;
  }

  void _assignTax(_TaxDetection tax, int? rate, int amount) {
    // A missing rate on a "消費税" line is assumed to be the standard 10%.
    if (rate == 8) {
      tax.tax8 = math.max(tax.tax8 ?? 0, amount);
    } else {
      tax.tax10 = math.max(tax.tax10 ?? 0, amount);
    }
  }

  void _assignBase(_TaxDetection tax, int? rate, int amount) {
    if (rate == 8) {
      tax.base8 = math.max(tax.base8 ?? 0, amount);
    } else if (rate == 10) {
      tax.base10 = math.max(tax.base10 ?? 0, amount);
    }
  }

  // -------------------------------------------------------------------------
  // Merchant
  // -------------------------------------------------------------------------

  String? _detectMerchant(List<String> lines) {
    final limit = math.min(lines.length, 12);
    String? best;
    var bestScore = 0.0;

    for (var i = 0; i < limit; i++) {
      final cleaned = _cleanMerchant(lines[i]);
      if (cleaned == null) continue;

      var score = 1.0 - i * 0.08;
      if (RegExp(
        r'店|ストア|マート|カフェ|レストラン|薬局|薬店|ドラッグ|書店|スーパー|'
        r'株式会社|\(株\)|有限会社|商事|Co\.|Inc\.|Ltd\.',
      ).hasMatch(cleaned)) {
        score += 0.9;
      }
      if (RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(cleaned)) {
        score += 0.2;
      }
      if (cleaned.length >= 3 && cleaned.length <= 24) score += 0.2;

      if (score > bestScore) {
        bestScore = score;
        best = cleaned;
      }
    }
    return best;
  }

  String? _cleanMerchant(String line) {
    var candidate = line.trim();
    if (candidate.isEmpty) return null;

    // Pure numbers / symbols.
    if (RegExp(r'^[\d\s¥￥,.\-:/*#|]+$').hasMatch(candidate)) return null;
    // Dates and times are never merchants.
    if (_dateMask.hasMatch(candidate)) return null;
    if (RegExp(r'(令和|平成|昭和)\s*(\d{1,2}|元)\s*年').hasMatch(candidate)) {
      return null;
    }
    if (RegExp(r'\d{1,2}\s*[時:]\s*\d{2}').hasMatch(candidate)) return null;
    // Known receipt boilerplate.
    if (_merchantNoise.any(candidate.contains)) return null;
    // A line that is only numbers plus latin letters (codes, totals).
    if (amountsIn(candidate).isNotEmpty &&
        !RegExp(r'[\u3040-\u30ff\u4e00-\u9fff]').hasMatch(candidate)) {
      return null;
    }

    candidate = candidate
        .replaceFirst(
          RegExp(r'^[\s\-\*=#~|■□◆◇●○【】\[\]「」<>※\*]+'),
          '',
        )
        .replaceFirst(
          RegExp(r'[\s\-\*=#~|■□◆◇●○【】\[\]「」<>※\*]+$'),
          '',
        )
        .trim();

    if (candidate.length < 2) return null;
    return candidate;
  }

  // -------------------------------------------------------------------------
  // Date & time
  // -------------------------------------------------------------------------

  DateTime? _detectDateTime(List<String> lines) {
    DateTime? date;
    for (final line in lines) {
      date = _parseDate(line);
      if (date != null) break;
    }
    if (date == null) return null;

    (int, int)? time;
    for (final line in lines) {
      time = _parseTime(line);
      if (time != null) break;
    }
    if (time == null) return date;
    return DateTime(date.year, date.month, date.day, time.$1, time.$2);
  }

  DateTime? _parseDate(String line) {
    // 2026年10月19日 / 2026/10/19 / 2026.10.19 / 2026-10-19
    var match = RegExp(
      r'(20\d{2}|19\d{2})\s*[年\/.\-]\s*(\d{1,2})\s*[月\/.\-]\s*(\d{1,2})',
    ).firstMatch(line);
    if (match != null) {
      final parsed = _safeDate(
        int.parse(match.group(1)!),
        int.parse(match.group(2)!),
        int.parse(match.group(3)!),
      );
      if (parsed != null) return parsed;
    }

    // 令和8年10月19日
    match = RegExp(
      r'(令和|平成|昭和)\s*(\d{1,2}|元)\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日',
    ).firstMatch(line);
    if (match != null) {
      final base = switch (match.group(1)!) {
        '令和' => 2018,
        '平成' => 1988,
        _ => 1925,
      };
      final eraYear =
          match.group(2) == '元' ? 1 : int.parse(match.group(2)!);
      final parsed = _safeDate(
        base + eraYear,
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
      );
      if (parsed != null) return parsed;
    }

    // R6.10.19 / R 6/10/19
    match = RegExp(
      r'([RHS])\s*(\d{1,2})\s*[.\/\-]\s*(\d{1,2})\s*[.\/\-]\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(line);
    if (match != null) {
      final base = switch (match.group(1)!.toUpperCase()) {
        'R' => 2018,
        'H' => 1988,
        _ => 1925,
      };
      final parsed = _safeDate(
        base + int.parse(match.group(2)!),
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
      );
      if (parsed != null) return parsed;
    }

    // 26/10/19 (2-digit year)
    match = RegExp(
      r'(^|\D)(\d{2})\s*[.\/\-]\s*(\d{1,2})\s*[.\/\-]\s*(\d{1,2})(?!\d)',
    ).firstMatch(line);
    if (match != null) {
      final twoDigits = int.parse(match.group(2)!);
      final year = twoDigits >= 70 ? 1900 + twoDigits : 2000 + twoDigits;
      final parsed = _safeDate(
        year,
        int.parse(match.group(3)!),
        int.parse(match.group(4)!),
      );
      if (parsed != null) return parsed;
    }
    return null;
  }

  (int, int)? _parseTime(String line) {
    final match =
        RegExp(r'(^|\D)(\d{1,2})\s*[:時]\s*(\d{1,2})').firstMatch(line);
    if (match == null) return null;
    final hour = int.parse(match.group(2)!);
    final minute = int.parse(match.group(3)!);
    if (hour > 23 || minute > 59) return null;
    return (hour, minute);
  }

  DateTime? _safeDate(int year, int month, int day) {
    if (year < 1990 || year > 2100) return null;
    if (month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;
    return date;
  }

  // -------------------------------------------------------------------------
  // Reference / invoice numbers
  // -------------------------------------------------------------------------

  String? _detectReferenceNumber(List<String> lines) {
    final labelled = RegExp(
      r'(?:No\.?|NO\.?|番号|伝票)\s*[:#]?\s*([0-9]{4,20})',
      caseSensitive: false,
    );
    for (final line in lines) {
      final match = labelled.firstMatch(line);
      if (match != null) return match.group(1);
    }

    // Qualified invoice registration number: T + 13 digits.
    final invoice = RegExp(r'[TＴ]\s*(\d{13})');
    for (final line in lines) {
      final match = invoice.firstMatch(line);
      if (match != null) return 'T${match.group(1)}';
    }
    return null;
  }
}

class _TaxDetection {
  int? tax8;
  int? tax10;
  int? base8;
  int? base10;
}
