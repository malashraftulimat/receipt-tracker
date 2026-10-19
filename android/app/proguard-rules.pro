# ---------------------------------------------------------------------------
# ML Kit text recognition
#
# google_mlkit_text_recognition declares the non-Latin script models as
# `compileOnly`, and references all of them from TextRecognizer.initialize().
# This app only ships the Japanese model, so silence the other scripts and
# keep the ML Kit entry points intact for R8.
# ---------------------------------------------------------------------------
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.korean.**

-keep class com.google.mlkit.vision.text.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }

# Mobile Scanner / ML Kit reflection
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
