import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/setup/connection_setup_page.dart';

class ReceiptTrackerApp extends ConsumerWidget {
  const ReceiptTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!AppConfig.isConfigured) {
      // No Supabase credentials yet (sideloaded APK / plain web build):
      // let the user connect to their project once.
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ref.watch(themeModeProvider),
        locale: const Locale('ja'),
        supportedLocales: const <Locale>[Locale('ja'), Locale('en')],
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const ConnectionSetupPage(),
      );
    }

    return MaterialApp.router(
      title: 'レシート帳',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
      locale: const Locale('ja'),
      supportedLocales: const <Locale>[Locale('ja'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
