import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/services/local_store.dart';

enum AppMode { supabase, local }

/// Runtime + build-time configuration.
///
/// Credentials can be supplied in three ways:
///  1. Compile time (CI / store builds):
///     `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
///  2. First launch: the in-app "接続設定" screen, persisted in SharedPreferences.
///  3. Local mode (no account, no server): everything is stored in
///     SharedPreferences / localStorage on this device.
class AppConfig {
  const AppConfig._();

  static const String defineUrl = String.fromEnvironment('SUPABASE_URL');
  static const String defineAnonKey =
      String.fromEnvironment('SUPABASE_ANON_KEY');

  static const String prefsUrlKey = 'supabase_url';
  static const String prefsAnonKey = 'supabase_anon_key';
  static const String prefsModeKey = 'backend_mode';

  static const String receiptBucket = 'receipts';
  static const String ocrFunction = 'ocr';
  static const int signedUrlTtlSeconds = 60 * 60 * 24 * 7;

  static String? _url;
  static String? _anonKey;
  static bool _supabaseInitialized = false;
  static AppMode _mode = AppMode.supabase;

  static AppMode get mode => _mode;

  static bool get isLocal => _mode == AppMode.local;

  static String? get supabaseUrl =>
      (_url ?? defineUrl).isEmpty ? null : (_url ?? defineUrl);

  static String? get supabaseAnonKey =>
      (_anonKey ?? defineAnonKey).isEmpty ? null : (_anonKey ?? defineAnonKey);

  static bool get isConfigured => supabaseUrl != null && supabaseAnonKey != null;

  static bool get supabaseInitialized => _supabaseInitialized;

  /// Loads the previously chosen mode and credentials from SharedPreferences
  /// (falling back to dart-defines) and initialises Supabase if possible.
  static Future<bool> bootstrap(SharedPreferences prefs) async {
    _mode = prefs.getString(prefsModeKey) == AppMode.local.name
        ? AppMode.local
        : AppMode.supabase;

    if (_mode == AppMode.local) {
      await LocalStore.instance.seedDefaults();
      return true;
    }

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
    _mode = AppMode.supabase;

    if (persist) {
      await prefs.setString(prefsUrlKey, normalizedUrl);
      await prefs.setString(prefsAnonKey, trimmedKey);
      await prefs.remove(prefsModeKey);
    }
  }

  /// Switches to on-device storage (no account required).
  static Future<void> useLocalMode(SharedPreferences prefs) async {
    _mode = AppMode.local;
    await LocalStore.instance.seedDefaults();
    await prefs.setString(prefsModeKey, AppMode.local.name);
  }

  /// Switches back to Supabase (shows the setup screen if no credentials).
  static Future<void> useSupabaseMode(SharedPreferences prefs) async {
    _mode = AppMode.supabase;
    await prefs.remove(prefsModeKey);
  }

  /// Removes persisted credentials (a restart is required to reconnect).
  static Future<void> clearStoredCredentials(SharedPreferences prefs) async {
    await prefs.remove(prefsUrlKey);
    await prefs.remove(prefsAnonKey);
    await prefs.remove(prefsModeKey);
    await LocalStore.instance.clearAll();
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