import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_config.dart';
import 'data/providers.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/setup/connection_setup_page.dart';

class ReceiptTrackerApp extends ConsumerWidget {
  const ReceiptTrackerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Rebuilds when the storage mode is switched (local <-> Supabase).
    ref.watch(appModeProvider);

    if (!AppConfig.isConfigured && !AppConfig.isLocal) {
      // No Supabase credentials and no local mode yet:
      // let the user choose how to store data (server sync or on-device).
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
