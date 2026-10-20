import 'package:flutter/widgets.dart';

/// Languages offered in Settings. Japanese remains the default, while English
/// and Arabic add LTR / RTL UI support.
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

  static AppLanguage fromCode(String? code) {
    for (final language in AppLanguage.values) {
      if (language.code == code) return language;
    }
    return AppLanguage.ja;
  }
}
