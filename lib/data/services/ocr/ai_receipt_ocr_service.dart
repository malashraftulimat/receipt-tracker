import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/ai_config.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/redaction.dart';
import '../../../domain/parser/receipt_parser.dart';
import '../ai_key_store.dart';

/// Receipt extractor backed by Gemini.
///
/// Two transports, chosen per request:
/// * A personal Gemini key saved in Settings is sent **directly** to Google
///   (legacy bring-your-own-key behaviour).
/// * Otherwise the photo is sent to the shared Cloudflare Worker
///   ([kReceiptBackendUrl]) with the Firebase ID token. The Worker verifies the
///   token, enforces the daily quota and adds the server-side API key.
///
/// Works on Flutter Web through the browser HTTP client. The photo is sent
/// only for inference and is never written to Firestore or local storage.
class AiReceiptOcrService {
  AiReceiptOcrService({String? apiKey})
      : _explicitApiKey =
            apiKey?.trim().isNotEmpty == true ? apiKey!.trim() : null;

  /// Optional explicit key (tests / custom callers). Normal app use resolves
  /// the user-saved key first, then the build-time key.
  final String? _explicitApiKey;

  /// User-saved key (explicit argument or browser localStorage).
  ///
  /// Null means "use the shared backend", never a build-time key: the Worker
  /// owns the production key so every client stays inside the daily quota.
  Future<String?> _resolvePersonalApiKey() async {
    final explicit = _explicitApiKey;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final stored = await AiKeyStore.read();
    return stored != null && stored.isNotEmpty ? stored : null;
  }

  /// Current Gemini Flash model from the Google AI Studio model list.
  static const String modelName = kGeminiReceiptModel;

  static const String _prompt = '''
You extract structured data from printed receipts and invoices in any
language or country. Return only JSON matching the response schema.

Rules:
- Read the actual receipt image. Never invent, complete or estimate values.
- If a value is not printed or is unreadable, return null for that field.
- The receipt may be written in any language or script (Arabic, English,
  Japanese, Chinese, Korean, Spanish, Hindi, etc.). Keep merchant and item
  names exactly as printed, in their original language and script. Do not
  translate, transliterate, romanise or otherwise rewrite them.
- currency is the ISO-4217 code actually used on the receipt (JPY, USD, EUR,
  SAR, AED, EGP, GBP, CNY, KRW, INR, etc.). Infer it from the currency symbol,
  code, or the store's country. Use null only when it cannot be determined.
- purchased_at must be an ISO-8601 date-time string (YYYY-MM-DDTHH:mm:ss).
  Keep the printed calendar date. Only when the receipt prints a Japanese era
  date (令和 / 平成 / 昭和, R / H / S) convert it to the Gregorian year.
  If no time is printed, use T00:00:00.
- Amounts may contain decimals. Return them as JSON numbers (not strings) and
  do not round or rescale them. Remove currency symbols, thousands separators,
  spaces and tax labels from the numeric value.
- total is the final tax-included amount actually payable, in the receipt's
  currency. Do not use change, cash tendered, deposit or point balances as the
  total.
- subtotal is the tax-excluded subtotal when printed.
- tax_8_amount and tax_10_amount are optional and Japanese-specific: fill them
  only when a Japanese receipt prints the 8% / 10% consumption tax amount.
  For non-Japanese receipts, or when no tax amount is printed, return null.
  Never calculate them.
- invoice_number is the Japanese qualified invoice registration number printed
  as 登録番号 / T followed by 13 digits. Never use 伝票 No. for this field.
  Normalise a full-width Ｔ to T. Otherwise null.
- For Japanese receipts, do not treat address, phone (TEL / 〒), tax lines
  (消費税 / 対象税), subtotal, total, payment or change lines as items. The
  store is the header merchant, not 会計日, a date, or an address.
- tax_8_base and tax_10_base are the printed tax-excluded taxable subtotals
  for each rate (for example 8%対象税 (税抜)). Never estimate them.
- items are the printed purchase lines, in printed order. Exclude subtotal,
  tax summary, totals, change, payment method, points, barcode and store
  address lines.
  Additional fees and charges (チャージ料, サービス料, 席料, お通し代, 深夜料金,
  GW料金, 休日料金, 手数料, 配送料, 包み料, corkage, service charge, cover
  charge, surcharge) ARE items: one line each, named exactly as printed,
  quantity 1, and the printed charge as total_price.
  Discounts already applied to this purchase (割引, 値引き, クーポン割引,
  お食事券利用) are items too, with a NEGATIVE total_price equal to the
  printed reduction, so that the sum of item total_price values matches the
  printed tax-included total.
  Only fees and discounts that actually appear on this receipt become items;
  never invent one.
  quantity defaults to 1 when no quantity is printed.
  unit_price is the per-unit price when printed, otherwise null.
  total_price is the printed line amount including tax if the receipt shows
  tax-included line prices, otherwise the printed line amount.
  tax_rate is optional and Japanese-specific: use 8 or 10 only when the line
  identifies that rate, otherwise null.
- coupon is a coupon, discount ticket or promotional voucher printed on this
  receipt (クーポン, 割引券, お食事券, 回数券, 特典券, coupon, voucher). Extract
  the one usable on a future visit; when several are printed prefer the
  soonest valid_until, then the largest discount.
  name is the coupon title exactly as printed.
  valid_from / valid_until are the printed validity dates as YYYY-MM-DD;
  valid_from is null when the coupon is valid immediately, valid_until is
  null when no expiry is printed. Convert Japanese era dates to Gregorian.
  discount_amount_or_percent is the printed value with its unit text, such as
  "10%" or "500", or null when none is specified. Never calculate it.
  Return null for coupon when no coupon is printed. A coupon already applied
  to this purchase belongs in items as a negative line, not in coupon.
- suggested_category must be exactly one of the Japanese seeded categories:
  食費, 外食, 日用品, 光熱費, 交通費, 娯楽, 医療・医薬品, その他.
  Choose the best category from the store and item names, regardless of the
  receipt language. Use null if unclear.
- Do not split one printed line into multiple items and do not merge lines.
''';

