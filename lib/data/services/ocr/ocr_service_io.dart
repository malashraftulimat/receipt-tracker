import 'dart:io';

import 'mlkit_ocr_service.dart';
import 'ocr_service.dart';

/// Android / iOS use ML Kit on-device. Desktop has no OCR engine in the
/// Firebase-only build.
OcrService createOcrService() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MlKitOcrService();
  }
  return const UnavailableOcrService(
    'デスクトップではOCRを利用できません。「手入力で登録」を使ってください。',
  );
}
