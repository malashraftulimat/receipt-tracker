import 'package:firebase_core/firebase_core.dart';

import 'ai_secrets.dart';

/// Optional Google AI Studio key override supplied at build time.
///
/// Takes priority over the bundled key in `ai_secrets.dart`:
/// `--dart-define=GEMINI_API_KEY=...`.
const String kGeminiApiKeyOverride = String.fromEnvironment('GEMINI_API_KEY');

/// Gemini Flash model for direct Google AI Studio requests.
///
/// A Flash **Lite** model is the default because a full receipt extraction
/// returns in ~2s on Lite, while thinking Flash models need 30-90s per scan.
/// Retired 1.5 / 2.0 / 2.5 names are intentionally not used. Override with
/// `--dart-define=GEMINI_RECEIPT_MODEL=...` if your API key exposes a different
/// model.
const String kGeminiReceiptModel = String.fromEnvironment(
  'GEMINI_RECEIPT_MODEL',
  defaultValue: 'gemini-3.1-flash-lite',
);

/// Current model fallbacks tried when the primary model is unavailable or not
/// exposed by the API key.
const List<String> kGeminiReceiptFallbackModels = <String>[
  'gemini-flash-lite-latest',
  'gemini-3.6-flash',
  'gemini-3.8-flash',
];

/// Timeout for a single Gemini request attempt.
///
/// Lite models answer in a few seconds, but thinking Flash fallbacks can need
/// ~20-30s, so leave headroom for them.
const Duration kGeminiRequestTimeout = Duration(seconds: 45);

/// Total wall-clock budget shared by every model attempt of one scan, so the
/// UI falls back to on-device OCR instead of waiting on a long outage.
const Duration kGeminiRequestBudget = Duration(seconds: 100);

/// Resolves the direct Google AI Studio API key.
///
/// Order: build-time override → bundled key → Firebase project API key.
String geminiApiKey() {
  final key = geminiApiKeyOrNull();
  if (key == null) {
    throw StateError('No Gemini API key is configured.');
  }
  return key;
}

/// Non-throwing variant of [geminiApiKey].
///
/// Firebase is only consulted when nothing else is configured, so this can be
/// called before `Firebase.initializeApp`.
String? geminiApiKeyOrNull() {
  final override = kGeminiApiKeyOverride.trim();
  if (override.isNotEmpty) return override;

  final bundled = kBundledGeminiApiKey.trim();
  if (bundled.isNotEmpty) return bundled;

  final firebaseKey = _firebaseOptionsOrNull()?.apiKey.trim();
  if (firebaseKey != null && firebaseKey.isNotEmpty) return firebaseKey;
  return null;
}

/// True when the app has a key it can send to the Generative Language API.
bool hasGeminiApiKey() => geminiApiKeyOrNull() != null;

/// Verifies that Firebase was initialized with the apiKey / projectId used when
/// the app falls back to the Firebase project key.
///
/// The bundled / build-time key does not depend on Firebase, so this is a no-op
/// in that case.
void verifyGeminiConfiguration() {
  if (geminiApiKeyOrNull() != null) return;
  final options = _firebaseOptionsOrNull();
  throw StateError(
    'No Gemini API key is configured and FirebaseOptions is missing '
    '${options == null ? '(Firebase not initialized)' : '(empty apiKey)'}.',
  );
}

FirebaseOptions? _firebaseOptionsOrNull() {
  try {
    return Firebase.app().options;
  } catch (_) {
    // Firebase not initialized yet (or no default app).
    return null;
  }
}