  static final Schema _schema = Schema.object(
    properties: <String, Schema>{
      'merchant': Schema.string(
        nullable: true,
        description: 'Store / vendor name exactly as printed, any language.',
      ),
      'currency': Schema.string(
        nullable: true,
        description: 'ISO-4217 currency code such as JPY, USD, SAR or EUR.',
      ),
      'purchased_at': Schema.string(
        nullable: true,
        description: 'ISO-8601 date-time in Gregorian calendar.',
      ),
      'total': Schema.number(
        nullable: true,
        description:
            'Final tax-included amount in the receipt currency (decimals ok).',
      ),
      'subtotal': Schema.number(
        nullable: true,
        description: 'Tax-excluded subtotal when printed (decimals ok).',
      ),
      'tax_8_amount': Schema.number(
        nullable: true,
        description: 'Optional printed 8% Japanese consumption tax amount.',
      ),
      'tax_10_amount': Schema.number(
        nullable: true,
        description: 'Optional printed 10% Japanese consumption tax amount.',
      ),
      'tax_8_base': Schema.number(
        nullable: true,
        description: 'Optional printed tax-excluded 8% taxable subtotal.',
      ),
      'tax_10_base': Schema.number(
        nullable: true,
        description: 'Optional printed tax-excluded 10% taxable subtotal.',
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
      'coupon': Schema.object(
        nullable: true,
        description:
            'Coupon / voucher printed for future use; null when none exists.',
        properties: <String, Schema>{
          'name': Schema.string(
            description: 'Coupon title exactly as printed.',
          ),
          'valid_from': Schema.string(
            nullable: true,
            description:
                'Start date YYYY-MM-DD, or null when immediately active.',
          ),
          'valid_until': Schema.string(
            nullable: true,
            description: 'Expiry date YYYY-MM-DD, or null when not printed.',
          ),
          'discount_amount_or_percent': Schema.string(
            nullable: true,
            description:
                'Printed discount value such as "10%" or "500"; null when '
                'not specified.',
          ),
        },
        requiredProperties: <String>[
          'name',
          'valid_from',
          'valid_until',
          'discount_amount_or_percent',
        ],
      ),
      'items': Schema.array(
        description:
            'Purchase, fee and applied-discount lines, in printed order.',
        items: Schema.object(
          properties: <String, Schema>{
            'name': Schema.string(description: 'Printed product name.'),
            'quantity': Schema.integer(
              nullable: true,
              description: 'Quantity, default 1.',
            ),
            'unit_price': Schema.number(
              nullable: true,
              description: 'Per-unit price in the receipt currency.',
            ),
            'total_price': Schema.number(
              nullable: true,
              description: 'Printed line amount in the receipt currency.',
            ),
            'tax_rate': Schema.integer(
              nullable: true,
              description:
                  'Optional Japanese rate: 8, 10, or null when not printed.',
            ),
          },
          requiredProperties: <String>[
            'name',
            'quantity',
            'unit_price',
            'total_price',
            'tax_rate',
          ],
        ),
      ),
    },
    requiredProperties: <String>[
      'merchant',
      'currency',
      'purchased_at',
      'total',
      'subtotal',
      'tax_8_amount',
      'tax_10_amount',
      'tax_8_base',
      'tax_10_base',
      'invoice_number',
      'suggested_category',
      'coupon',
      'items',
    ],
    description: 'Language- and currency-agnostic receipt extraction.',
  );

  /// Sends [jpegBytes] to Gemini and converts the structured response into the
  /// app's existing [ParsedReceipt] shape.
  Future<ParsedReceipt> recognize(Uint8List jpegBytes) async {
    if (jpegBytes.isEmpty) {
      throw const AiReceiptOcrException('レシート画像が空です。');
    }

    final content = <Content>[
      Content.multi(<Part>[
        TextPart(
          'Extract this receipt in its original language and currency. '
          'Use null for anything unreadable.',
        ),
        DataPart('image/jpeg', jpegBytes),
      ]),
    ];
    final generationConfig = GenerationConfig(
      responseMimeType: 'application/json',
      responseSchema: _schema,
      temperature: 0,
    );

    // Personal key -> Google directly; otherwise the shared Worker.
    final apiKey = await _resolvePersonalApiKey();
    final text = apiKey != null
        ? (await _generateContent(
            content,
            generationConfig: generationConfig,
            apiKey: apiKey,
          ))
            .text
        : await _generateViaWorker(
            content,
            generationConfig: generationConfig,
          );
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

  /// Sends a tiny request to verify that [apiKey] can call the Gemini API.
  ///
  /// The key is not stored or logged. The returned message is safe to show.
  Future<AiKeyTestResult> testKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) {
      return const AiKeyTestResult(
        ok: false,
        kind: AiReceiptFailureKind.missingKey,
        message: 'AI key missing',
      );
    }

    try {
      final model = GenerativeModel(
        model: kGeminiReceiptModel,
        apiKey: key,
      );
      final response = await model.generateContent(<Content>[
        Content.text('Reply with OK only.')
      ]).timeout(const Duration(seconds: 20));
      if ((response.text ?? '').trim().isEmpty) {
        return const AiKeyTestResult(
          ok: false,
          kind: AiReceiptFailureKind.other,
          message: 'AI returned an empty response',
        );
      }
      return const AiKeyTestResult(ok: true, message: 'AI key works');
    } catch (error) {
      final mapped = _mapAiError(
        error,
        modelName: kGeminiReceiptModel,
        apiKey: key,
      );
      return AiKeyTestResult(
        ok: false,
        kind: mapped.kind,
        message: mapped.message,
      );
    }
  }

