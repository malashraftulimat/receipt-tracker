import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'gemini_api_key';

/// Non-web fallback (mobile / desktop / tests). Web uses localStorage directly.
Future<String?> readAiKey() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_key)?.trim();
    return value == null || value.isEmpty ? null : value;
  } catch (_) {
    return null;
  }
}

Future<void> saveAiKey(String key) async {
  final value = key.trim();
  if (value.isEmpty) {
    await clearAiKey();
    return;
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key, value);
}

Future<void> clearAiKey() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  } catch (_) {
    // Storage unavailable; the key is simply not persisted.
  }
}
