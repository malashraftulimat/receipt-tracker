import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';

/// Receipt image storage (`receipts` bucket, `<userId>/<timestamp>.jpg`).
class StorageRepository {
  StorageRepository(this._client);

  final SupabaseClient _client;

  Future<String> uploadReceiptImage(String userId, Uint8List bytes) async {
    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _client.storage.from(AppConfig.receiptBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  Future<String> signedUrl(String path) {
    return _client.storage
        .from(AppConfig.receiptBucket)
        .createSignedUrl(path, AppConfig.signedUrlTtlSeconds);
  }

  Future<void> deleteImage(String path) async {
    await _client.storage.from(AppConfig.receiptBucket).remove(<String>[path]);
  }
}
