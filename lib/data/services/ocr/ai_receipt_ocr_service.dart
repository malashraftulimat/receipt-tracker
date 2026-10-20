import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_ai/firebase_ai.dart';

import '../../../core/config/ai_config.dart';
import '../../../domain/parser/receipt_parser.dart';

/// Firebase AI Logic (Gemini Developer API) receipt extractor.
///
/// The photo is sent only for inference. This service never writes the image
/// to Firestore, local storage or a file.
class AiReceiptOcrService {
  AiReceiptOcrService({FirebaseAI? firebaseAi})
      : _firebaseAi = firebaseAi ?? initializeReceiptAi();

  final FirebaseAI _firebaseAi;

  /// Current Gemini Flash model from the Firebase AI Logic docs.
  static const String modelName = kGeminiReceiptModel;

  static const String _prompt = '''
You extract structured data from Japanese printed receipts and invoices.
Return only JSON matching the response schema.

Rules:
- Read the actual receipt image. Never invent, complete or estimate values.
- If a value is not printed or is unreadable, return null for that field.
- purchased_at must be an ISO-8601 date-time string (YYYY-MM-DDTHH:mm:ss).
  Convert Japanese era dates (令和 / 平成 / 昭和, R / H / S) to the Gregorian year.
  If no time is printed, use T00:00:00.
- Amounts are integer Japanese yen. Remove ¥, commas, spaces and tax labels.
- total is the final tax-included amount actually payable (税込合計 / 合計).
  Do not use change (お釣り), deposit (お預り) or point balances as the total.
- subtotal is the tax-excluded subtotal (小計 / 税抜) when printed.
- tax_8_amount and tax_10_amount are the printed consumption tax amounts
  (消費税 8% / 10%, 内消費税). Do not calculate them when not printed.
- invoice_number is the qualified invoice registration number printed as
  T followed by 13 digits. Normalise a full-width Ｔ to T. Otherwise null.
- items are product lines only (商品明細). Exclude subtotal, tax, totals,
  change, payment method, points, barcode and store address lines.
  quantity defaults to 1 when no quantity is printed.
  unit_price is the per-unit price when printed, otherwise null.
  total_price is the printed line amount including tax if the receipt shows
  tax-included line prices, otherwise the printed line amount.
  tax_rate must be 8 or 10 when the line identifies the rate, otherwise null.
- suggested_category must be exactly one of:
  食費, 外食, 日用品, 光熱費, 交通費, 娯楽, 医療・医薬品, その他.
  Choose the best category from the store and item names. Use null if unclear.
- Do not split one printed line into multiple items and do not merge lines.
''';

  static final Schema _schema = Schema.object(
    properties: <String, Schema>{
      'merchant': Schema.string(
        nullable: true,
        description: 'Store / vendor name exactly as printed.',
      ),
      'purchased_at': Schema.string(
        nullable: true,
        description: 'ISO-8601 date-time in Gregorian calendar.',
      ),
      'total': Schema.integer(
        nullable: true,
        description: 'Final tax-included amount in yen.',
      ),
      'subtotal': Schema.integer(
        nullable: true,
        description: 'Tax-excluded subtotal in yen.',
      ),
      'tax_8_amount': Schema.integer(
        nullable: true,
        description: 'Printed 8% consumption tax in yen.',
      ),
      'tax_10_amount': Schema.integer(
        nullable: true,
        description: 'Printed 10% consumption tax in yen.',
      ),
      'invoice_number': Schema.string(
        nullable: true,
        description: 'Qualified invoice number: T followed by 13 digits.',
      ),
      'suggested_category': Schema.enumString(
        enumValues: <String>[
          '食費',
          '外食',
          '日用品',
          '光熱費',
          '交通費',
          '娯楽',
          '医療・医薬品',
          'その他',
        ],
        nullable: true,
        description: 'Best matching seeded expense category.',
      ),
      'items': Schema.array(
        items: Schema.object(
          properties: <String, Schema>{
            'name': Schema.string(description: 'Printed product name.'),
            'quantity': Schema.integer(
              nullable: true,
              minimum: 1,
              description: 'Quantity, default 1.',
            ),
            'unit_price': Schema.integer(
              nullable: true,
              description: 'Per-unit price in yen when printed.',
            ),
            'total_price': Schema.integer(
              nullable: true,
              description: 'Printed line amount in yen.',
            ),
            'tax_rate': Schema.integer(
              nullable: true,
              description: 'Line tax rate: 8, 10, or null if unknown.',
            ),
          },
          propertyOrdering: <String>[
            'name',
            'quantity',
            'unit_price',
            'total_price',
            'tax_rate',
          ],
          optionalProperties: <String>[
            'quantity',
            'unit_price',
            'total_price',
            'tax_rate',
          ],
        ),
        description: 'Product lines only, in printed order.',
        maxItems: 100,
      ),
    },
    propertyOrdering: <String>[
      'merchant',
      'purchased_at',
      'total',
      'subtotal',
      'tax_8_amount',
      'tax_10_amount',
      'invoice_number',
      'suggested_category',
      'items',
    ],
    optionalProperties: <String>[
      'merchant',
      'purchased_at',
      'total',
      'subtotal',
      'tax_8_amount',
      'tax_10_amount',
      'invoice_number',
      'suggested_category',
      'items',
    ],
  );

