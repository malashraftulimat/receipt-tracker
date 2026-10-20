import 'ocr_service.dart';

/// Fallback for platforms without dart:io or dart:js_interop.
OcrService createOcrService() => const UnavailableOcrService(
      'この環境ではOCRを利用できません。「手入力で登録」を使ってください。',
    );
