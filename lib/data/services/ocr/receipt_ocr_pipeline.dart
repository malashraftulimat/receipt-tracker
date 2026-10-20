import 'dart:typed_data';

import '../../../domain/parser/receipt_parser.dart';
import 'ai_receipt_ocr_service.dart';
import 'ocr_service.dart';

enum ReceiptExtractionEngine { gemini, onDeviceFallback }

/// Result of the AI-first extraction with an automatic OCR fallback.
class ReceiptExtractionResult {
  const ReceiptExtractionResult({
    required this.parsed,
    required this.engine,
    this.aiError,
  });

  final ParsedReceipt parsed;
  final ReceiptExtractionEngine engine;

  /// Why the AI call failed before the local/browser OCR fallback succeeded.
  final Object? aiError;

  bool get usedFallback => engine == ReceiptExtractionEngine.onDeviceFallback;

  /// Typed failure details for diagnostics on the scan screen.
  AiReceiptOcrException? get aiFailure => aiError is AiReceiptOcrException
      ? aiError as AiReceiptOcrException
      : null;

  bool get aiServiceUnavailable => aiFailure?.isTemporaryServiceIssue ?? false;
}

/// Gemini (Firebase AI Logic) first, ML Kit / Tesseract.js on error, offline
/// or quota exhaustion. The image is passed by reference and never stored.
class ReceiptOcrPipeline {
  const ReceiptOcrPipeline({
    required AiReceiptOcrService ai,
    required OcrService fallback,
    required ReceiptParser parser,
  })  : _ai = ai,
        _fallback = fallback,
        _parser = parser;

  final AiReceiptOcrService _ai;
  final OcrService _fallback;
  final ReceiptParser _parser;

  Future<ReceiptExtractionResult> recognize(
    Uint8List bytes, {
    String? barcodeId,
    void Function(Object? aiError)? onFallback,
  }) async {
    Object? aiError;
    try {
      final parsed = await _ai.recognize(bytes);
      return ReceiptExtractionResult(
        parsed: parsed,
        engine: ReceiptExtractionEngine.gemini,
      );
    } catch (error) {
      aiError = error is AiReceiptOcrException
          ? error
          : AiReceiptOcrException(
              'AIで読み取れませんでした。',
              cause: error,
            );
    }

    onFallback?.call(aiError);
    try {
      final fallback = await _fallback.recognize(bytes);
      final parsed = _parser.parse(
        fallback.text,
        scannedBarcode: barcodeId,
      );
      return ReceiptExtractionResult(
        parsed: parsed,
        engine: ReceiptExtractionEngine.onDeviceFallback,
        aiError: aiError,
      );
    } catch (fallbackError) {
      throw ReceiptScanException(
        'AIと端末内OCRの両方で読み取れませんでした。'
        '通信環境を確認するか、手入力で登録してください。',
        aiError: aiError,
        fallbackError: fallbackError,
      );
    }
  }
}

class ReceiptScanException implements Exception {
  const ReceiptScanException(
    this.message, {
    this.aiError,
    this.fallbackError,
  });

  final String message;
  final Object? aiError;
  final Object? fallbackError;

  @override
  String toString() => message;
}
