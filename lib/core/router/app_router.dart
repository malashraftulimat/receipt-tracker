import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../data/providers.dart';
import '../config/app_config.dart';
import '../../features/auth/auth_page.dart';
import '../../features/budget/budget_page.dart';
import '../../features/categories/categories_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/receipts/receipt_detail_page.dart';
import '../../features/review/review_page.dart';
import '../../features/scan/scan_page.dart';
import '../../features/settings/settings_page.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Rebuild the router when the storage mode changes.
  ref.watch(appModeProvider);

  // Re-run redirects whenever the session changes.
  final refresh = ValueNotifier<int>(0);
  StreamSubscription<AuthState>? subscription;

  if (!AppConfig.isLocal) {
    final client = ref.watch(supabaseClientProvider);
    subscription =
        client.auth.onAuthStateChange.listen((_) => refresh.value++);
  }
  ref.onDispose(() {
    subscription?.cancel();
    refresh.dispose();
  });

  // Local mode uses an on-device account and never touches Supabase.
  bool signedIn() => AppConfig.isLocal
      ? AppConfig.localUser != null
      : Supabase.instance.client.auth.currentUser != null;

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final onAuthPage = state.matchedLocation.startsWith('/auth');
      if (!signedIn()) return onAuthPage ? null : '/auth';
      if (onAuthPage) return '/dashboard';
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
        path: '/auth',
        name: 'auth',
        builder: (context, state) => const AuthPage(),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(
          location: state.matchedLocation,
          child: child,
        ),
        routes: <RouteBase>[
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) => const DashboardPage(),
          ),
          GoRoute(
            path: '/categories',
            name: 'categories',
            builder: (context, state) => const CategoriesPage(),
          ),
          GoRoute(
            path: '/settings',
            name: 'settings',
            builder: (context, state) => const SettingsPage(),
          ),
          GoRoute(
            path: '/budget',
            name: 'budget',
            builder: (context, state) => const BudgetPage(),
          ),
        ],
      ),
      GoRoute(
        path: '/scan',
        name: 'scan',
        builder: (context, state) => const ScanPage(),
      ),
      GoRoute(
        path: '/review',
        name: 'review',
        builder: (context, state) => ReviewPage(
          args: state.extra is ReviewArgs
              ? state.extra! as ReviewArgs
              : const ReviewArgs(),
        ),
      ),
      GoRoute(
        path: '/receipt/:id',
        name: 'receipt',
        builder: (context, state) => ReceiptDetailPage(
          receiptId: state.pathParameters['id'] ?? '',
        ),
      ),
    ],
  );
});
