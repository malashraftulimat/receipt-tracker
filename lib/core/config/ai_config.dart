/// Gemini API key supplied at build time.
///
/// Web deploys pass it from the `GEMINI_API_KEY` GitHub Actions secret:
/// `--dart-define=GEMINI_API_KEY=...`. No key is bundled in the repository,
/// and the Firebase project API key is never used for Gemini calls.
const String kGeminiApiKeyOverride = String.fromEnvironment('GEMINI_API_KEY');

/// Gemini Flash model for direct Gemini Developer API requests.
///
/// A Flash **Lite** model is the default because receipt extraction returns
/// in a few seconds on Lite, while thinking Flash models need much longer per
/// scan. `gemini-3.1-flash-lite` is a stable model in the official model list.
/// Override with `--dart-define=GEMINI_RECEIPT_MODEL=...` if needed.
const String kGeminiReceiptModel = String.fromEnvironment(
  'GEMINI_RECEIPT_MODEL',
  defaultValue: 'gemini-3.1-flash-lite',
);

/// Stable fallback models tried when the primary model is unavailable or not
/// exposed by the API key. All names are listed as stable in the Gemini API
/// model documentation.
const List<String> kGeminiReceiptFallbackModels = <String>[
  'gemini-3.5-flash-lite',
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

/// Resolves the Gemini API key from the build-time override only.
///
/// Returns null when `GEMINI_API_KEY` was not supplied at build time. There is
/// deliberately no Firebase / bundled-key fallback: a missing key must surface
/// as an "AI key missing" error and let the on-device OCR fallback run.
String? geminiApiKeyOrNull() {
  final key = kGeminiApiKeyOverride.trim();
  return key.isEmpty ? null : key;
}

/// Throwing variant of [geminiApiKeyOrNull] for callers that require a key.
String geminiApiKey() {
  final key = geminiApiKeyOrNull();
  if (key == null) {
    throw StateError(
        'AI key missing: GEMINI_API_KEY was not set at build time.');
  }
  return key;
}

/// True when the build supplied a Gemini API key.
bool hasGeminiApiKey() => geminiApiKeyOrNull() != null;