  /// Sends [jpegBytes] to Gemini and converts the structured response into the
  /// app's existing [ParsedReceipt] shape.
  Future<ParsedReceipt> recognize(Uint8List jpegBytes) async {
    if (jpegBytes.isEmpty) {
      throw const AiReceiptOcrException('レシート画像が空です。');
    }

    final response = await _generateContent(
      <Content>[
        Content.multi(<Part>[
          const TextPart(
            'Extract this Japanese receipt. Use null for anything unreadable.',
          ),
          InlineDataPart('image/jpeg', jpegBytes),
        ]),
      ],
      generationConfig: GenerationConfig(
        responseMimeType: 'application/json',
        responseSchema: _schema,
        temperature: 0,
      ),
    );

    final text = response.text;
    if (text == null || text.trim().isEmpty) {
      throw const AiReceiptOcrException('AIから読み取り結果が返りませんでした。');
    }

    final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        throw const FormatException('response is not an object');
      }
      json = Map<String, dynamic>.from(decoded);
    } on FormatException {
      throw const AiReceiptOcrException('AIの読み取り結果を解析できませんでした。');
    }

    return _toParsedReceipt(json, text);
  }

  /// Sends the request with retry and model fallback.
  ///
  /// Transient 503/unavailable responses are retried once, then the next
  /// configured Flash model is tried. A 404/unsupported model also moves to the
  /// next model. Configuration and quota errors are surfaced immediately.
  Future<GenerateContentResponse> _generateContent(
    List<Content> content, {
    required GenerationConfig generationConfig,
  }) async {
    final modelNames = <String>{
      kGeminiReceiptModel,
      ...kGeminiReceiptFallbackModels,
    };
    Object? lastError;

    for (final name in modelNames) {
      final model = _firebaseAi.generativeModel(
        model: name,
        systemInstruction: Content.system(_prompt),
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          return await model
              .generateContent(content, generationConfig: generationConfig)
              .timeout(const Duration(seconds: 25));
        } catch (error) {
          lastError = error;
          final mapped = _mapAiError(error);

          if (mapped.kind == AiReceiptFailureKind.unavailable && attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }

          if (mapped.kind == AiReceiptFailureKind.unavailable ||
              mapped.kind == AiReceiptFailureKind.notFound) {
            break; // Try the next Flash model.
          }

          throw mapped;
        }
      }
    }

    throw _mapAiError(lastError ?? Exception('AI service unavailable'));
  }

  static AiReceiptOcrException _mapAiError(Object error) {
    if (error is AiReceiptOcrException) return error;

    final text = error.toString().toLowerCase();
    final AiReceiptFailureKind kind;

    if (error is QuotaExceeded ||
        text.contains('quota') ||
        text.contains('resource_exhausted') ||
        text.contains('429')) {
      kind = AiReceiptFailureKind.quota;
    } else if (error is ServiceApiNotEnabled ||
        error is InvalidApiKey ||
        text.contains('permission_denied') ||
        text.contains('api key') ||
        text.contains('app check') ||
        text.contains('403')) {
      kind = AiReceiptFailureKind.configuration;
    } else if (text.contains('404') ||
        text.contains('not found') ||
        text.contains('not supported') ||
        text.contains('unsupported')) {
      kind = AiReceiptFailureKind.notFound;
    } else if (error is UnsupportedUserLocation ||
        text.contains('503') ||
        text.contains('unavailable') ||
        text.contains('overloaded') ||
        text.contains('deadline') ||
        text.contains('timeout')) {
      kind = AiReceiptFailureKind.unavailable;
    } else {
      kind = AiReceiptFailureKind.other;
    }

    final message = switch (kind) {
      AiReceiptFailureKind.unavailable => 'AIサービスが一時的に利用できません。',
      AiReceiptFailureKind.notFound => '選択したAIモデルを利用できません。',
      AiReceiptFailureKind.quota => 'AIの利用上限に達しました。',
      AiReceiptFailureKind.configuration => 'AIの設定を確認してください。',
      AiReceiptFailureKind.other => 'AIで読み取れませんでした。',
    };
    return AiReceiptOcrException(message, kind: kind, cause: error);
  }

  ParsedReceipt _toParsedReceipt(
    Map<String, dynamic> json,
    String rawText,
  ) {
    final warnings = <String>[];
    final merchant = _string(json['merchant']);
    final purchasedAt = _dateTime(json['purchased_at']);
    final total = _amount(json['total']);
    final subtotal = _amount(json['subtotal']);
    final tax8 = _amount(json['tax_8_amount']);
    final tax10 = _amount(json['tax_10_amount']);
    final invoice = _invoiceNumber(json['invoice_number']);
    final suggestedCategory = _suggestedCategory(json['suggested_category']);
    final items = _items(json['items']);

    if (merchant == null) warnings.add('店舗名を読み取れませんでした');
    if (purchasedAt == null) warnings.add('購入日を読み取れませんでした');
    if (total == null) warnings.add('合計金額を読み取れませんでした');

    final itemsTotal = items.fold<int>(0, (sum, item) => sum + item.totalPrice);
    if (total != null && items.isNotEmpty && (itemsTotal - total).abs() > 1) {
      warnings.add('明細の合計がレシートの合計と一致しません。内容を確認してください');
    }

    final tax8ItemsTotal = items
        .where((item) => item.taxRate == 8)
        .fold<int>(0, (sum, item) => sum + item.totalPrice);
    final tax10ItemsTotal = items
        .where((item) => item.taxRate == 10)
        .fold<int>(0, (sum, item) => sum + item.totalPrice);

    return ParsedReceipt(
      merchant: merchant,
      purchasedAt: purchasedAt,
      totalAmount: total,
      subtotalAmount: subtotal,
      tax8Amount: tax8,
      tax10Amount: tax10,
      tax8ItemsTotal:
          items.any((item) => item.taxRate == 8) ? tax8ItemsTotal : null,
      tax10ItemsTotal:
          items.any((item) => item.taxRate == 10) ? tax10ItemsTotal : null,
      dueDate: null,
      pointBrand: null,
      pointAmount: null,
      barcodeId: invoice,
      suggestedCategory: suggestedCategory,
      items: items,
      rawText: rawText,
      warnings: warnings,
      confidence: <String, double>{
        if (merchant != null) 'merchant': 0.9,
        if (purchasedAt != null) 'date': 0.9,
        if (total != null) 'total': 0.9,
        if (items.isNotEmpty) 'items': 0.85,
        if (suggestedCategory != null) 'category': 0.8,
      },
    );
  }

  static List<ParsedItem> _items(Object? raw) {
    if (raw is! List) return const <ParsedItem>[];
    final result = <ParsedItem>[];
    for (final row in raw) {
      if (row is! Map) continue;
      final map = Map<String, dynamic>.from(row);
      final name = _string(map['name']);
      if (name == null) continue;

      final quantity = _positiveInt(map['quantity']) ?? 1;
      final unitPrice = _amount(map['unit_price']);
      var totalPrice = _amount(map['total_price']);
      totalPrice ??= unitPrice == null ? 0 : unitPrice * quantity;
      if (totalPrice < 0) totalPrice = 0;

      final rate = _taxRate(map['tax_rate']);
      result.add(
        ParsedItem(
          name: name,
          quantity: quantity,
          unitPrice:
              unitPrice ?? (quantity > 0 ? totalPrice ~/ quantity : null),
          totalPrice: totalPrice,
          taxRate: rate,
        ),
      );
      if (result.length >= 100) break;
    }
    return result;
  }

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _amount(Object? value) {
    if (value == null) return null;
    if (value is num) return value.round();
    final normalized = value
        .toString()
        .replaceAll(RegExp(r'[¥￥,\s円]'), '')
        .replaceAll('−', '-')
        .replaceAll('ー', '-');
    if (normalized.isEmpty) return null;
    return int.tryParse(normalized);
  }

  static int? _positiveInt(Object? value) {
    final parsed = _amount(value);
    if (parsed == null || parsed < 1) return null;
    return parsed;
  }

  static int? _taxRate(Object? value) {
    final rate = _amount(value);
    return rate == 8 || rate == 10 ? rate : null;
  }

  static String? _suggestedCategory(Object? value) {
    const allowed = <String>{
      '食費',
      '外食',
      '日用品',
      '光熱費',
      '交通費',
      '娯楽',
      '医療・医薬品',
      'その他',
    };
    final category = _string(value);
    return category != null && allowed.contains(category) ? category : null;
  }

  static String? _invoiceNumber(Object? value) {
    final text = _string(value)?.toUpperCase().replaceAll('Ｔ', 'T');
    if (text == null) return null;
    final match = RegExp(r'T\s*(\d{13})').firstMatch(text);
    return match == null ? null : 'T${match.group(1)}';
  }

  static DateTime? _dateTime(Object? value) {
    final text = _string(value);
    if (text == null) return null;

    final iso = DateTime.tryParse(text);
    if (iso != null) return iso;

    final normalized = text.replaceAll('　', ' ');
    final era = RegExp(
      r'(令和|平成|昭和|R|H|S)\s*(\d{1,2}|元)\s*[年./\-]\s*(\d{1,2})\s*[月./\-]\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(normalized);
    if (era != null) {
      final base = switch (era.group(1)!.toUpperCase()) {
        '令和' => 2018,
        '平成' => 1988,
        '昭和' => 1925,
        'R' => 2018,
        'H' => 1988,
        _ => 1925,
      };
      final eraYear =
          era.group(2) == '元' ? 1 : int.tryParse(era.group(2)!) ?? 0;
      return _safeDate(
        base + eraYear,
        int.tryParse(era.group(3)!) ?? 0,
        int.tryParse(era.group(4)!) ?? 0,
        normalized,
      );
    }

    final full = RegExp(
      r'(20\d{2}|19\d{2})\s*[年./\-]\s*(\d{1,2})\s*[月./\-]\s*(\d{1,2})',
    ).firstMatch(normalized);
    if (full != null) {
      return _safeDate(
        int.tryParse(full.group(1)!) ?? 0,
        int.tryParse(full.group(2)!) ?? 0,
        int.tryParse(full.group(3)!) ?? 0,
        normalized,
      );
    }
    return null;
  }

  static DateTime? _safeDate(int year, int month, int day, String source) {
    if (year < 1990 || year > 2100 || month < 1 || month > 12) return null;
    if (day < 1 || day > 31) return null;
    final date = DateTime(year, month, day);
    if (date.month != month || date.day != day) return null;

    final time = RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?!\d)').firstMatch(source);
    if (time == null) return date;
    final hour = int.tryParse(time.group(1)!) ?? 0;
    final minute = int.tryParse(time.group(2)!) ?? 0;
    if (hour > 23 || minute > 59) return date;
    return DateTime(year, month, day, hour, minute);
  }
}

enum AiReceiptFailureKind {
  unavailable,
  notFound,
  quota,
  configuration,
  other,
}

class AiReceiptOcrException implements Exception {
  const AiReceiptOcrException(
    this.message, {
    this.kind = AiReceiptFailureKind.other,
    this.cause,
  });

  final String message;
  final AiReceiptFailureKind kind;
  final Object? cause;

  bool get isTemporaryServiceIssue =>
      kind == AiReceiptFailureKind.unavailable ||
      kind == AiReceiptFailureKind.notFound;

  @override
  String toString() => message;
}
