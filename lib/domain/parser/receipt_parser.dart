import 'dart:math' as math;

import '../../core/localization/currencies.dart';
import 'receipt_amount_check.dart';
import 'receipt_identity.dart';

/// One parsed line item (before the user edits it).
class ParsedItem {
  const ParsedItem({
    required this.name,
    this.quantity = 1,
    this.unitPrice,
    this.totalPrice = 0,
    this.taxRate,
  });

  final String name;
  final int quantity;
  final double? unitPrice;
  final double totalPrice;

  /// 8 = reduced rate, 10 = standard rate, null = unknown / not applicable.
  final int? taxRate;
}

/// Coupon / voucher printed on a receipt for a future visit.
class ParsedCoupon {
  const ParsedCoupon({
    required this.name,
    this.validFrom,
    this.validUntil,
    this.discountAmountOrPercent,
  });

  /// Coupon title exactly as printed (including any amount wording).
  final String name;

  /// First day the coupon can be used; null when valid immediately.
  final DateTime? validFrom;

  /// Last day the coupon can be used; null when no expiry is printed.
  final DateTime? validUntil;

  /// Printed value such as `10%` or `500`, in [ParsedReceipt.currency] for an
  /// amount. Null when the coupon does not state one.
  final String? discountAmountOrPercent;

  /// True when [validUntil] is in the past relative to [at] (default: now).
  bool isExpired({DateTime? at}) {
    final until = validUntil;
    if (until == null) return false;
    final day = at ?? DateTime.now();
    final endExclusive =
        DateTime(until.year, until.month, until.day).add(const Duration(days: 1));
    return !day.isBefore(endExclusive);
  }
}

/// Structured output of the OCR post-processor.
class ParsedReceipt {
  const ParsedReceipt({
    this.merchant,
    this.currency,
    this.purchasedAt,
    this.totalAmount,
    this.subtotalAmount,
    this.tax8Amount,
    this.tax10Amount,
    this.tax8Base,
    this.tax10Base,
    this.tax8ItemsTotal,
    this.tax10ItemsTotal,
    this.dueDate,
    this.pointBrand,
    this.pointAmount,
    this.receiptNumber,
    this.registrationNumber,
    this.suggestedCategory,
    this.coupon,
    this.items = const <ParsedItem>[],
    this.rawText = '',
    this.warnings = const <String>[],
    this.confidence = const <String, double>{},
  });

  final String? merchant;

  /// ISO-4217 currency code (e.g. JPY, USD, SAR) when detected.
  final String? currency;
  final DateTime? purchasedAt;
  final double? totalAmount;
  final double? subtotalAmount;
  final double? tax8Amount;
  final double? tax10Amount;
  final double? tax8Base;
  final double? tax10Base;

  /// Sum of item lines detected as 8% / 10% (estimated, optional).
  final double? tax8ItemsTotal;
  final double? tax10ItemsTotal;

  /// 振込用紙 / utility bill payment deadline.
  final DateTime? dueDate;

  /// Loyalty points printed on the receipt.
  final String? pointBrand;
  final int? pointAmount;

  /// The receipt's own number (伝票番号 / レシート番号 / receipt barcode).
  /// This is the duplicate key. Never a 登録番号.
  final String? receiptNumber;

  /// Japanese qualified-invoice registration number (登録番号, T + 13 digits).
  /// Identifies the business and repeats on every receipt from that shop.
  final String? registrationNumber;

  /// Backwards-compatible alias for [receiptNumber].
  String? get barcodeId => receiptNumber;

  /// Gemini-suggested seeded category name (e.g. 食費 / 交通費).
  final String? suggestedCategory;

  /// Coupon / voucher printed for a future visit, when the receipt has one.
  final ParsedCoupon? coupon;

  /// Item rows extracted above the total section, including fees and applied
  /// discounts (the latter as negative amounts).
  final List<ParsedItem> items;

  final String rawText;
  final List<String> warnings;

  /// Per-field confidence in 0..1 (used to highlight uncertain fields).
  final Map<String, double> confidence;

