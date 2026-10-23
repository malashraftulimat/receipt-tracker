import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_language.dart';
import 'messages.dart';
import 'translations_ar.dart';
import 'translations_en.dart';

const List<Locale> kSupportedAppLocales = <Locale>[
  Locale('ja'),
  Locale('en'),
  Locale('ar'),
];

/// Localization layer for the whole app.
///
/// Every user-visible string is addressed by a stable message id whose
/// Japanese text, English text and Arabic text live in
/// `messages.dart` / `translations_en.dart` / `translations_ar.dart`.
///
/// Messages may contain `{name}` placeholders and can opt into plural forms
/// by defining `<id>.zero`, `<id>.one`, `<id>.two`, `<id>.few`, `<id>.many`
/// and `<id>.other` entries (CLDR categories for ja / en / ar).
class AppLocalizations {
  const AppLocalizations(this.language);

  final AppLanguage language;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations) ??
        const AppLocalizations(AppLanguage.ja);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  static bool isMessageId(String value) => kMessageKeys.containsKey(value);

  Map<String, String> get _dictionary => switch (language) {
        AppLanguage.ja => kMessageKeys,
        AppLanguage.en => kEnglishTranslations,
        AppLanguage.ar => kArabicTranslations,
      };

  /// Translates a message id, or passes user data (merchant / item / note)
  /// through unchanged. Seeded category names stored in Firestore are mapped
  /// to their message id so old documents translate without being rewritten.
  String translate(String id) {
    if (kMessageKeys.containsKey(id)) return _dictionary[id] ?? kMessageKeys[id]!;
    final seedId = kSeedNameIds[id];
    if (seedId != null) return _dictionary[seedId] ?? kMessageKeys[seedId]!;
    return id;
  }

  /// Translates [id] and interpolates `{placeholders}` from [params].
  ///
  /// When [count] is supplied the matching CLDR plural form is chosen.
  String msg(
    String id, {
    Map<String, Object?> params = const <String, Object?>{},
    num? count,
  }) {
    var resolvedId = id;
    if (count != null) {
      final category = pluralCategory(language, count);
      if (kMessageKeys.containsKey('$id.$category')) {
        resolvedId = '$id.$category';
      } else if (kMessageKeys.containsKey('$id.other')) {
        resolvedId = '$id.other';
      }
    }
    var resolvedParams = params;
    if (count != null && params['count'] == null) {
      resolvedParams = <String, Object?>{...params, 'count': count};
    }
    return interpolate(translate(resolvedId), resolvedParams);
  }

  /// Replaces `{name}` placeholders in [pattern]. Unknown placeholders are kept.
  static String interpolate(String pattern, Map<String, Object?> params) {
    if (params.isEmpty || !pattern.contains('{')) return pattern;
    var result = pattern;
    params.forEach((key, value) {
      result = result.replaceAll('{$key}', '${value ?? ''}');
    });
    return result;
  }

  /// CLDR plural category for the supported languages.
  static String pluralCategory(AppLanguage language, num value) {
    final n = value.abs();
    switch (language) {
      case AppLanguage.ja:
        return 'other';
      case AppLanguage.en:
        return n == 1 ? 'one' : 'other';
      case AppLanguage.ar:
        if (n == 0) return 'zero';
        if (n == 1) return 'one';
        if (n == 2) return 'two';
        final mod100 = n % 100;
        if (mod100 >= 3 && mod100 <= 10) return 'few';
        if (mod100 >= 11 && mod100 <= 99) return 'many';
        return 'other';
    }
  }
}

/// Parameters accepted by [AppText] / [BuildContext.tr].
typedef MessageParams = Map<String, Object?>;

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return kSupportedAppLocales
        .any((supported) => supported.languageCode == locale.languageCode);
  }

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(
      AppLocalizations(AppLanguage.fromCode(locale.languageCode)),
    );
  }

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

extension AppLocalizationContext on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Translates a message id with optional `{name}` parameters / plural count.
  String tr(
    String id, {
    MessageParams params = const <String, Object?>{},
    num? count,
  }) =>
      l10n.msg(id, params: params, count: count);
}
