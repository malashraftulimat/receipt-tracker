import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/app_config.dart';
import '../domain/models/app_user.dart';
import '../domain/models/category.dart';
import '../domain/models/monthly_budget.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import 'repositories/auth_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/receipt_repository.dart';
import 'repositories/storage_repository.dart';
import 'services/local_store.dart';
import 'services/ocr/ocr_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final supabaseClientProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

// Repositories resolve the Supabase client lazily so that local mode works
// without ever initialising Supabase.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(),
);

final storageRepositoryProvider = Provider<StorageRepository>(
  (ref) => StorageRepository(),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(),
);

bool get _hasOnDeviceOcr =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// ML Kit on mobile, Tesseract.js on local web, Supabase Edge Function in
/// Supabase mode (web / desktop). Desktop local mode has no OCR engine.
final ocrServiceProvider = Provider<OcrService>((ref) {
  ref.watch(appModeProvider);

  if (AppConfig.isLocal && !_hasOnDeviceOcr && !kIsWeb) {
    return const UnavailableOcrService(
      'ローカルモードではサーバーOCRを使えません。'
      '「手入力で登録」を使うか、設定から Supabase に接続してください。',
    );
  }
  final service = createOcrService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Backend mode (Supabase sync vs on-device local mode)
// ---------------------------------------------------------------------------

class AppModeController extends Notifier<AppMode> {
  @override
  AppMode build() => AppConfig.mode;

  Future<void> switchToLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await AppConfig.useLocalMode(prefs);
    state = AppMode.local;
  }

  Future<void> switchToSupabase() async {
    final prefs = await SharedPreferences.getInstance();
    await AppConfig.useSupabaseMode(prefs);
    state = AppMode.supabase;
  }

  /// Re-reads the mode after [AppConfig.connect] changed it.
  void refresh() => state = AppConfig.mode;
}

final appModeProvider =
    NotifierProvider<AppModeController, AppMode>(AppModeController.new);

// ---------------------------------------------------------------------------
// Auth state
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseClientProvider).auth.onAuthStateChange,
);

/// Holds the signed-in account for on-device (local) mode.
class LocalSessionController extends Notifier<AppUser?> {
  @override
  AppUser? build() => AppConfig.localUser;

  void setUser(AppUser? user) {
    AppConfig.localUser = user;
    if (user != null) LocalStore.instance.useUser(user.id);
    state = user;
  }
}

final localSessionProvider =
    NotifierProvider<LocalSessionController, AppUser?>(
  LocalSessionController.new,
);

final currentUserProvider = Provider<AppUser?>((ref) {
  final mode = ref.watch(appModeProvider);
  if (mode == AppMode.local) return ref.watch(localSessionProvider);

  ref.watch(authStateProvider); // rebuild on sign-in / sign-out / refresh
  final user = ref.watch(supabaseClientProvider).auth.currentUser;
  if (user == null) return null;
  return AppUser(id: user.id, email: user.email ?? '');
});

final userIdProvider = Provider<String?>(
  (ref) => ref.watch(currentUserProvider)?.id,
);

// ---------------------------------------------------------------------------
// Data
// ---------------------------------------------------------------------------

final categoriesProvider = FutureProvider<List<ExpenseCategory>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <ExpenseCategory>[];
  final repository = ref.watch(categoryRepositoryProvider);
  await repository.ensureDefaults();
  return repository.fetchAll();
});

/// Dashboard query state (search / category / month / range / view mode).
class ReceiptFilterController extends Notifier<ReceiptFilter> {
  @override
  ReceiptFilter build() => const ReceiptFilter();

  void setSearch(String value) => state = state.copyWith(search: value);

  void toggleCategory(String? categoryId) => state = state.copyWith(
        categoryId: state.categoryId == categoryId ? null : categoryId,
      );

  void setMonth(DateTime? month) => state = state.copyWith(
        month: month == null ? null : DateTime(month.year, month.month),
        from: null,
        to: null,
      );

  void setRange(DateTime start, DateTime endInclusive) => state = state.copyWith(
        month: null,
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(
          endInclusive.year,
          endInclusive.month,
          endInclusive.day + 1,
        ),
      );

  void clearRange() => state = state.copyWith(month: null, from: null, to: null);

  void setView(ReceiptViewMode view) => state = state.copyWith(view: view);

  void reset() => state = ReceiptFilter(view: state.view);
}

final receiptFilterProvider =
    NotifierProvider<ReceiptFilterController, ReceiptFilter>(
  ReceiptFilterController.new,
);

final receiptsProvider = FutureProvider<List<Receipt>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Receipt>[];
  final filter = ref.watch(receiptFilterProvider);
  return ref.watch(receiptRepositoryProvider).fetch(filter);
});


// ---------------------------------------------------------------------------
// Budgets
// ---------------------------------------------------------------------------

/// Stored plan for a month (null when never configured).
final budgetProvider = FutureProvider.family<MonthlyBudget?, DateTime>(
  (ref, month) async {
    final userId = ref.watch(userIdProvider);
    if (userId == null) return null;
    return ref.watch(budgetRepositoryProvider).fetchMonth(month);
  },
);

/// Plan + actual spending + pacing for a month.
final budgetSummaryProvider = FutureProvider.family<BudgetSummary, DateTime>(
  (ref, month) async {
    final userId = ref.watch(userIdProvider);
    final first = DateTime(month.year, month.month, 1);
    final now = DateTime.now();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    var daysElapsed = 0;
    if (first.year == now.year && first.month == now.month) {
      daysElapsed = now.day;
    } else if (first.isBefore(DateTime(now.year, now.month, 1))) {
      daysElapsed = daysInMonth;
    }

    final budget = await ref.watch(budgetProvider(first).future);

    var spent = 0;
    var receiptCount = 0;
    var todaySpent = 0;

    if (userId != null) {
      final receipts = await ref
          .watch(receiptRepositoryProvider)
          .fetch(ReceiptFilter(month: first));
      for (final receipt in receipts) {
        spent += receipt.totalAmount;
        receiptCount += 1;
        final date = receipt.purchasedAt;
        if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          todaySpent += receipt.totalAmount;
        }
      }
    }

    return BudgetSummary(
      month: first,
      budget: budget,
      spent: spent,
      receiptCount: receiptCount,
      daysInMonth: daysInMonth,
      daysElapsed: daysElapsed,
      todaySpent: todaySpent,
    );
  },
);

final receiptByIdProvider = FutureProvider.family<Receipt, String>(
  (ref, id) => ref.watch(receiptRepositoryProvider).getById(id),
);


/// Receipts with a 支払期限, sorted by the closest deadline.
final upcomingDueProvider = FutureProvider<List<Receipt>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Receipt>[];

  final now = DateTime.now();
  final receipts = await ref.watch(receiptRepositoryProvider).fetch(
    ReceiptFilter(
      from: DateTime(now.year, now.month - 1, 1),
      to: DateTime(now.year, now.month + 3, 1),
    ),
  );

  final due = receipts.where((receipt) => receipt.dueDate != null).toList();
  due.sort((a, b) => a.dueDate!.compareTo(b.dueDate!));
  return due;
});

/// Signed URL for a stored receipt image path.
final signedImageUrlProvider = FutureProvider.family<String, String>(
  (ref, path) => ref.watch(storageRepositoryProvider).signedUrl(path),
);
