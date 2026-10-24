import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/settings/currency_provider.dart';
import '../core/settings/exchange_rates_provider.dart';
import '../core/settings/pay_cycle_provider.dart';
import '../domain/models/app_user.dart';
import '../domain/models/category.dart';
import '../domain/models/coupon.dart';
import '../domain/models/debt.dart';
import '../domain/models/exchange_rates.dart';
import '../domain/models/income_entry.dart';
import '../domain/models/income_source.dart';
import '../domain/models/income_summary.dart';
import '../domain/models/money_totals.dart';
import '../domain/models/monthly_budget.dart';
import '../domain/models/payment_method.dart';
import '../domain/models/pay_cycle.dart';
import '../domain/models/receipt.dart';
import '../domain/models/receipt_filter.dart';
import '../domain/models/reminder.dart';
import '../domain/models/wallet.dart';
import '../domain/models/wallet_adjustment.dart';
import '../domain/models/wallet_ledger.dart';
import '../domain/models/wallet_transfer.dart';
import '../domain/parser/receipt_parser.dart';
import 'repositories/auth_repository.dart';
import 'repositories/budget_repository.dart';
import 'repositories/category_repository.dart';
import 'repositories/coupon_repository.dart';
import 'repositories/debt_repository.dart';
import 'repositories/income_repository.dart';
import 'repositories/receipt_repository.dart';
import 'repositories/wallet_repository.dart';
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

final incomeSourceRepositoryProvider = Provider<IncomeSourceRepository>(
  (ref) => IncomeSourceRepository(),
);

final incomeEntryRepositoryProvider = Provider<IncomeEntryRepository>(
  (ref) => IncomeEntryRepository(),
);

final couponRepositoryProvider = Provider<CouponRepository>(
  (ref) => CouponRepository(),
);

final walletRepositoryProvider = Provider<WalletRepository>(
  (ref) => WalletRepository(),
);

final debtRepositoryProvider = Provider<DebtRepository>(
  (ref) => DebtRepository(),
);

final walletTransferRepositoryProvider = Provider<WalletTransferRepository>(
  (ref) => WalletTransferRepository(),
);

final walletAdjustmentRepositoryProvider =
    Provider<WalletAdjustmentRepository>(
  (ref) => WalletAdjustmentRepository(),
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

/// Recurring income sources persisted in Firestore.
///
/// On first load an empty collection is seeded from the legacy single pay
/// cycle + latest monthly plan (one source named "Main"). A marker document
/// prevents re-seeding after the user deliberately deletes every source.
class IncomeSourcesController extends AsyncNotifier<List<IncomeSource>> {
  @override
  Future<List<IncomeSource>> build() async {
    final userId = ref.watch(userIdProvider);
    if (userId == null) return const <IncomeSource>[];
    final latest = await ref.watch(budgetRepositoryProvider).fetchLatest();
    return ref.watch(incomeSourceRepositoryProvider).ensureSeeded(
          legacyConfig: ref.read(payCycleProvider),
          latestBudget: latest,
          currency: ref.read(defaultCurrencyProvider).code,
        );
  }

  Future<void> save(IncomeSource source) async {
    final current = state.valueOrNull ?? const <IncomeSource>[];
    final next = <IncomeSource>[...current];
    final index = next.indexWhere((item) => item.id == source.id);
    if (index >= 0) {
      next[index] = source;
    } else {
      next.add(source);
    }
    if (source.definesBudgetPeriod) {
      for (var i = 0; i < next.length; i++) {
        next[i] = next[i].copyWith(
          definesBudgetPeriod: next[i].id == source.id,
        );
      }
    }
    await _apply(normalizeBudgetPeriodFlag(next));
  }

  Future<void> delete(String id) async {
    final current = state.valueOrNull ?? const <IncomeSource>[];
    final next = normalizeBudgetPeriodFlag(
      current.where((item) => item.id != id).toList(growable: false),
    );
    final previous = state;
    state = AsyncData(next);
    try {
      final repository = ref.read(incomeSourceRepositoryProvider);
      await repository.delete(id);
      if (next.isNotEmpty) await repository.saveAll(next);
    } catch (error, stack) {
      state = previous;
      Error.throwWithStackTrace(error, stack);
    }
  }

  Future<void> setDefinesBudgetPeriod(String id) async {
    final current = state.valueOrNull ?? const <IncomeSource>[];
    await _apply(normalizeBudgetPeriodFlag(<IncomeSource>[
      for (final item in current)
        item.copyWith(definesBudgetPeriod: item.id == id),
    ]));
  }

  Future<void> setActive(String id, bool active) async {
    final current = state.valueOrNull ?? const <IncomeSource>[];
    await _apply(<IncomeSource>[
      for (final item in current)
        item.id == id ? item.copyWith(active: active) : item,
    ]);
  }

  Future<void> _apply(List<IncomeSource> next) async {
    final previous = state;
    state = AsyncData(next);
    try {
      await ref.read(incomeSourceRepositoryProvider).saveAll(next);
    } catch (error, stack) {
      state = previous;
      Error.throwWithStackTrace(error, stack);
    }
  }
}

final incomeSourcesProvider =
    AsyncNotifierProvider<IncomeSourcesController, List<IncomeSource>>(
  IncomeSourcesController.new,
);

/// One-off income entries (newest first) used for period totals + autocomplete.
final incomeEntriesProvider = FutureProvider<List<IncomeEntry>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <IncomeEntry>[];
  return ref.watch(incomeEntryRepositoryProvider).fetchAll(limit: 5000);
});

