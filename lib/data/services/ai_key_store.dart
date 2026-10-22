import 'ai_key_store_stub.dart'
    if (dart.library.js_interop) 'ai_key_store_web.dart' as platform;

/// Browser-local Gemini key storage.
///
/// On web the value is kept in `window.localStorage` only. No key is sent to
/// Firestore, Supabase, GitHub, or any app backend. The AI request sends it
/// directly to Google's Gemini API.
class AiKeyStore {
  const AiKeyStore._();

  static const String storageKey = 'gemini_api_key';

  static Future<String?> read() => platform.readAiKey();
  static Future<void> save(String key) => platform.saveAiKey(key);
  static Future<void> clear() => platform.clearAiKey();
}
