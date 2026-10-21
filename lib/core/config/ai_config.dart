import 'package:firebase_core/firebase_core.dart';

/// Optional Google AI Studio key override.
///
/// When empty, the app uses the existing Firebase project API key from
/// `FirebaseOptions` (the same key already shipped with the web build).
const String kGeminiApiKeyOverride = String.fromEnvironment('GEMINI_API_KEY');

/// Current Gemini Flash model for direct Google AI Studio requests.
///
/// The retired 1.5 / 2.0 names are intentionally not used. Override with
/// `--dart-define=GEMINI_RECEIPT_MODEL=...` if your API key exposes a different
/// Flash model.
const String kGeminiReceiptModel = String.fromEnvironment(
  'GEMINI_RECEIPT_MODEL',
  defaultValue: 'gemini-3.8-flash',
);

/// Current model fallbacks tried when the primary model is unavailable or not
/// exposed by the API key.
const List<String> kGeminiReceiptFallbackModels = <String>[
  'gemini-3.7-flash',
  'gemini-3.5-flash',
];

/// Resolves the direct Google AI Studio API key.
String geminiApiKey() {
  final override = kGeminiApiKeyOverride.trim();
  if (override.isNotEmpty) return override;

  final key = Firebase.app().options.apiKey.trim();
  if (key.isEmpty) {
    throw StateError('Firebase apiKey is empty; Gemini requests cannot start.');
  }
  return key;
}

/// Verifies that Firebase was initialized with the apiKey / projectId used by
/// the direct Google AI Studio client.
void verifyGeminiConfiguration() {
  final options = Firebase.app().options;
  if (options.apiKey.isEmpty || options.projectId.isEmpty) {
    throw StateError(
      'Firebase AI requires non-empty apiKey and projectId in FirebaseOptions.',
    );
  }
}