/// Distinct source texts typed before, newest first.
final incomeSourceSuggestionsProvider = Provider<List<String>>((ref) {
  final entries =
      ref.watch(incomeEntriesProvider).valueOrNull ?? const <IncomeEntry>[];
  return previousIncomeSources(entries);
});

// ---------------------------------------------------------------------------
// Wallets, transactions and display-currency totals
// ---------------------------------------------------------------------------

final walletsProvider = FutureProvider<List<Wallet>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Wallet>[];
  return ref.watch(walletRepositoryProvider).fetchAll();
});

final walletByIdProvider = Provider.family<Wallet?, String>((ref, id) {
  final wallets = ref.watch(walletsProvider).valueOrNull;
  if (wallets == null) return null;
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet;
  }
  return null;
});

/// All receipts, independent of the dashboard filter, for balance maths.
final walletReceiptsProvider = FutureProvider<List<Receipt>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Receipt>[];
  return ref
      .watch(receiptRepositoryProvider)
      .fetch(const ReceiptFilter(), limit: 5000);
});

final walletTransfersProvider =
    FutureProvider<List<WalletTransfer>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <WalletTransfer>[];
  return ref.watch(walletTransferRepositoryProvider).fetchAll();
});

final walletAdjustmentsProvider =
    FutureProvider<List<WalletAdjustment>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <WalletAdjustment>[];
  return ref.watch(walletAdjustmentRepositoryProvider).fetchAll();
});

final debtsProvider = FutureProvider<List<Debt>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return const <Debt>[];
  return ref.watch(debtRepositoryProvider).fetchAll();
});

final debtByIdProvider = Provider.family<Debt?, String>((ref, id) {
  final debts = ref.watch(debtsProvider).valueOrNull;
  if (debts == null) return null;
  for (final debt in debts) {
    if (debt.id == id) return debt;
  }
  return null;
});

