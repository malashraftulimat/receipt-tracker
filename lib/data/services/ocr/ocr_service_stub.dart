import 'ocr_service.dart';
import 'remote_ocr_service.dart';

/// Fallback for platforms without `dart:io` or `dart:js_interop`.
OcrService createOcrService() => RemoteOcrService();
