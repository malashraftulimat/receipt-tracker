import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';

/// Persisted UI language.
///
/// On startup the app follows the browser / OS language (`navigator.languages`
/// on web, the system locale elsewhere). A language picked from the header
/// switcher is stored in `SharedPreferences` and overrides detection from then
/// on. Changing the language also updates `Intl.defaultLocale`, which the date
/// and number formatters use for their locale-aware output.
class LanguageController extends Notifier<AppLanguage> {
  static const String _prefsKey = 'app_language';

  /// True once the user picked a language explicitly (persisted preference).
  bool _manuallySelected = false;

  bool get hasManualSelection => _manuallySelected;

  @override
  AppLanguage build() {
    // Auto-detect first so the very first frame already uses the right locale.
    final detected = AppLanguage.detectSystemLanguage();
    Intl.defaultLocale = detected.code;
    _manuallySelected = false;

    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final saved = AppLanguage.tryParse(prefs.getString(_prefsKey));
        // No stored choice: keep following the browser / OS language.
        if (saved == null) return;
        _manuallySelected = true;
        Intl.defaultLocale = saved.code;
        state = saved;
      } catch (_) {
        // Storage unavailable (e.g. unit tests) — keep the detected language.
      }
    });

    return detected;
  }

  Future<void> setLanguage(AppLanguage language) async {
    _manuallySelected = true;
    state = language;
    Intl.defaultLocale = language.code;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, language.code);
    } catch (_) {
      // Persisting failed; the in-memory choice still applies for this session.
    }
  }

  /// Re-detects the browser / OS language, e.g. after `didChangeLocales`.
  ///
  /// Does nothing when the user pinned a language in the header switcher.
  void syncWithSystemLocales(List<Locale> locales) {
    if (_manuallySelected) return;
    final detected = AppLanguage.fromLocales(locales);
    if (detected == null || detected == state) return;
    Intl.defaultLocale = detected.code;
    state = detected;
  }
}

final languageProvider =
    NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);
