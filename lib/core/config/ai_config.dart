import 'package:firebase_ai/firebase_ai.dart';

/// Current Gemini Flash model available through Firebase AI Logic.
///
/// `firebase_vertexai` has been discontinued by Firebase and renamed to
/// `firebase_ai`; this project uses the official replacement package while
/// still targeting the Gemini Developer API backend.
const String kGeminiReceiptModel = String.fromEnvironment(
  'GEMINI_RECEIPT_MODEL',
  defaultValue: 'gemini-3.8-flash',
);

/// Creates the cached Gemini Developer API backend service after
/// `Firebase.initializeApp()` and App Check activation.
FirebaseAI initializeReceiptAi() => FirebaseAI.googleAI();
