import 'dart:typed_data';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/app_config.dart';
import '../services/local_store.dart';

/// Receipt image storage.
///
/// Supabase: `receipts` bucket, `<userId>/<timestamp>.jpg`.
/// Local mode: data URI in SharedPreferences (or memory for large files).
class StorageRepository {
  StorageRepository([this._client]);

  final SupabaseClient? _client;

  SupabaseClient get _supabase => _client ?? Supabase.instance.client;

  Future<String> uploadReceiptImage(String userId, Uint8List bytes) async {
    if (AppConfig.isLocal) return LocalStore.instance.saveImage(bytes);

    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}.jpg';
    await _supabase.storage.from(AppConfig.receiptBucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );
    return path;
  }

  /// Returns a URL the UI can display.
  Future<String> signedUrl(String path) async {
    if (AppConfig.isLocal) {
      return await LocalStore.instance.resolveImage(path) ?? path;
    }
    return _supabase.storage
        .from(AppConfig.receiptBucket)
        .createSignedUrl(path, AppConfig.signedUrlTtlSeconds);
  }

  Future<void> deleteImage(String path) async {
    if (AppConfig.isLocal) {
      await LocalStore.instance.deleteImage(path);
      return;
    }
    await _supabase.storage
        .from(AppConfig.receiptBucket)
        .remove(<String>[path]);
  }
}