  /// Message shown when the Worker's daily per-user quota is exhausted.
  static const String dailyLimitMessage =
      "You've reached your daily limit. Please add a personal Gemini API key "
      'in Settings.';

  /// Sends the scan to the shared Cloudflare Worker.
  ///
  /// Applies the same retry / model-fallback budget as the direct path: a
  /// transient 503 is retried once, then the next Flash model is tried.
  Future<String> _generateViaWorker(
    List<Content> content, {
    required GenerationConfig generationConfig,
  }) async {
    final idToken = await _firebaseIdToken();
    final modelNames = <String>{
      kGeminiReceiptModel,
      ...kGeminiReceiptFallbackModels,
    };
    final stopwatch = Stopwatch()..start();
    AiReceiptOcrException? lastError;

    for (final name in modelNames) {
      for (var attempt = 0; attempt < 2; attempt++) {
        if (stopwatch.elapsed > kGeminiRequestBudget) {
          throw lastError ??
              const AiReceiptOcrException(
                'AIサービスが一時的に利用できません。',
                kind: AiReceiptFailureKind.unavailable,
              );
        }
        try {
          return await _postToWorker(
            model: name,
            idToken: idToken,
            content: content,
            generationConfig: generationConfig,
            stopwatch: stopwatch,
          );
        } on AiReceiptOcrException catch (error) {
          lastError = error;
          debugPrint(
            '[AiReceiptOcrService] backend model=$name '
            'attempt=${attempt + 1} kind=${error.kind.name} '
            'message=${error.message} diagnostics=${error.diagnostics}',
          );

          if (error.kind == AiReceiptFailureKind.unavailable && attempt == 0) {
            await Future<void>.delayed(const Duration(milliseconds: 800));
            continue;
          }
          if (error.kind == AiReceiptFailureKind.unavailable ||
              error.kind == AiReceiptFailureKind.notFound) {
            break; // Try the next Flash model.
          }
          rethrow;
        }
      }
    }

    throw lastError ??
        const AiReceiptOcrException(
          'AIサービスが一時的に利用できません。',
          kind: AiReceiptFailureKind.unavailable,
        );
  }

