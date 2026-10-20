import '../../../core/config/app_config.dart';
import 'ocr_service.dart';
import 'remote_ocr_service.dart';
import 'tesseract_ocr_service_web.dart';

/// Web OCR:
///  * Supabase mode  -> `ocr` Edge Function (Cloud Vision)
///  * Local mode     -> Tesseract.js inside the browser (no server)
OcrService createOcrService() {
  if (AppConfig.isLocal) return TesseractOcrService();
  return RemoteOcrService();
}
