import 'package:firebase_ai/firebase_ai.dart';
import 'package:firebase_core/firebase_core.dart';

/// Primary Gemini Flash model for receipt extraction.
///
/// `firebase_vertexai` has been discontinued by Firebase and renamed to
/// `firebase_ai`; this project uses the official replacement package while
/// still targeting the Gemini Developer API backend.
const String kGeminiReceiptModel = String.fromEnvironment(
  'GEMINI_RECEIPT_MODEL',
  defaultValue: 'gemini-3.8-flash',
);

/// Model fallbacks tried automatically when the primary model is unavailable
/// or not exposed by the current Firebase project.
const List<String> kGeminiReceiptFallbackModels = <String>[
  'gemini-3.7-flash',
  'gemini-3.5-flash',
];

/// Creates the cached Gemini Developer API backend service after
/// `Firebase.initializeApp()` and App Check activation.
///
/// The SDK reads `apiKey` and `projectId` from the supplied Firebase app
/// options. Verify they are present so misconfiguration fails early instead of
/// surfacing as a generic "unavailable" error.
FirebaseAI initializeReceiptAi() {
  final app = Firebase.app();
  final options = app.options;
  if (options.apiKey.isEmpty || options.projectId.isEmpty) {
    throw StateError(
      'Firebase AI requires non-empty apiKey and projectId in FirebaseOptions.',
    );
  }
  return FirebaseAI.googleAI(app: app);
}
