import 'dart:convert';
import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/app_config.dart';
import 'ocr_service.dart';

/// Calls the `ocr` Supabase Edge Function (Google Cloud Vision under the hood).
/// Used on Web / Windows / macOS / Linux where ML Kit is unavailable.
class RemoteOcrService implements OcrService {
  RemoteOcrService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  final SupabaseClient _client;

  @override
  Future<OcrResult> recognize(Uint8List bytes) async {
    final response = await _client.functions.invoke(
      AppConfig.ocrFunction,
      body: <String, dynamic>{
        'image': base64Encode(bytes),
        'language': 'ja',
      },
    );

    final data = response.data;
    if (data is! Map) {
      throw OcrException(
        'サーバーOCRの応答が不正です (status: ${response.status})',
      );
    }

    final error = data['error'];
    if (error != null && error.toString().isNotEmpty) {
      throw OcrException(error.toString());
    }

    final text = (data['text'] as String?) ?? '';
    if (text.trim().isEmpty) {
      throw const OcrException(
        '文字を認識できませんでした。明るい場所で、レシート全体が入るように撮影してください。',
      );
    }

    return OcrResult(
      text: text,
      engine: (data['engine'] as String?) ?? 'remote',
      lines: text
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList(growable: false),
    );
  }

  @override
  Future<void> dispose() async {}
}

class OcrException implements Exception {
  const OcrException(this.message);

  final String message;

  @override
  String toString() => message;
}
