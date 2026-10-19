import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Runtime + build-time configuration.
///
/// Credentials can be supplied in two ways:
///  1. Compile time (recommended for CI / app-store builds):
///     `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
///  2. First launch: the in-app "接続設定" screen, persisted in
///     SharedPreferences (handy for a sideloaded APK or a web build).
class AppConfig {
  const AppConfig._();

  static const String defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const String defineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String prefsUrlKey = 'supabase_url';
  static const String prefsAnonKey = 'supabase_anon_key';

  static const String receiptBucket = 'receipts';
  static const String ocrFunction = 'ocr';
  static const int signedUrlTtlSeconds = 60 * 60 * 24 * 7;

  static String? _url;
  static String? _anonKey;
  static bool _supabaseInitialized = false;

  static String? get supabaseUrl =>
      (_url ?? defineUrl).isEmpty ? null : (_url ?? defineUrl);

  static String? get supabaseAnonKey =>
      (_anonKey ?? defineAnonKey).isEmpty ? null : (_anonKey ?? defineAnonKey);

  static bool get isConfigured => supabaseUrl != null && supabaseAnonKey != null;

  static bool get supabaseInitialized => _supabaseInitialized;

  /// Loads credentials from SharedPreferences (falling back to dart-defines)
  /// and initialises Supabase when both values are present.
  static Future<bool> bootstrap(SharedPreferences prefs) async {
    final url = defineUrl.isNotEmpty
        ? defineUrl
        : (prefs.getString(prefsUrlKey) ?? '');
    final anonKey = defineAnonKey.isNotEmpty
        ? defineAnonKey
        : (prefs.getString(prefsAnonKey) ?? '');

    if (url.trim().isEmpty || anonKey.trim().isEmpty) return false;

    try {
      await connect(url: url, anonKey: anonKey, prefs: prefs, persist: false);
      return true;
    } catch (_) {
      // Invalid/expired credentials: fall through to the setup screen.
      return false;
    }
  }

  /// Validates, initialises Supabase (once) and persists the credentials.
  static Future<void> connect({
    required String url,
    required String anonKey,
    required SharedPreferences prefs,
    bool persist = true,
  }) async {
    final normalizedUrl = _normalizeUrl(url);
    final trimmedKey = anonKey.trim();
    if (normalizedUrl.isEmpty) {
      throw const AppConfigException('Supabase URL を入力してください。');
    }
    if (!normalizedUrl.startsWith('http://') &&
        !normalizedUrl.startsWith('https://')) {
      throw const AppConfigException(
        'URL は https://xxxx.supabase.co の形式で入力してください。',
      );
    }
    if (trimmedKey.isEmpty) {
      throw const AppConfigException('anon / publishable key を入力してください。');
    }

    if (!_supabaseInitialized) {
      await Supabase.initialize(url: normalizedUrl, anonKey: trimmedKey);
      _supabaseInitialized = true;
    }

    // Only expose the credentials once the client exists.
    _url = normalizedUrl;
    _anonKey = trimmedKey;

    if (persist) {
      await prefs.setString(prefsUrlKey, normalizedUrl);
      await prefs.setString(prefsAnonKey, trimmedKey);
    }
  }

  /// Removes persisted credentials (a restart is required to reconnect).
  static Future<void> clearStoredCredentials(SharedPreferences prefs) async {
    await prefs.remove(prefsUrlKey);
    await prefs.remove(prefsAnonKey);
  }

  static String _normalizeUrl(String value) {
    var url = value.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/rest/v1')) {
      url = url.substring(0, url.length - '/rest/v1'.length);
    }
    return url;
  }
}

class AppConfigException implements Exception {
  const AppConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}
