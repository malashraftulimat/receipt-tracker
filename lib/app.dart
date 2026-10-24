import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/localization/localization.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'data/providers.dart';
import 'features/dashboard/analytics_provider.dart';

class ReceiptTrackerApp extends ConsumerStatefulWidget {
  const ReceiptTrackerApp({super.key});

  @override
  ConsumerState<ReceiptTrackerApp> createState() => _ReceiptTrackerAppState();
}

class _ReceiptTrackerAppState extends ConsumerState<ReceiptTrackerApp>
    with WidgetsBindingObserver {
  bool _postingRecurring = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Initialises notifications and applies queued notification actions.
      ref.read(couponReminderServiceProvider).start();
      _postRecurring();
    });
  }

  Future<void> _postRecurring() async {
    if (_postingRecurring || ref.read(userIdProvider) == null) return;
    _postingRecurring = true;
    try {
      final result =
          await ref.read(recurringPostingServiceProvider).postDue();
      if (result.postedAnything) {
        ref.invalidate(receiptsProvider);
        ref.invalidate(walletReceiptsProvider);
        ref.invalidate(incomeEntriesProvider);
        ref.invalidate(recurringTransactionsProvider);
        ref.invalidate(analyticsProvider);
        final now = DateTime.now();
        ref.invalidate(budgetSummaryProvider(DateTime(now.year, now.month)));
      }
    } catch (error) {
      debugPrint('[Recurring] posting skipped: $error');
    } finally {
      _postingRecurring = false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    // Follow the browser / OS language unless the user pinned one.
    ref.read(languageProvider.notifier).syncWithSystemLocales(
          locales ?? AppLanguage.systemLocales,
        );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Expire overdue coupons and refresh reminders when the app comes back.
    if (state == AppLifecycleState.resumed) {
      ref.read(couponReminderServiceProvider).sync();
      _postRecurring();
    }
  }

  @override
  Widget build(BuildContext context) {
    final language = ref.watch(languageProvider);

    // Resync reminders whenever the signed-in account changes.
    ref.listen(authStateProvider, (previous, next) {
      if (next.value != null) {
        ref.read(couponReminderServiceProvider).sync();
        _postRecurring();
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
      onGenerateTitle: (context) => context.tr('receipt_tracker'),
    );
  }
}
