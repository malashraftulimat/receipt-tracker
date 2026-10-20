import 'ocr_service.dart';
import 'tesseract_ocr_service_web.dart';

/// Flutter Web always uses client-side Tesseract.js (WASM + Web Worker).
/// No server function or API key is required.
OcrService createOcrService() => TesseractOcrService();