  /// One POST to the Worker. Returns the raw JSON text of the first candidate.
  Future<String> _postToWorker({
    required String model,
    required String idToken,
    required List<Content> content,
    required GenerationConfig generationConfig,
    required Stopwatch stopwatch,
  }) async {
    final remaining = kGeminiRequestBudget - stopwatch.elapsed;
    final timeout = remaining < kGeminiRequestTimeout
        ? remaining
        : kGeminiRequestTimeout;

    final body = <String, Object?>{
      'model': model,
      'contents': content.map((part) => part.toJson()).toList(),
      'systemInstruction': Content.system(_prompt).toJson(),
      'generationConfig': generationConfig.toJson(),
    };

    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(kReceiptBackendUrl),
            headers: <String, String>{
              'Authorization': 'Bearer $idToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw AiReceiptOcrException(
        'AIサービスが一時的に利用できません。',
        kind: AiReceiptFailureKind.unavailable,
        modelName: model,
        diagnostics: 'backend request timed out after ${timeout.inSeconds}s',
      );
    } catch (error) {
      throw AiReceiptOcrException(
        'AIサービスが一時的に利用できません。',
        kind: AiReceiptFailureKind.unavailable,
        cause: error,
        modelName: model,
        diagnostics: redactSensitiveText(error.toString()),
      );
    }

