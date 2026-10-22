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

    test('a missing build key surfaces as AI key missing', () async {
      // If the test runner supplied GEMINI_API_KEY, there is nothing to test.
      if (hasGeminiApiKey()) return;

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