/// Wallet balances derived from opening balances + transactions.
final walletLedgerProvider = FutureProvider<WalletLedger>((ref) async {
  final wallets = await ref.watch(walletsProvider.future);
  final receipts = await ref.watch(walletReceiptsProvider.future);
  final income = await ref.watch(incomeEntriesProvider.future);
  final transfers = await ref.watch(walletTransfersProvider.future);
  final adjustments = await ref.watch(walletAdjustmentsProvider.future);
  final debts = await ref.watch(debtsProvider.future);
  return buildWalletLedger(
    wallets: wallets,
    receipts: receipts,
    incomeEntries: income,
    transfers: transfers,
    adjustments: adjustments,
    debts: debts,
  );
});

final walletAccountProvider = Provider.family<WalletAccount?, String>(
  (ref, id) => ref.watch(walletLedgerProvider).valueOrNull?.accountFor(id),
);

/// The three dashboard totals in the display currency.
final moneyTotalsProvider = FutureProvider<MoneyTotals>((ref) async {
  final ledger = await ref.watch(walletLedgerProvider.future);
  final debts = await ref.watch(debtsProvider.future);
  final base = ref.watch(defaultCurrencyProvider).code;
  final needsFx = ledger.all.any(
        (account) =>
            account.wallet.currency.trim().toUpperCase() != base.toUpperCase(),
      ) ||
      debts.any(
        (debt) => debt.currency.trim().toUpperCase() != base.toUpperCase(),
      );
  final fx = needsFx
      ? (await ref.watch(exchangeRatesProvider.future)).snapshot
      : FxSnapshot(
          base: base,
          rates: const <String, double>{},
          fetchedAt: DateTime.now(),
        );

  var debtsOwedToMe = 0.0;
  var debtsIOwe = 0.0;
  var missingDebtRates = 0;
  for (final debt in debts) {
    if (debt.outstanding <= 0) continue;
    final converted = fx.convert(debt.outstanding, debt.currency, base);
    if (converted == null) {
      missingDebtRates += 1;
      continue;
    }
    if (debt.direction.isLent) {
      debtsOwedToMe += converted;
    } else {
      debtsIOwe += converted;
    }
  }

  return computeMoneyTotals(
    ledger: ledger,
    fx: fx,
    asOf: DateTime.now(),
    debtsOwedToMe: debtsOwedToMe,
    debtsIOwe: debtsIOwe,
    extraMissingRateCount: missingDebtRates,
  );
});

/// Debt totals for the debt screen (converted to the display currency).
final debtTotalsProvider = FutureProvider<DebtTotals>((ref) async {
  final debts = await ref.watch(debtsProvider.future);
  final base = ref.watch(defaultCurrencyProvider).code;
  final needsFx = debts.any(
    (debt) => debt.currency.trim().toUpperCase() != base.toUpperCase(),
  );
  final fx = needsFx
      ? (await ref.watch(exchangeRatesProvider.future)).snapshot
      : FxSnapshot(
          base: base,
          rates: const <String, double>{},
          fetchedAt: DateTime.now(),
        );
  var owedToMe = 0.0;
  var iOwe = 0.0;
  var missing = 0;
  for (final debt in debts) {
    if (debt.outstanding <= 0) continue;
    final converted = fx.convert(debt.outstanding, debt.currency, base);
    if (converted == null) {
      missing += 1;
      continue;
    }
    if (debt.direction.isLent) {
      owedToMe += converted;
    } else {
      iOwe += converted;
    }
  }
  return DebtTotals(
    owedToMe: owedToMe,
    iOwe: iOwe,
    missingRateCount: missing,
  );
});

