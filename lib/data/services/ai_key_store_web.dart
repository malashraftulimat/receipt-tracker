import 'package:web/web.dart' as web;

const String _key = 'gemini_api_key';

Future<String?> readAiKey() async {
  try {
    final value = web.window.localStorage.getItem(_key)?.trim();
    return value == null || value.isEmpty ? null : value;
  } catch (_) {
    // localStorage can be unavailable in strict privacy modes.
    return null;
  }
}

Future<void> saveAiKey(String key) async {
  final value = key.trim();
  try {
    if (value.isEmpty) {
      web.window.localStorage.removeItem(_key);
    } else {
      web.window.localStorage.setItem(_key, value);
    }
  } catch (_) {
    // Storage unavailable; nothing is persisted.
  }
}

Future<void> clearAiKey() async {
  try {
    web.window.localStorage.removeItem(_key);
  } catch (_) {
    // Storage unavailable; nothing to clear.
  }
}
