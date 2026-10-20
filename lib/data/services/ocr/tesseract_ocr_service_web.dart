import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'ocr_service.dart';

/// Client-side OCR for Flutter Web.
///
/// Tesseract.js runs entirely inside the browser (WASM + Web Worker), so no
/// server API, key or Edge Function is required for recognition. The JS bundle
/// is served from the app (`web/tesseract.min.js`); worker/WASM/language data
/// are loaded from the Tesseract.js CDN and cached by the browser.
class TesseractOcrService implements OcrService {
  static Future<void>? _loading;

  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    await _ensureTesseractLoaded();

    final global = _tesseractGlobal;
    if (global == null || global.isUndefinedOrNull) {
      throw const OcrException(
        'ブラウザOCRエンジンを読み込めませんでした。通信環境を確認して再試行してください。',
      );
    }

    final image = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    try {
      final result = await _Tesseract._(global)
          .recognize(image.toJS, 'jpn+eng'.toJS)
          .toDart;

      final text = result.data.text;
      if (text.trim().isEmpty) {
        throw const OcrException(
          '文字を認識できませんでした。明るい場所で、レシート全体が入るように撮影してください。',
        );
      }

      return OcrResult(
        text: text,
        engine: 'tesseract.js-wasm',
        lines: text
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList(growable: false),
      );
    } catch (error) {
      if (error is OcrException) rethrow;
      throw OcrException('ブラウザOCRでエラーが発生しました: $error');
    }
  }

  @override
  Future<void> dispose() async {}

  static Future<void> _ensureTesseractLoaded() {
    if (!_tesseractGlobal.isUndefinedOrNull) return Future<void>.value();
    return _loading ??= _loadScript().whenComplete(() => _loading = null);
  }

  static Future<void> _loadScript() async {
    final existing = web.document.querySelector('script#tesseract-ocr');
    if (existing != null) {
      // Another service instance already started loading it.
      for (var attempt = 0; attempt < 200; attempt++) {
        if (!_tesseractGlobal.isUndefinedOrNull) return;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      throw const OcrException(
        'ブラウザOCRエンジンを読み込めませんでした。通信環境を確認して再試行してください。',
      );
    }

    final completer = Completer<void>();
    final script = web.HTMLScriptElement()
      ..id = 'tesseract-ocr'
      ..type = 'application/javascript'
      ..async = true
      ..src = Uri.base.resolve('tesseract.min.js').toString()
      ..crossOrigin = 'anonymous';

    script.onload = ((JSAny _) {
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    script.onerror = ((JSAny _) {
      script.remove();
      if (!completer.isCompleted) {
        completer.completeError(
          const OcrException(
            'ブラウザOCRエンジンを読み込めませんでした。通信環境を確認して再試行してください。',
          ),
        );
      }
    }).toJS;

    web.document.head!.appendChild(script);
    await completer.future;
  }
}

@JS('Tesseract')
external JSObject? get _tesseractGlobal;

extension type _Tesseract._(JSObject _) implements JSObject {
  external JSPromise<_TesseractResult> recognize(
    JSString image,
    JSString languages,
  );
}

extension type _TesseractResult._(JSObject _) implements JSObject {
  external _TesseractData get data;
}

extension type _TesseractData._(JSObject _) implements JSObject {
  external String get text;
}
