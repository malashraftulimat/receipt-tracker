import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_user.dart';
import '../core/settings/currency_provider.dart';
import '../core/settings/pay_cycle_provider.dart';
import '../domain/models/category.dart';
import '../domain/models/coupon.dart';
import '../domain/models/monthly_budget.dart';
import '../domain/models/payment_method.dart';
import '../domain/models/pay_cycle.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import '../domain/parser/receipt_parser.dart';
import 'repositories/auth_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/coupon_repository.dart';
import 'repositories/receipt_repository.dart';
import 'services/coupons/coupon_reminder_service.dart';
import 'services/ocr/ai_receipt_ocr_service.dart';
import 'services/ocr/ocr_service.dart';
import 'services/ocr/receipt_ocr_pipeline.dart';

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

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => CouponRepository(),
);

/// Coupon persistence + daily local reminders.
final couponReminderServiceProvider = Provider<CouponReminderService>(
  (ref) => CouponReminderService(
    repository: ref.watch(couponRepositoryProvider),
  ),
);

/// Active / used / expired coupons for the signed-in user.
final couponsProvider = FutureProvider<List<Coupon>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Coupon>[];
  final repository = ref.watch(couponRepositoryProvider);
  try {
    await repository.expireOverdue();
  } catch (_) {
    // Offline / permission errors must not hide the coupon list.
  }
  return repository.fetchAll();
});

/// Fallback OCR: ML Kit on Android/iOS, Tesseract.js on Web.
/// Desktop has no fallback OCR engine (Gemini still runs when online).
final ocrServiceProvider = Provider<OcrService>((ref) {
  final service = createOcrService();
  ref.onDispose(service.dispose);
  return service;
});

/// Primary extraction engine: direct Google AI Studio (Gemini Developer API).
final aiReceiptOcrServiceProvider = Provider<AiReceiptOcrService>(
  (ref) => AiReceiptOcrService(),
);

/// AI first, then the platform OCR service on error / offline / quota.
final receiptOcrPipelineProvider = Provider<ReceiptOcrPipeline>(
  (ref) => ReceiptOcrPipeline(
    ai: ref.watch(aiReceiptOcrServiceProvider),
    fallback: ref.watch(ocrServiceProvider),
    parser: const ReceiptParser(),
  ),
);

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

  void setPaymentMethod(PaymentMethod? method) =>
      state = state.copyWith(paymentMethod: method);

  void setMonth(DateTime? month) => state = state.copyWith(
        month: month == null ? null : DateTime(month.year, month.month),
        from: null,
        to: null,
      );

  void setRange(DateTime start, DateTime endInclusive) =>
      state = state.copyWith(
        month: null,
        from: DateTime(start.year, start.month, start.day),
        to: DateTime(
          endInclusive.year,
          endInclusive.month,
          endInclusive.day + 1,
        ),
      );

  void clearRange() =>
      state = state.copyWith(month: null, from: null, to: null);

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
  final repository = ref.watch(receiptRepositoryProvider);
  // One-time, non-blocking cleanup of legacy 登録番号 values stored as
  // barcode_id. The read path already treats them correctly.
  unawaited(repository.migrateLegacyInvoiceNumbers());
  return repository.fetch(filter);
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

/// Plan + actual spending + pacing for a month, paced by the pay cycle.
///
/// For the current month the summary also carries the **current pay period**
/// (`daily` = today, `weekly` = this week, `monthly` = the payday-to-payday
/// month), so the dashboard can show how much is left until the next payday.
/// Past / future months fall back to the calendar month.
final budgetSummaryProvider = FutureProvider.family<BudgetSummary, DateTime>(
  (ref, month) async {
    final userId = ref.watch(userIdProvider);
    final config = ref.watch(payCycleProvider);
    final currencyCode = ref.watch(defaultCurrencyProvider).code;
    final first = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 1);
    final now = DateTime.now();
    final daysInMonth = daysInMonthOf(first);

    var daysElapsed = 0;
    if (first.year == now.year && first.month == now.month) {
      daysElapsed = now.day;
    } else if (first.isBefore(DateTime(now.year, now.month, 1))) {
      daysElapsed = daysInMonth;
    }

    final budget = await ref.watch(budgetProvider(first).future);

    final isCurrentMonth = first.year == now.year && first.month == now.month;
    final period = isCurrentMonth ? config.periodFor(now) : null;

    // A monthly payday period that started last month (e.g. payday 25, today
    // Oct 3) was funded by last month's plan. Fall back to this month's plan
    // when that one is missing.
    var periodPlan = budget;
    if (period != null && config.isMonthly) {
      final periodMonth = firstDayOfMonth(period.start);
      if (periodMonth != first) {
        periodPlan =
            await ref.watch(budgetProvider(periodMonth).future) ?? budget;
      }
    }

    // One query covering both the calendar month and the current pay period.
    final rangeStart = period != null && period.start.isBefore(first)
        ? period.start
        : first;
    final rangeEnd = period != null && period.end.isAfter(monthEnd)
        ? period.end
        : monthEnd;

    var spent = 0.0;
    var receiptCount = 0;
    var todaySpent = 0.0;
    var periodSpent = 0.0;
    var otherCurrencyCount = 0;

    if (userId != null) {
      final receipts = await ref.watch(receiptRepositoryProvider).fetch(
            ReceiptFilter(from: rangeStart, to: rangeEnd),
          );
      final inDefaultCurrency = receipts
          .where((receipt) => receipt.currency == currencyCode)
          .toList(growable: false);
      for (final receipt in receipts) {
        final date = receipt.purchasedAt;
        final inMonth = !date.isBefore(first) && date.isBefore(monthEnd);
        if (inMonth && receipt.currency != currencyCode) {
          otherCurrencyCount += 1;
        }
        if (!inMonth || receipt.currency != currencyCode) continue;
        spent += receipt.totalAmount;
        receiptCount += 1;
        if (date.year == now.year &&
            date.month == now.month &&
            date.day == now.day) {
          todaySpent += receipt.totalAmount;
        }
      }
      if (period != null) {
        // Only the default currency feeds the pay-period remaining budget.
        periodSpent = inDefaultCurrency.totalInPeriod(period);
      }
    }

    double? periodBudget;
    int? periodDays;
    int? periodDaysElapsed;
    if (period != null && periodPlan != null) {
      final disposable = periodPlan.disposableIncome.toDouble();
      periodDays = period.days;
      periodDaysElapsed = period.daysElapsedOn(now);
      periodBudget = config.isMonthly
          ? disposable
          : disposable / config.periodsInMonth(first);
    }

    return BudgetSummary(
      month: first,
      budget: budget,
      spent: spent,
      receiptCount: receiptCount,
      daysInMonth: daysInMonth,
      daysElapsed: daysElapsed,
      todaySpent: todaySpent,
      payCycle: config.cycle,
      periodStart: period?.start,
      periodEnd: period?.end,
      periodDays: periodDays,
      periodDaysElapsed: periodDaysElapsed,
      periodBudget: periodBudget,
      periodSpent: period == null ? null : periodSpent,
      otherCurrencyCount: otherCurrencyCount,
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