/// In-app reminders for credit-card payments and debt due dates.
final remindersProvider = FutureProvider<List<ReminderItem>>((ref) async {
  final ledger = await ref.watch(walletLedgerProvider.future);
  final debts = await ref.watch(debtsProvider.future);
  final now = DateTime.now();
  final reminders = <ReminderItem>[];

  for (final account in ledger.all) {
    final wallet = account.wallet;
    if (wallet.archived || !wallet.isCredit || account.owed <= 0) continue;
    final due = account.nextDueDate(asOf: now);
    if (due == null || !isReminderActive(due, now)) continue;
    reminders.add(
      ReminderItem(
        id: 'card_${wallet.id}',
        kind: ReminderKind.creditCard,
        title: wallet.name,
        amount: account.owed,
        currency: wallet.currency,
        dueDate: due,
        sourceId: wallet.id,
      ),
    );
  }

  for (final debt in debts) {
    final due = debt.dueDate;
    if (due == null || debt.outstanding <= 0) continue;
    if (debt.status == DebtStatus.settled) continue;
    if (!isReminderActive(due, now)) continue;
    reminders.add(
      ReminderItem(
        id: 'debt_${debt.id}',
        kind: ReminderKind.debt,
        title: debt.counterparty,
        amount: debt.outstanding,
        currency: debt.currency,
        dueDate: due,
        sourceId: debt.id,
      ),
    );
  }

  reminders.sort((a, b) => a.dueDate.compareTo(b.dueDate));
  return reminders;
});

/// Pay-cycle anchors for the budget period: the source flagged by the user,
/// with the legacy local preference as a fallback when no source exists yet.
final budgetPayCycleProvider = Provider<PayCycleConfig>((ref) {
  final sources = ref.watch(incomeSourcesProvider).valueOrNull ??
      const <IncomeSource>[];
  return budgetDefiningSource(sources)?.config ?? ref.watch(payCycleProvider);
});

/// Plan + actual spending + pacing for a month, paced by the pay cycle.
///
/// For the current month the summary also carries the **current pay period**
/// (`daily` = today, `weekly` = this week, `monthly` = the payday-to-payday
/// month), so the dashboard can show how much is left until the next payday.
/// Past / future months fall back to the calendar month.
final budgetSummaryProvider = FutureProvider.family<BudgetSummary, DateTime>(
  (ref, month) async {
    final userId = ref.watch(userIdProvider);
    final config = ref.watch(budgetPayCycleProvider);
    final currencyCode = ref.watch(defaultCurrencyProvider).code;
    final sources =
        ref.watch(incomeSourcesProvider).valueOrNull ?? const <IncomeSource>[];
    final entries =
        ref.watch(incomeEntriesProvider).valueOrNull ?? const <IncomeEntry>[];
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

    final storedBudget = await ref.watch(budgetProvider(first).future);

    final isCurrentMonth = first.year == now.year && first.month == now.month;
    final period = isCurrentMonth ? config.periodFor(now) : null;
    final incomePeriod = period ??
        PayPeriod(start: first, end: monthEnd, cycle: config.cycle);
    final income = summarizeIncome(
      sources: sources,
      entries: entries,
      period: incomePeriod,
      month: first,
      currencyCode: currencyCode,
    );

    // Income sources are the source of truth for income; the stored plan's
    // salary is only a fallback for documents saved before this feature.
    MonthlyBudget? effectivePlan(MonthlyBudget? plan) {
      if (plan == null || sources.isEmpty) return plan;
      return plan.copyWith(
        salary: income.monthlyEquivalent,
        payCycle: config.cycle,
        incomePerCycle: budgetDefiningSource(sources)?.amountPerCycle,
      );
    }

    final budget = effectivePlan(storedBudget);

    // A monthly payday period that started last month (e.g. payday 25, today
    // Oct 3) was funded by last month's plan. Fall back to this month's plan
    // when that one is missing.
    var periodPlan = budget;
    if (period != null && config.isMonthly) {
      final periodMonth = firstDayOfMonth(period.start);
      if (periodMonth != first) {
        periodPlan = effectivePlan(
              await ref.watch(budgetProvider(periodMonth).future),
            ) ??
            budget;
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
      monthlyIncome: income.monthlyEquivalent,
      scheduledPeriodIncome: income.scheduledInPeriod,
      oneOffPeriodIncome: income.oneOffInPeriod,
      otherCurrencyIncomeCount: income.otherCurrencyCount,
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
