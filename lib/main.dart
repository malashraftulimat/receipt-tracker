import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'app.dart';
import 'core/config/ai_config.dart';
import 'core/config/app_check_config.dart';
import 'core/config/firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Date symbols for every UI language (Japanese / English / Arabic).
  await initializeDateFormatting('ja');
  await initializeDateFormatting('en');
  await initializeDateFormatting('ar');

  // Firebase Auth + Cloud Firestore + direct Google AI Studio.
  await Firebase.initializeApp(options: kFirebaseOptions);
  await _initializeAppCheck();

  // AI OCR uses only the build-time GEMINI_API_KEY. When it is missing the
  // app still starts and the scanner falls back to on-device OCR.
  if (!hasGeminiApiKey()) {
    debugPrint(
      '[AI] No build-time key; a saved browser key or on-device OCR will be used.',
    );
  }

  runApp(const ProviderScope(child: ReceiptTrackerApp()));
}

/// Enables App Check for Firebase services.
///
/// Web debug builds use the App Check debug provider. Release web builds use
/// reCAPTCHA v3 when `RECAPTCHA_V3_SITE_KEY` is supplied; when it is absent the
/// app still starts normally (Firebase services do not enforce App Check).
Future<void> _initializeAppCheck() async {
  try {
    if (kIsWeb) {
      if (kDebugMode) {
        await FirebaseAppCheck.instance.activate(
          providerWeb: WebDebugProvider(),
        );
        return;
      }
      final siteKey = kReCaptchaV3SiteKey.trim();
      if (siteKey.isEmpty) return;
      await FirebaseAppCheck.instance.activate(
        providerWeb: ReCaptchaV3Provider(siteKey),
      );
      return;
    }

    final isApple = defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
    } else if (isApple) {
      await FirebaseAppCheck.instance.activate(
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
  } catch (_) {
    // Never block app startup because App Check could not be activated.
  }
}
