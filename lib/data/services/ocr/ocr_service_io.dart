import 'dart:io';

import 'mlkit_ocr_service.dart';
import 'ocr_service.dart';
import 'remote_ocr_service.dart';

/// Android / iOS use ML Kit on-device; desktop falls back to the edge function.
OcrService createOcrService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MlKitOcrService();
  }
  return RemoteOcrService();
}
