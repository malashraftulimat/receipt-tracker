import 'package:flutter/widgets.dart';

/// Languages offered in the app. Japanese is the fallback, while English and
/// Arabic add LTR / RTL UI support.
enum AppLanguage {
  ja('ja', '日本語', 'Japanese'),
  en('en', 'English', 'English'),
  ar('ar', 'العربية', 'Arabic');

  const AppLanguage(this.code, this.nativeLabel, this.englishLabel);

  final String code;
  final String nativeLabel;
  final String englishLabel;

  Locale get locale => Locale(code);

  bool get isRtl => this == AppLanguage.ar;

  /// Language used when the browser / OS reports something we do not support.
  static AppLanguage get fallback => AppLanguage.ja;

  /// Resolves a language tag such as `ja`, `ja-JP`, `en_US` or `ar-EG`.
  /// Returns `null` when the language is not supported.
  static AppLanguage? tryParse(String? code) {
    if (code == null) return null;
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final language in AppLanguage.values) {
      if (language.code == normalized) return language;
    }
    final base = normalized.split(RegExp('[-_]')).first;
    for (final language in AppLanguage.values) {
      if (language.code == base) return language;
    }
    return null;
  }

  static AppLanguage fromCode(String? code) =>
      tryParse(code) ?? AppLanguage.fallback;

  /// First supported language found in [locales]; unsupported entries are
  /// skipped so `['fr-FR', 'ja-JP']` resolves to Japanese.
  static AppLanguage? fromLocales(Iterable<Locale> locales) {
    for (final locale in locales) {
      final match = tryParse(locale.languageCode);
      if (match != null) return match;
    }
    return null;
  }

  /// Browser (`navigator.languages`) / OS language of the running device.
  static List<Locale> get systemLocales {
    final dispatcher = WidgetsBinding.instance.platformDispatcher;
    return <Locale>[dispatcher.locale, ...dispatcher.locales];
  }

  /// Detected system language, falling back to [fallback] when unsupported.
  static AppLanguage detectSystemLanguage() =>
      fromLocales(systemLocales) ?? AppLanguage.fallback;
}
