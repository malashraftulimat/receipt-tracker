import 'ocr_service.dart';
import 'remote_ocr_service.dart';

/// Browsers cannot run ML Kit — use the Supabase Edge Function instead.
OcrService createOcrService() => RemoteOcrService();
