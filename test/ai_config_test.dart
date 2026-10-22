import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/core/config/ai_config.dart';
import 'package:receipt_tracker/core/utils/redaction.dart';
import 'package:receipt_tracker/data/services/ocr/ai_receipt_ocr_service.dart';

void main() {
  group('Gemini configuration', () {
    test('stable model and fallbacks', () {
      expect(kGeminiReceiptModel, 'gemini-3.1-flash-lite');
      expect(kGeminiReceiptFallbackModels, contains('gemini-3.5-flash-lite'));
      expect(kGeminiReceiptFallbackModels, contains('gemini-3.6-flash'));
      expect(kGeminiReceiptFallbackModels, contains('gemini-3.8-flash'));
      expect(kGeminiReceiptFallbackModels,
          isNot(contains('gemini-flash-lite-latest')));
    });

    test('no personal key and no session surfaces as AI key missing', () async {
      // No personal key, so the shared backend is attempted; without a Firebase
      // session the service must still surface the actionable missing-key state.
      final service = AiReceiptOcrService(apiKey: '');
      await expectLater(
        service.recognize(Uint8List.fromList(<int>[1, 2, 3])),
        throwsA(
          isA<AiReceiptOcrException>().having(
            (error) => error.kind,
            'kind',
            AiReceiptFailureKind.missingKey,
          ),
        ),
      );
    });
  });

  group('shared backend contract', () {
    test('429 rate_limited becomes the daily limit message', () {
      final error = AiReceiptOcrService.describeWorkerFailure(
        429,
        '{"error":"rate_limited","message":"Daily limit of 10 AI requests '
            'reached.","limit":10}',
        modelName: 'gemini-3.1-flash-lite',
      );

      expect(error.kind, AiReceiptFailureKind.dailyLimit);
      expect(
        error.message,
        "You've reached your daily limit. Please add a personal Gemini API key "
        'in Settings.',
      );
      expect(error.diagnostics, contains('HTTP 429'));
      expect(error.modelName, 'gemini-3.1-flash-lite');
    });

    test('pass-through Gemini 429 stays a provider quota error', () {
      final error = AiReceiptOcrService.describeWorkerFailure(
        429,
        '{"error":{"code":429,"message":"Quota exceeded",'
            '"status":"RESOURCE_EXHAUSTED"}}',
      );

      expect(error.kind, AiReceiptFailureKind.quota);
    });

    test('backend failures map to actionable kinds', () {
      expect(
        AiReceiptOcrService.describeWorkerFailure(401, '{}').kind,
        AiReceiptFailureKind.configuration,
      );
      expect(
        AiReceiptOcrService.describeWorkerFailure(503, '{}').kind,
        AiReceiptFailureKind.unavailable,
      );
      expect(
        AiReceiptOcrService.describeWorkerFailure(404, '{}').kind,
        AiReceiptFailureKind.notFound,
      );
    });

    test('shared backend URL is https', () {
      expect(kReceiptBackendUrl, startsWith('https://'));
    });
  });

  group('redaction', () {
    test('removes key query parameters and header values', () {
      final redacted = redactSensitiveText(
        'GET https://generativelanguage.googleapis.com/v1beta/models'
        '?key=SECRET123&alt=json\n'
        'x-goog-api-key: fake-header-key-value-1234567890\n'
        'Authorization: Bearer abcdefghijklmnopqrstuvwxyz123456',
      );
      expect(redacted, isNot(contains('SECRET123')));
      expect(redacted, isNot(contains('fake-header-key')));
      expect(redacted, isNot(contains('abcdefghijklmnop')));
      expect(redacted, contains('[REDACTED]'));
    });

    test('removes a known key wherever it appears', () {
      const key = 'fake-api-key-value-1234567890';
      final redacted = redactSensitiveText(
        'request failed with $key attached',
        apiKey: key,
      );
      expect(redacted, isNot(contains(key)));
      expect(redacted, contains('[REDACTED]'));
    });
  });
}
