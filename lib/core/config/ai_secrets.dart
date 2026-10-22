/// Bundled Google AI Studio (Gemini Developer API) key.
///
/// Kept empty in the repository so no credential is committed. Provide the key
/// at build time instead:
///
/// ```bash
/// flutter build web --release --dart-define=GEMINI_API_KEY=...
/// ```
///
/// `GEMINI_API_KEY` (see `ai_config.dart`) takes priority over this value.
/// `GEMINI_BUNDLED_API_KEY` can also be used when the key should be embedded
/// in the build without an override file.
const String kBundledGeminiApiKey = String.fromEnvironment(
  'GEMINI_BUNDLED_API_KEY',
  defaultValue: '',
);
