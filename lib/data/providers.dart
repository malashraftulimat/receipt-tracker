import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_user.dart';
import '../domain/models/category.dart';
import '../domain/models/monthly_budget.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import 'repositories/auth_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/receipt_repository.dart';
import 'services/ocr/ocr_service.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(),
);

final receiptRepositoryProvider = Provider<ReceiptRepository>(
  (ref) => ReceiptRepository(),
);

final categoryRepositoryProvider = Provider<CategoryRepository>(
  (ref) => CategoryRepository(),
);

final budgetRepositoryProvider = Provider<BudgetRepository>(
  (ref) => BudgetRepository(),
);

/// ML Kit on Android/iOS, Tesseract.js on Web. Desktop has no OCR engine.
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = createOcrService();
  ref.onDispose(service.dispose);
  return service;
});

// ---------------------------------------------------------------------------
// Auth state (Firebase Auth)
// ---------------------------------------------------------------------------

final authStateProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

final currentUserProvider = Provider<AppUser?>((ref) {
  ref.watch(authStateProvider); // rebuild on sign-in / sign-out / refresh
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;
  return AppUser(id: user.uid, email: user.email ?? '');
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


