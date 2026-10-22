import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/localization.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'data/providers.dart';

class ReceiptTrackerApp extends ConsumerStatefulWidget {
  const ReceiptTrackerApp({super.key});

  @override
  ConsumerState<ReceiptTrackerApp> createState() => _ReceiptTrackerAppState();
}

class _ReceiptTrackerAppState extends ConsumerState<ReceiptTrackerApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialises notifications and applies queued notification actions.
      ref.read(couponReminderServiceProvider).start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Expire overdue coupons and refresh reminders when the app comes back.
    if (state == AppLifecycleState.resumed) {
      ref.read(couponReminderServiceProvider).sync();
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);

    // Resync reminders whenever the signed-in account changes.
    ref.listen(authStateProvider, (previous, next) {
      if (next.value != null) {
        ref.read(couponReminderServiceProvider).sync();
      }
    });

    const delegates = <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ];

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: language.locale,
      supportedLocales: kSupportedAppLocales,
      localizationsDelegates: delegates,
      onGenerateTitle: (context) => context.tr('レシート帳'),
    );
  }
}