    final raw = utf8.decode(response.bodyBytes, allowMalformed: true);
    if (response.statusCode == 200) {
      return _textFromWorkerResponse(raw, model);
    }
    throw describeWorkerFailure(
      response.statusCode,
      raw,
      modelName: model,
    );
  }

  /// Firebase ID token for the signed-in user, used as the Worker's bearer.
  ///
  /// Missing auth is surfaced as [AiReceiptFailureKind.missingKey] so the scan
  /// screen offers the same actionable settings card as before.
  Future<String> _firebaseIdToken() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw const AiReceiptOcrException(
          'AI key missing',
          kind: AiReceiptFailureKind.missingKey,
        );
      }
      final token = await user.getIdToken();
      if (token == null || token.isEmpty) {
        throw const AiReceiptOcrException(
          'AI key missing',
          kind: AiReceiptFailureKind.missingKey,
        );
      }
      return token;
    } on AiReceiptOcrException {
      rethrow;
    } catch (error) {
      // No Firebase app / signed-out session / refresh error: the user can
      // still add a personal key, so point them at Settings.
      throw AiReceiptOcrException(
        'AI key missing',
        kind: AiReceiptFailureKind.missingKey,
        cause: error,
        diagnostics: redactSensitiveText(error.toString()),
      );
    }
  }

  String _textFromWorkerResponse(String raw, String model) {
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      throw AiReceiptOcrException(
        'AIの読み取り結果を解析できませんでした。',
        kind: AiReceiptFailureKind.other,
        modelName: model,
        diagnostics: redactSensitiveText(raw),
      );
    }

    final text = _collectText(decoded);
    if (text == null || text.trim().isEmpty) {
      throw AiReceiptOcrException(
        'AIから読み取り結果が返りませんでした。',
        kind: AiReceiptFailureKind.other,
        modelName: model,
        diagnostics: redactSensitiveText(raw),
      );
    }
    return text;
  }

  static String? _collectText(Object? decoded) {
    if (decoded is! Map) return null;
    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final first = candidates.first;
    if (first is! Map) return null;
    final content = first['content'];
    if (content is! Map) return null;
    final parts = content['parts'];
    if (parts is! List) return null;

    final buffer = StringBuffer();
    for (final part in parts) {
      if (part is Map) {
        final value = part['text'];
        if (value is String) buffer.write(value);
      }
    }
    final text = buffer.toString();
    return text.isEmpty ? null : text;
  }

  /// Maps a Worker HTTP failure to a typed, user-safe exception.
  ///
  /// A 429 with the Worker's own `rate_limited` code becomes
  /// [AiReceiptFailureKind.dailyLimit] with [dailyLimitMessage]; a 429 that was
  /// passed through from Gemini stays a quota error.
  @visibleForTesting
  static AiReceiptOcrException describeWorkerFailure(
    int status,
    String body, {
    String? modelName,
  }) {
    final decoded = _tryDecode(body);
    final errorField = decoded is Map ? decoded['error'] : null;
    final workerCode = errorField is String ? errorField : null;
    final serverMessage = _serverErrorMessage(decoded);
    final diagnostics = redactSensitiveText(
      'HTTP $status${serverMessage == null ? '' : ' · $serverMessage'}',
    );

    // The Worker's own quota (`{"error":"rate_limited"}`) is the actionable
    // daily limit. A 429 carrying a Gemini error object is provider quota.
    if (status == 429 &&
        (workerCode == 'rate_limited' || errorField == null)) {
      return AiReceiptOcrException(
        dailyLimitMessage,
        kind: AiReceiptFailureKind.dailyLimit,
        modelName: modelName,
        diagnostics: diagnostics,
      );
    }

    final AiReceiptFailureKind kind;
    final String message;
    switch (status) {
      case 401:
      case 403:
        kind = AiReceiptFailureKind.configuration;
        message = 'ログインの有効期限が切れました。再度ログインしてください。';
      case 404:
        kind = AiReceiptFailureKind.notFound;
        message = '選択したAIモデルを利用できません。';
      case 429:
        kind = AiReceiptFailureKind.quota;
        message = 'AIの利用上限に達しました。';
      case 500:
      case 502:
      case 503:
      case 504:
        kind = AiReceiptFailureKind.unavailable;
        message = 'AIサービスが一時的に利用できません。';
      default:
        kind = status >= 500
            ? AiReceiptFailureKind.unavailable
            : AiReceiptFailureKind.other;
        message = 'AIで読み取れませんでした。';
    }

    return AiReceiptOcrException(
      message,
      kind: kind,
      modelName: modelName,
      diagnostics: diagnostics,
    );
  }

  /// Human readable message from the Worker or a passthrough Gemini error.
  static String? _serverErrorMessage(Object? decoded) {
    if (decoded is! Map) return null;
    final error = decoded['error'];
    if (error is String) {
      final message = decoded['message'];
      return message is String ? message : error;
    }
    if (error is Map) {
      final message = error['message'];
      if (message is String) return message;
      final status = error['status'];
      return status is String ? status : null;
    }
    return null;
  }

  static Object? _tryDecode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }

  /// Sends the request with retry and model fallback.
  ///
  /// Transient 503/unavailable responses are retried once, then the next
  /// configured Flash model is tried. A 404/unsupported model also moves to the
  /// next model. Configuration and quota errors are surfaced immediately.
  Future<GenerateContentResponse> _generateContent(
    List<Content> content, {
    required GenerationConfig generationConfig,
    required String apiKey,
  }) async {
    final modelNames = <String>{
      kGeminiReceiptModel,
      ...kGeminiReceiptFallbackModels,
    };
    final stopwatch = Stopwatch()..start();
    Object? lastError;
    String? lastModelName;

    for (final name in modelNames) {
      final model = GenerativeModel(
        model: name,
        apiKey: apiKey,
        systemInstruction: Content.system(_prompt),
      );

      for (var attempt = 0; attempt < 2; attempt++) {
        if (stopwatch.elapsed > kGeminiRequestBudget) {
          throw _mapAiError(
            lastError ?? TimeoutException('AI request budget exceeded'),
            modelName: lastModelName,
            apiKey: apiKey,
          );
        }
        try {
          return await model
              .generateContent(content, generationConfig: generationConfig)
              .timeout(kGeminiRequestTimeout);
        } catch (error) {
          lastError = error;
          lastModelName = name;
          final mapped = _mapAiError(error, modelName: name, apiKey: apiKey);
          debugPrint(
            '[AiReceiptOcrService] model=$name attempt=${attempt + 1} '
            'runtimeType=${error.runtimeType} kind=${mapped.kind.name} '
            'message=${mapped.message} raw=${_safeError(error, apiKey)}',
          );

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

    throw _mapAiError(
      lastError ?? Exception('AI service unavailable'),
      modelName: lastModelName,
      apiKey: apiKey,
    );
  }

  AiReceiptOcrException _mapAiError(
    Object error, {
    String? modelName,
    String? apiKey,
  }) {
    if (error is AiReceiptOcrException) {
      return AiReceiptOcrException(
        error.message,
        kind: error.kind,
        cause: error.cause ?? error,
        diagnostics: error.diagnostics ?? _safeError(error, apiKey),
        modelName: modelName ?? error.modelName,
      );
    }

    final text = error.toString().toLowerCase();
    final AiReceiptFailureKind kind;

    if (text.contains('quota') ||
        text.contains('resource_exhausted') ||
        text.contains('429')) {
      kind = AiReceiptFailureKind.quota;
    } else if (error is InvalidApiKey ||
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
      AiReceiptFailureKind.dailyLimit => dailyLimitMessage,
      AiReceiptFailureKind.configuration => 'AIの設定を確認してください。',
      AiReceiptFailureKind.missingKey => 'AI key missing',
      AiReceiptFailureKind.other => 'AIで読み取れませんでした。',
    };
    return AiReceiptOcrException(
      message,
      kind: kind,
      cause: error,
      diagnostics: _safeError(error, apiKey),
      modelName: modelName,
    );
  }

  /// Error text that is safe to log or show in the diagnostics box.
  String _safeError(Object error, [String? apiKey]) =>
      redactSensitiveText(error.toString(), apiKey: apiKey);

  ParsedReceipt _toParsedReceipt(
    Map<String, dynamic> json,
    String rawText,
  ) {
    final warnings = <String>[];
    final merchant = _string(json['merchant']);
    final currency = _currency(json['currency']);
    final purchasedAt = _dateTime(json['purchased_at']);
    final total = _amount(json['total']);
    final subtotal = _amount(json['subtotal']);
    final tax8 = _amount(json['tax_8_amount']);
    final tax10 = _amount(json['tax_10_amount']);
    final tax8Base = _amount(json['tax_8_base']);
    final tax10Base = _amount(json['tax_10_base']);
    final invoice = _invoiceNumber(json['invoice_number']);
    final suggestedCategory = _suggestedCategory(json['suggested_category']);
    final coupon = parseCoupon(json['coupon']);
    final items = _items(json['items']);

    if (merchant == null) warnings.add('店舗名を読み取れませんでした');
    if (purchasedAt == null) warnings.add('購入日を読み取れませんでした');
    if (total == null) warnings.add('合計金額を読み取れませんでした');

    final itemsTotal =
        items.fold<double>(0, (sum, item) => sum + item.totalPrice);
    if (total != null &&
        items.isNotEmpty &&
        (itemsTotal - total).abs() > 0.011) {
      warnings.add('明細の合計がレシートの合計と一致しません。内容を確認してください');
    }

    final tax8ItemsTotal = items
        .where((item) => item.taxRate == 8)
        .fold<double>(0, (sum, item) => sum + item.totalPrice);
    final tax10ItemsTotal = items
        .where((item) => item.taxRate == 10)
        .fold<double>(0, (sum, item) => sum + item.totalPrice);

    return ParsedReceipt(
      merchant: merchant,
      currency: currency,
      purchasedAt: purchasedAt,
      totalAmount: total,
      subtotalAmount: subtotal,
      tax8Amount: tax8,
      tax10Amount: tax10,
      tax8Base: tax8Base,
      tax10Base: tax10Base,
      tax8ItemsTotal:
          items.any((item) => item.taxRate == 8) ? tax8ItemsTotal : null,
      tax10ItemsTotal:
          items.any((item) => item.taxRate == 10) ? tax10ItemsTotal : null,
      dueDate: null,
      pointBrand: null,
      pointAmount: null,
      barcodeId: invoice,
      suggestedCategory: suggestedCategory,
      coupon: coupon,
      items: items,
      rawText: rawText,
      warnings: warnings,
      confidence: <String, double>{
        if (merchant != null) 'merchant': 0.9,
        if (purchasedAt != null) 'date': 0.9,
        if (total != null) 'total': 0.9,
        if (items.isNotEmpty) 'items': 0.85,
        if (suggestedCategory != null) 'category': 0.8,
        if (coupon != null) 'coupon': 0.8,
      },
    );
  }

  /// Parses the schema's `coupon` object.
  ///
  /// Returns null when the model emitted no coupon or no usable name. Dates are
  /// printed as `YYYY-MM-DD`; era dates are normalised through [_dateTime].
  @visibleForTesting
  static ParsedCoupon? parseCoupon(Object? value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
    final name = _string(map['name']);
    if (name == null) return null;

    final validFrom = _dateTime(map['valid_from']);
    final validUntil = _dateTime(map['valid_until']);
    final discount = _string(map['discount_amount_or_percent']);

    return ParsedCoupon(
      name: name,
      validFrom: validFrom,
      validUntil: validUntil,
      discountAmountOrPercent: discount,
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
      // Fees are positive lines; applied discounts are negative lines, so the
      // sign is kept and the item sum can match the printed total.

      final rate = _taxRate(map['tax_rate']);
      result.add(
        ParsedItem(
          name: name,
          quantity: quantity,
          unitPrice: unitPrice ?? (quantity > 0 ? totalPrice / quantity : null),
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

  static double? _amount(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return parseAmountInput(
      value.toString().replaceAll('−', '-').replaceAll('ー', '-'),
    );
  }

  static int? _positiveInt(Object? value) {
    final parsed = _amount(value);
    if (parsed == null || parsed < 1) return null;
    return parsed.round();
  }

  static int? _taxRate(Object? value) {
    final rate = _amount(value);
    if (rate == null) return null;
    final rounded = rate.round();
    return rounded == 8 || rounded == 10 ? rounded : null;
  }

  static String? _currency(Object? value) {
    final text = _string(value)?.toUpperCase();
    if (text == null) return null;
    final match = RegExp(r'\b([A-Z]{3})\b').firstMatch(text);
    return match?.group(1) ?? (text.length == 3 ? text : null);
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

    // Era dates are only converted when the printed date actually contains a
    // Japanese era marker; otherwise the printed Gregorian date is used as-is.
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

class AiKeyTestResult {
  const AiKeyTestResult({
    required this.ok,
    this.kind,
    this.message = '',
  });

  final bool ok;
  final AiReceiptFailureKind? kind;
  final String message;
}

enum AiReceiptFailureKind {
  unavailable,
  notFound,
  quota,
  dailyLimit,
  configuration,
  missingKey,
  other,
}

class AiReceiptOcrException implements Exception {
  const AiReceiptOcrException(
    this.message, {
    this.kind = AiReceiptFailureKind.other,
    this.cause,
    this.diagnostics,
    this.modelName,
  });

  final String message;
  final AiReceiptFailureKind kind;
  final Object? cause;

  /// Sanitised error text safe for logs and the "AI error details" box.
  final String? diagnostics;
  final String? modelName;

  bool get isTemporaryServiceIssue =>
      kind == AiReceiptFailureKind.unavailable ||
      kind == AiReceiptFailureKind.notFound;

  @override
  String toString() => message;
}
