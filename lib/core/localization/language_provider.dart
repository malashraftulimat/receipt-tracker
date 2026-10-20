import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_language.dart';

/// Persisted UI language. Changing it also updates `Intl.defaultLocale`, which
/// the date / number formatters use for their locale-aware output.
class LanguageController extends Notifier<AppLanguage> {
  static const String _prefsKey = 'app_language';

  @override
  AppLanguage build() {
    Intl.defaultLocale = AppLanguage.ja.code;

    Future<void>(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        final language =
            AppLanguage.fromCode(prefs.getString(_prefsKey));
        Intl.defaultLocale = language.code;
        state = language;
      } catch (_) {
        // Storage unavailable (e.g. unit tests) — keep Japanese.
      }
    });

    return AppLanguage.ja;
  }

  Future<void> setLanguage(AppLanguage language) async {
    state = language;
    Intl.defaultLocale = language.code;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, language.code);
  }
}

final languageProvider =
    NotifierProvider<LanguageController, AppLanguage>(LanguageController.new);
