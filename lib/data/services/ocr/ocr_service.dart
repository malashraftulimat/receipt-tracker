import 'dart:typed_data';

import 'ocr_service_stub.dart'
    if (dart.library.io) 'ocr_service_io.dart'
    if (dart.library.js_interop) 'ocr_service_web.dart' as platform;

/// Result of a text-recognition call.
class OcrResult {
  const OcrResult({
    required this.text,
    this.engine = 'unknown',
    this.lines = const <String>[],
  });

  final String text;

  /// e.g. `mlkit-japanese` or `google-vision`.
  final String engine;

  final List<String> lines;

  bool get isEmpty => text.trim().isEmpty;
}

/// Platform-agnostic OCR contract.
///
/// * Android / iOS -> on-device ML Kit (Japanese + English script)
/// * Web           -> Tesseract.js WASM inside the browser
abstract class OcrService {
  Future<OcrResult> recognize(Uint8List bytes);

  Future<void> dispose();
}

/// Resolves the implementation for the current platform.
OcrService createOcrService() => platform.createOcrService();

/// Used when OCR cannot run on the current platform (desktop).
class UnavailableOcrService implements OcrService {
  const UnavailableOcrService(this.message);

  final String message;

  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    throw OcrUnavailableException(message);
  }

  @override
  Future<void> dispose() async {}
}

class OcrUnavailableException implements Exception {
  const OcrUnavailableException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OcrException implements Exception {
  const OcrException(this.message);

  final String message;

  @override
  String toString() => message;
}
