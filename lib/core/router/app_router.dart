import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_page.dart';
import '../../features/budget/budget_page.dart';
import '../../features/categories/categories_page.dart';
import '../../features/coupons/coupons_page.dart';
import '../../features/dashboard/dashboard_page.dart';
import '../../features/debts/debt_detail_page.dart';
import '../../features/debts/debts_page.dart';
import '../../features/income/add_income_page.dart';
import '../../features/payments/add_payment_page.dart';
import '../../features/receipts/receipt_detail_page.dart';
import '../../features/recurring/recurring_page.dart';
import '../../features/review/review_page.dart';
import '../../features/scan/scan_page.dart';
import '../../features/settings/rates_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/wallets/wallet_detail_page.dart';
import '../../features/wallets/wallets_page.dart';
import 'app_shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  // Re-run redirects whenever the Firebase session changes.
  final refresh = ValueNotifier<int>(0);
  final subscription = FirebaseAuth.instance.authStateChanges().listen(
        (_) => refresh.value++,
      );
  ref.onDispose(() {
    subscription.cancel();
    refresh.dispose();
  });

  bool signedIn() => FirebaseAuth.instance.currentUser != null;

  // Login / register screens (both served by [AuthPage]).
  bool isAuthLocation(String path) =>
      path.startsWith('/auth') ||
      path.startsWith('/login') ||
      path.startsWith('/register');

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    debugLogDiagnostics: false,
    redirect: (context, state) {
      final onAuthPage = isAuthLocation(state.matchedLocation);
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
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const AuthPage(),
      ),
      GoRoute(
        path: '/register',
        name: 'register',
        builder: (context, state) => const AuthPage(initialSignUp: true),
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
            path: '/coupons',
            name: 'coupons',
            builder: (context, state) => const CouponsPage(),
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
        path: '/payment/new',
        name: 'addPayment',
        builder: (context, state) => const AddPaymentPage(),
      ),
      GoRoute(
        path: '/income/new',
        name: 'addIncome',
        builder: (context, state) => const AddIncomePage(),
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
      GoRoute(
        path: '/wallets',
        name: 'wallets',
        builder: (context, state) => const WalletsPage(),
      ),
      GoRoute(
        path: '/wallet/:id',
        name: 'wallet',
        builder: (context, state) => WalletDetailPage(
          walletId: state.pathParameters['id'] ?? '',
        ),
      ),
      GoRoute(
        path: '/rates',
        name: 'rates',
        builder: (context, state) => const RatesPage(),
      ),
      GoRoute(
        path: '/debts',
        name: 'debts',
        builder: (context, state) => const DebtsPage(),
      ),
      GoRoute(
        path: '/recurring',
        name: 'recurring',
        builder: (context, state) => const RecurringPage(),
      ),
      GoRoute(
        path: '/debt/:id',
        name: 'debt',
        builder: (context, state) => DebtDetailPage(
          debtId: state.pathParameters['id'] ?? '',
        ),
      ),
    ],
  );
});