  bool get isEmpty =>
      merchant == null &&
      totalAmount == null &&
      purchasedAt == null &&
      receiptNumber == null &&
      registrationNumber == null;

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
    'Total',
    'TOTAL',
    'Grand Total',
    'Amount Due',
    'Balance Due',
  ];

  static const List<String> _subtotalKeywords = <String>[
    '小計',
    'Subtotal',
    'SUBTOTAL',
    'Sub Total',
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
    'Cash',
    'Change',
    'Card',
    'Payment',
    'Tendered',
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
  static final RegExp _addressMask = RegExp(
    r'(?:〒\s*\d{3}-?\d{4})|'
    r'(?:[^\s]{1,10}(?:都|道|府|県))[^\n]{0,40}(?:市|区|町|村)|'
    r'(?:丁目|番地|号室)',
  );

  bool _looksLikeAddress(String line) => _addressMask.hasMatch(line);
  static final RegExp _amountPattern = RegExp(
    '$kCurrencyAmountPrefixPattern'
    r'\s*(\d{1,3}(?:[,\.]\d{3})+|\d+)'
    r'(?:([.,])(\d{1,2}))?\s*'
    '$kCurrencySuffixPattern?',
  );

  static final RegExp _currencyCodeMask = RegExp(kCurrencyCodePattern);

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
    final currency = _detectCurrency(normalized);

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
    // 登録番号 (T + 13 digits) identifies the shop and repeats on every
    // receipt. It is stored separately and never used as a duplicate key.
    var registrationNumber = _detectInvoiceRegistrationNumber(lines);
    var receiptNumber = _detectReceiptNumber(lines);
    final scanned = (scannedBarcode ?? '').trim();
    if (scanned.isNotEmpty) {
      if (ReceiptIdentity.isInvoiceRegistrationNumber(scanned)) {
        registrationNumber =
            ReceiptIdentity.normalizeInvoiceRegistrationNumber(scanned);
      } else {
        receiptNumber = scanned;
      }
    }
    if (receiptNumber != null) {
      confidence['receiptNumber'] =
          scanned.isNotEmpty ? 1.0 : 0.5;
    }
    if (registrationNumber != null) {
      confidence['registrationNumber'] = scanned.isNotEmpty ? 1.0 : 0.6;
    }

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
    tax8 ??= base8 == null ? null : _roundMoney(base8 * 8 / 108);
    tax10 ??= base10 == null ? null : _roundMoney(base10 * 10 / 110);

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

    // --- item-level reduced / standard rate split --------------------------
    final tax8ItemsTotal = _detectItemTotal(lines, 8);
    final tax10ItemsTotal = _detectItemTotal(lines, 10);

    // --- payment deadline (振込用紙) ---------------------------------------
    final dueDate = _detectDueDate(lines);
    if (dueDate != null) confidence['dueDate'] = 0.7;

    // --- line items ---------------------------------------------------------
    final items = _parseItems(lines);
    if (items.isNotEmpty) {
      confidence['items'] = 0.6;
      if (total != null) {
        final itemsSum = items.fold<double>(
          0,
          (sum, item) => sum + item.totalPrice,
        );
        if (!itemsTotalMatchesReceipt(
          itemsTotal: itemsSum,
          subtotalAmount: subtotal,
          taxTotal: (tax8 ?? 0) + (tax10 ?? 0),
          totalAmount: total,
        )) {
          warnings.add('明細の合計がレシートの合計と一致しません。内容を確認してください');
        }
      }
    }

    // --- loyalty points ----------------------------------------------------
    final points = _detectPoints(lines);
    if (points != null) confidence['points'] = 0.6;

    return ParsedReceipt(
      merchant: merchant,
      currency: currency,
      purchasedAt: purchasedAt,
      totalAmount: total,
      subtotalAmount: subtotal,
      tax8Amount: tax8,
      tax10Amount: tax10,
      tax8Base: base8,
      tax10Base: base10,
      tax8ItemsTotal: tax8ItemsTotal,
      tax10ItemsTotal: tax10ItemsTotal,
      dueDate: dueDate,
      pointBrand: points?.brand,
      pointAmount: points?.amount,
      receiptNumber: receiptNumber,
      registrationNumber: registrationNumber,
      items: items,
      rawText: rawText,
      warnings: warnings,
      confidence: confidence,
    );
  }

  // -------------------------------------------------------------------------
  // Normalisation
  // -------------------------------------------------------------------------

  /// Full-width ASCII (U+FF01..U+FF5E) -> half-width, ideographic space -> ' ',
  /// full-width yen sign -> the canonical yen symbol.
  String _normalize(String input) {
    final buffer = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0xFF01 && rune <= 0xFF5E) {
        buffer.writeCharCode(rune - 0xFEE0);
      } else if (rune == 0x3000) {
        buffer.write(' ');
      } else if (rune == 0xFFE5) {
        buffer.write(kYenSymbol);
      } else {
        buffer.writeCharCode(rune);
      }
    }
    // Normalise common simplified / traditional OCR variants to the Japanese
    // forms used by the keyword lists below (e.g. 对象税 -> 対象税).
    var normalized = buffer.toString();
    const variants = <String, String>{
      '对': '対',
      '對': '対',
      '会': '会',
      '會': '会',
      '计': '計',
      '計': '計',
      '领': '領',
      '領': '領',
      '收': '収',
      '収': '収',
      '录': '録',
      '錄': '録',
      '费': '費',
      '費': '費',
      '额': '額',
      '額': '額',
      '号': '号',
      '號': '号',
      '登录': '登録',
      '登录番号': '登録番号',
    };
    for (final entry in variants.entries) {
      normalized = normalized.replaceAll(entry.key, entry.value);
    }
    return normalized;
  }

  // -------------------------------------------------------------------------
  // Money
  // -------------------------------------------------------------------------

  /// All plausible amounts in [line], with dates / times / phone numbers /
  /// percentages / long codes masked out first. Decimal amounts are supported
  /// so receipts in other currencies (e.g. 12.99 USD) parse correctly.
  List<double> amountsIn(String line) {
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

    final result = <double>[];
    for (final match in _amountPattern.allMatches(masked)) {
      final token = match.group(0)!;
      final digits = match.group(1)!.replaceAll(RegExp(r'[,\.]'), '');
      final fraction = match.group(3);
      final raw = fraction == null ? digits : '$digits.$fraction';
      final value = double.tryParse(raw);
      if (value == null) continue;

      final hasCurrency = RegExp(kCurrencySymbolPattern).hasMatch(token) ||
          _currencyCodeMask.hasMatch(masked);
      final before = match.start > 0 ? masked[match.start - 1] : ' ';
      final after = match.end < masked.length ? masked[match.end] : ' ';

      if (RegExp(r'[0-9]').hasMatch(before)) continue; // inside a longer number
      if (RegExp(r'[0-9A-Za-z]').hasMatch(after)) continue;
      if (!hasCurrency && value < 1) continue; // rates, counts, item index
      if (value > 10000000) continue;
      result.add(value);
    }
    return result;
  }

  static double _maxAmount(List<double> values) =>
      values.reduce((a, b) => a > b ? a : b);

  static double _roundMoney(double value) =>
      (value * 100).roundToDouble() / 100;

  /// Best-effort currency detection for the OCR fallback path.
  String? _detectCurrency(String text) {
    final upper = text.toUpperCase();
    final code = _currencyCodeMask.firstMatch(upper);
    if (code != null) return code.group(1);

    for (final entry in kCurrencySymbolToCode.entries) {
      if (text.contains(entry.key)) return entry.value;
    }
    return null;
  }

  double? _detectByKeywords(
    List<String> lines,
    List<String> keywords, {
    bool isTotal = false,
  }) {
    for (final keyword in keywords) {
      final values = <double>[];
      for (final line in lines) {
        if (!line.contains(keyword)) continue;

        if (keyword == '合計' && line.contains('税抜')) continue;
        if (keyword == '計') {
          // '計' is a substring of 合計 / 小計 / 会計 -> require a standalone use.
          if (line.contains('合計') ||
              line.contains('小計') ||
              line.contains('会計')) {
            continue;
          }
        }
        if (isTotal && _isPaymentLine(line)) continue;

        values.addAll(amountsIn(line).where((value) => value >= 1));
      }
      if (values.isNotEmpty) return _maxAmount(values);
    }
    return null;
  }

  /// Largest plausible amount that is not a change / payment / balance line.
  double? _fallbackTotal(List<String> lines) {
    final candidates = <double>[];
    for (final line in lines) {
      if (_isPaymentLine(line)) continue;
      if (line.contains('対象') || line.contains('税率')) continue;
      candidates.addAll(amountsIn(line).where((value) => value >= 1));
    }
    if (candidates.isEmpty) return null;
    return _maxAmount(candidates);
  }

  bool _isPaymentLine(String line) {
    final lower = line.toLowerCase();
    return _nonTotalHints.any((hint) => lower.contains(hint.toLowerCase()));
  }

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
        // e.g. "8% taxable 1,000, tax 74"
        _assignBase(tax, rate, _maxAmount(values));
        _assignTax(
          tax,
          rate,
          values.reduce((a, b) => a < b ? a : b),
        );
      } else if (mentionsBase) {
        _assignBase(tax, rate, _maxAmount(values));
      } else if (mentionsTax) {
        _assignTax(tax, rate, _maxAmount(values));
      }
    }
    return tax;
  }

  int? _extractRate(String line) {
    final match = RegExp(r'(8|10)\s*%').firstMatch(line);
    if (match != null) return int.parse(match.group(1)!);
    return null;
  }

  void _assignTax(_TaxDetection tax, int? rate, double amount) {
    // A missing rate on a "消費税" line is assumed to be the standard 10%.
    if (rate == 8) {
      tax.tax8 = _maxAmount(<double>[tax.tax8 ?? 0, amount]);
    } else {
      tax.tax10 = _maxAmount(<double>[tax.tax10 ?? 0, amount]);
    }
  }

  void _assignBase(_TaxDetection tax, int? rate, double amount) {
    if (rate == 8) {
      tax.base8 = _maxAmount(<double>[tax.base8 ?? 0, amount]);
    } else if (rate == 10) {
      tax.base10 = _maxAmount(<double>[tax.base10 ?? 0, amount]);
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
    if (RegExp(r'^[\d\s' + kCurrencySymbolChars + r',.\-:/*#|]+$')
        .hasMatch(candidate)) {
      return null;
    }
    // Dates and times are never merchants.
    if (_dateMask.hasMatch(candidate)) return null;
    if (RegExp(r'(令和|平成|昭和)\s*(\d{1,2}|元)\s*年').hasMatch(candidate)) {
      return null;
    }
    if (RegExp(r'\d{1,2}\s*[時:]\s*\d{2}').hasMatch(candidate)) return null;
    if (RegExp(r'(会計日|會計日)').hasMatch(candidate)) return null;
    if (_looksLikeAddress(candidate)) return null;
    // Long unseparated numbers are more likely OCR date / reference codes.
    if (RegExp(r'\d{6,}').hasMatch(candidate)) return null;
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
      final eraYear = match.group(2) == '元' ? 1 : int.parse(match.group(2)!);
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

  /// Japanese qualified-invoice registration number (登録番号).
  String? _detectInvoiceRegistrationNumber(List<String> lines) {
    final invoice = RegExp(r'[TＴ]\s*(\d{13})');
    for (final line in lines) {
      final match = invoice.firstMatch(line);
      if (match != null) return 'T${match.group(1)}';
    }
    return null;
  }

  /// The receipt's own number, never the shop's 登録番号.
  ///
  /// Coupon barcodes (クーポン / 利用期限 / "No." printed under a coupon) are
  /// ignored because they are not unique to this purchase.
  String? _detectReceiptNumber(List<String> lines) {
    const couponMarkers = <String>[
      'クーポン',
      '利用期限',
      '有効期限',
      '割引券',
      '特典券',
      '回数券',
      'coupon',
      'voucher',
    ];
    // Only a real coupon heading makes the following "No." line a coupon
    // number. 利用期限 / 有効期限 can also precede unrelated lines.
    const couponHeadings = <String>[
      'クーポン',
      '割引券',
      '特典券',
      '回数券',
      'coupon',
      'voucher',
    ];
    bool containsAny(String value, List<String> markers) {
      final lower = value.toLowerCase();
      return markers.any((marker) => lower.contains(marker));
    }

    final explicitReceiptLabel = RegExp(
      r'(?:レシート|伝票|領収書|受付|注文|オーダー|receipt|slip)\s*'
      r'(?:No\.?|NO\.?|番号)\s*[:#]?\s*([0-9]{3,20})',
      caseSensitive: false,
    );
    final labelled = RegExp(
      r'(?:レシート|伝票|領収書|受付|注文|オーダー|バーコード|barcode)?\s*'
      r'(?:No\.?|NO\.?|番号)\s*[:#]?\s*([0-9]{3,20})',
      caseSensitive: false,
    );
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (containsAny(line, couponMarkers)) continue;
      final explicit = explicitReceiptLabel.firstMatch(line);
      if (explicit != null) {
        final value = explicit.group(1);
        if (value != null) {
          return ReceiptIdentity.normalizeReceiptNumber(value);
        }
      }
      var underCoupon = false;
      for (var back = 1; back <= 3 && i - back >= 0; back++) {
        final prev = lines[i - back];
        if (containsAny(prev, couponHeadings) ||
            (back == 1 && containsAny(prev, couponMarkers))) {
          underCoupon = true;
          break;
        }
      }
      if (underCoupon) continue;
      final match = labelled.firstMatch(line);
      if (match == null) continue;
      final value = match.group(1);
      if (value == null) continue;
      return ReceiptIdentity.normalizeReceiptNumber(value);
    }
    return null;
  }

  // -------------------------------------------------------------------------
// -------------------------------------------------------------------------
  // Line items
  // -------------------------------------------------------------------------

  static final RegExp _itemQtyTimes = RegExp(
    r'(\d{1,3})\s*[×xX]\s*'
    '$kCurrencyAmountPrefixPattern'
    r'\s*(\d{1,3}(?:,\d{3})+|\d+)',
  );
  static final RegExp _itemQtyPiece = RegExp(r'(\d{1,3})\s*(?:個|点|本|枚|袋|箱)');
  static final RegExp _itemNoise = RegExp(
    r'電話|TEL|住所|登録番号|レジ|担当|領収|レシート|ポイント|お預|お釣|釣銭|'
    r'カード|現金|クレジット|電子マネー|支払|対象|消費税|税率|軽減|割引|値引|'
    r'No\.|番号|伝票|バーコード|小計|合計|総計|現計|お会計|領収書|'
    r'対象税|〒|お釣り|Total|Subtotal|Tax|VAT|Change|Cash|Card|Payment|Amount Due|Balance',
    caseSensitive: false,
  );

  /// Extracts item rows between the header and the first total line.
  List<ParsedItem> _parseItems(List<String> lines) {
    const totalMarkers = <String>[
      '合計',
      '小計',
      'お会計',
      '税込合計',
      '総計',
      '現計',
      'お預',
      'お釣',
      '釣銭',
      'total',
      'subtotal',
      'amount due',
      'balance due',
    ];

    final items = <ParsedItem>[];

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (totalMarkers.any((marker) => lower.contains(marker.toLowerCase()))) {
        break;
      }
      if (_itemNoise.hasMatch(line)) continue;
      if (_looksLikeAddress(line)) continue;
      if (_dateMask.hasMatch(line)) continue;
      if (RegExp(r'\d{1,2}\s*[:時]\s*\d{2}').hasMatch(line)) continue;

      final quantityMatch = _itemQtyTimes.firstMatch(line);
      final pieceMatch = _itemQtyPiece.firstMatch(line);

      // "2×198" prints the quantity before the unit price; ignore that first
      // number when collecting the line amounts.
      final amountLine = quantityMatch == null
          ? line
          : line.replaceFirst(RegExp(r'(\d{1,3})\s*[×xX]'), ' ');
      final amounts =
          amountsIn(amountLine).where((value) => value >= 1).toList();
      if (amounts.isEmpty) continue;

      var quantity = 1;
      double? unitPrice;
      if (quantityMatch != null) {
        quantity = int.tryParse(quantityMatch.group(1)!) ?? 1;
        unitPrice = double.tryParse(
          quantityMatch.group(2)!.replaceAll(RegExp(r'[,\.]'), ''),
        );
      } else if (pieceMatch != null) {
        quantity = int.tryParse(pieceMatch.group(1)!) ?? 1;
      }

      var totalPrice = amounts.last;
      if (quantityMatch != null && amounts.length == 1 && unitPrice != null) {
        // "2×198" style: the printed price is the unit price.
        totalPrice = unitPrice * quantity;
      }
      unitPrice ??= quantity > 1 ? totalPrice / quantity : totalPrice;

      var name = line;
      if (quantityMatch != null) {
        name = name.replaceFirst(quantityMatch.group(0)!, ' ');
      } else if (pieceMatch != null) {
        name = name.replaceFirst(pieceMatch.group(0)!, ' ');
      }

      for (final marker in <String>[
        '※',
        '＊',
        '*',
        '（8%）',
        '(8%)',
        '（10%）',
        '(10%)',
        '8%',
        '10%',
        '軽減',
      ]) {
        name = name.replaceAll(marker, ' ');
      }

      name = name.replaceAll(RegExp(kCurrencyPrefixSymbolPattern), ' ');
      name = name.replaceAll(RegExp(r'\d{1,3}(?:,\d{3})+|\d+'), ' ');
      name = name.replaceAll(RegExp(r'[×xX]'), ' ');
      name = name.replaceAll(RegExp(r'^[\s\-*:：.、|/]+'), '');
      name = name.replaceAll(RegExp(r'[\s\-*:：.、|/]+$'), '');
      name = name.replaceAll(RegExp(r'\s+'), ' ').trim();

      if (name.length < 2) continue;
      if (RegExp(r'^[\d\s.,\-]+$').hasMatch(name)) continue;

      final reducedMarker = line.contains('※') ||
          line.contains('軽減') ||
          line.contains('(8%)') ||
          line.contains('（8%）');
      final standardMarker = line.contains('(10%)') || line.contains('（10%）');
      final taxRate = reducedMarker ? 8 : (standardMarker ? 10 : null);

      items.add(
        ParsedItem(
          name: name,
          quantity: quantity,
          unitPrice: unitPrice,
          totalPrice: totalPrice,
          taxRate: taxRate,
        ),
      );
      if (items.length >= 50) break;
    }

    return items;
  }

  // -------------------------------------------------------------------------
  // Japanese receipt extras: reduced-rate items, payment deadlines, points
  // -------------------------------------------------------------------------

  /// Sum of item lines explicitly marked as 8% (reduced) or 10% (standard).
  double? _detectItemTotal(List<String> lines, int rate) {
    var sum = 0.0;
    var found = false;

    for (final line in lines) {
      if (line.contains('合計') ||
          line.contains('小計') ||
          line.contains('消費税') ||
          line.contains('対象') ||
          line.contains('税込') ||
          line.contains('税抜') ||
          line.contains('お預') ||
          line.contains('お釣') ||
          line.contains('釣銭') ||
          line.contains('ポイント')) {
        continue;
      }

      final markedReduced = line.contains('※') ||
          line.contains('軽減') ||
          line.contains('(8%)') ||
          line.contains('8%');
      final markedStandard = line.contains('(10%)') || line.contains('10%');

      if (rate == 8 && !markedReduced) continue;
      if (rate == 10 && !markedStandard) continue;

      final values = amountsIn(line).where((value) => value >= 1).toList();
      if (values.isEmpty) continue;
      sum += _maxAmount(values);
      found = true;
    }
    return found ? sum : null;
  }

  static const List<String> _dueDateKeywords = <String>[
    'お支払期限',
    '支払期限',
    'お支払期日',
    '支払期日',
    '納期限',
    'お支払日',
    '払込期限',
  ];

  /// 支払期限 / 納期限 on utility bills and 振込用紙.
  DateTime? _detectDueDate(List<String> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!_dueDateKeywords.any(line.contains)) continue;

      final date = _parseLooseDate(line) ??
          (i + 1 < lines.length ? _parseLooseDate(lines[i + 1]) : null);
      if (date != null) return _normalizeDueDate(date);
    }

    for (final line in lines) {
      if (!line.contains('振込') &&
          !line.contains('払込') &&
          !line.contains('コンビニ')) {
        continue;
      }
      final date = _parseLooseDate(line);
      if (date != null) return _normalizeDueDate(date);
    }
    return null;
  }

  DateTime _normalizeDueDate(DateTime date) {
    final now = DateTime.now();
    var result = date;
    if (result.isBefore(DateTime(now.year, now.month - 1, 1))) {
      result = DateTime(result.year + 1, result.month, result.day);
    }
    return DateTime(result.year, result.month, result.day);
  }

  /// Date parser that also accepts `10月31日` / `10/31` without a year.
  DateTime? _parseLooseDate(String text) {
    final full = _parseDate(text);
    if (full != null) return full;

    final withoutYear =
        RegExp(r'(?<!\d)(\d{1,2})\s*月\s*(\d{1,2})\s*日').firstMatch(text) ??
            RegExp(r'(?<!\d)(\d{1,2})\s*/\s*(\d{1,2})(?!\d)').firstMatch(text);
    if (withoutYear == null) return null;

    final now = DateTime.now();
    final month = int.parse(withoutYear.group(1)!);
    final day = int.parse(withoutYear.group(2)!);
    var date = DateTime(now.year, month, day);
    if (date.isBefore(DateTime(now.year, now.month - 1, now.day))) {
      date = DateTime(now.year + 1, month, day);
    }
    return date;
  }

  /// Loyalty points: dポイント / Ponta / Tポイント / 楽天ポイント.
  ({String brand, int amount})? _detectPoints(List<String> lines) {
    String? brand;
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (line.contains('dポイント') ||
          line.contains('Dポイント') ||
          upper.contains('D POINT') ||
          upper.contains('D-POINT')) {
        brand = 'dポイント';
        break;
      }
      if (line.contains('Ponta') || line.contains('ポンタ')) {
        brand = 'Ponta';
        break;
      }
      if (line.contains('Tポイント') ||
          upper.contains('T-POINT') ||
          upper.contains('T POINT')) {
        brand = 'Tポイント';
        break;
      }
      if (line.contains('楽天ポイント') || upper.contains('RAKUTEN')) {
        brand = '楽天ポイント';
        break;
      }
    }

    ({String brand, int amount})? weakCandidate;

    for (final line in lines) {
      final lower = line.toLowerCase();
      if (!line.contains('ポイント') && !lower.contains('point')) continue;
      if (line.contains('倍') || line.contains('%')) continue;
      if (line.contains('残高') && !line.contains('今回') && !line.contains('獲得')) {
        continue;
      }
      if (line.contains('ポイントカード') &&
          !line.contains('今回') &&
          !line.contains('獲得')) {
        continue;
      }

      final match = RegExp(
            r'(\d{1,3}(?:,\d{3})+|\d+)\s*(?:ポイント|point|pt)',
            caseSensitive: false,
          ).firstMatch(line) ??
          RegExp(
            r'(?:ポイント|point|pt)\s*[:]?\s*(\d{1,3}(?:,\d{3})+|\d+)',
            caseSensitive: false,
          ).firstMatch(line);
      if (match == null) continue;

      final amount = int.tryParse(match.group(1)!.replaceAll(',', ''));
      if (amount == null || amount <= 0 || amount > 1000000) continue;

      final entry = (brand: brand ?? 'ポイント', amount: amount);
      if (line.contains('今回') ||
          line.contains('獲得') ||
          line.contains('加算') ||
          line.contains('付与')) {
        return entry;
      }
      weakCandidate ??= entry;
    }
    return weakCandidate;
  }
}

class _TaxDetection {
  double? tax8;
  double? tax10;
  double? base8;
  double? base10;
}
