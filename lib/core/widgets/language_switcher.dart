import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../localization/localization.dart';

/// Global language switcher used in every header (`AppBar`).
///
/// It is mounted in the signed-in shell pages as well as on the login /
/// register screens, so the UI language can always be changed — before and
/// after signing in. The choice is persisted by [LanguageController].
class LanguageSwitcherButton extends ConsumerWidget {
  const LanguageSwitcherButton({super.key, this.showLabel = false});

  /// Also renders the current language code next to the icon.
  /// Useful on wide (desktop / web) headers.
  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final language = ref.watch(languageProvider);
    final theme = Theme.of(context);

    void select(AppLanguage? next) {
      if (next == null || next == language) return;
      ref.read(languageProvider.notifier).setLanguage(next);
    }

    return PopupMenuButton<AppLanguage>(
      tooltip: context.tr('change_language'),
      initialValue: language,
      onSelected: select,
      icon: showLabel
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.translate, size: 20),
                const SizedBox(width: 4),
                Text(
                  language.code.toUpperCase(),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            )
          : const Icon(Icons.translate),
      itemBuilder: (context) => <PopupMenuEntry<AppLanguage>>[
        PopupMenuItem<AppLanguage>(
          enabled: false,
          height: 36,
          child: AppText(
            'change_language',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const PopupMenuDivider(),
        for (final option in AppLanguage.values)
          CheckedPopupMenuItem<AppLanguage>(
            value: option,
            checked: option == language,
            child: AppText(
              option.nativeLabel,
              translate: false,
              textDirection:
                  option.isRtl ? TextDirection.rtl : TextDirection.ltr,
            ),
          ),
      ],
    );
  }
}

/// Standard trailing actions for a page `AppBar`: optional page actions plus the
/// always-visible [LanguageSwitcherButton].
List<Widget> headerActions(
  BuildContext context, {
  List<Widget> actions = const <Widget>[],
  bool showLanguageLabel = false,
}) {
  return <Widget>[
    ...actions,
    LanguageSwitcherButton(showLabel: showLanguageLabel),
    const SizedBox(width: 4),
  ];
}
