import 'dart:io';
import 'dart:typed_data';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';

import 'ocr_service.dart';

/// On-device OCR for Android / iOS.
///
/// The Japanese recogniser also returns Latin text, so a single recogniser
/// covers both "日本語/English" receipts.
class MlKitOcrService implements OcrService {
  MlKitOcrService()
      : _recognizer =
            TextRecognizer(script: TextRecognitionScript.japanese);

  final TextRecognizer _recognizer;

  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    final directory = await getTemporaryDirectory();
    final file = File(
      '${directory.path}/ocr_${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await file.writeAsBytes(bytes, flush: true);

    try {
      final inputImage = InputImage.fromFilePath(file.path);
      final recognized = await _recognizer.processImage(inputImage);

      final lines = <String>[];
      for (final block in recognized.blocks) {
        for (final line in block.lines) {
          if (line.text.trim().isNotEmpty) lines.add(line.text.trim());
        }
      }

      return OcrResult(
        text: recognized.text,
        lines: lines,
        engine: 'mlkit-japanese',
      );
    } finally {
      if (file.existsSync()) {
        await file.delete();
      }
    }
  }

  @override
  Future<void> dispose() => _recognizer.close();
}
