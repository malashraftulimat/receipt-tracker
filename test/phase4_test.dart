import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/full_export_service.dart';
import 'package:receipt_tracker/domain/models/debt.dart';
import 'package:receipt_tracker/domain/models/income_entry.dart';
import 'package:receipt_tracker/domain/models/income_source.dart';
import 'package:receipt_tracker/domain/models/monthly_budget.dart';
import 'package:receipt_tracker/domain/models/pay_cycle.dart';
import 'package:receipt_tracker/domain/models/receipt.dart';
import 'package:receipt_tracker/domain/models/recurring_transaction.dart';
import 'package:receipt_tracker/domain/models/wallet.dart';
import 'package:receipt_tracker/domain/models/wallet_adjustment.dart';
import 'package:receipt_tracker/domain/models/wallet_spending.dart';
import 'package:receipt_tracker/domain/models/wallet_transfer.dart';

final created = DateTime(2026, 10, 1);

Wallet wallet({
  String id = 'w1',
  String name = 'Cash',
  String currency = 'JPY',
  double opening = 0,
}) {
  return Wallet(
    id: id,
    name: name,
    currency: currency,
    openingBalance: opening,
    createdAt: created,
    updatedAt: created,
  );
}

Receipt receipt({
  String id = 'r1',
  String? walletId,
  double amount = 1000,
  String currency = 'JPY',
  String? categoryId,
  DateTime? at,
}) {
  final date = at ?? DateTime(2026, 10, 10);
  return Receipt(
    id: id,
    userId: 'u1',
    merchant: 'Shop',
    currency: currency,
    purchasedAt: date,
    totalAmount: amount,
    walletId: walletId,
    categoryId: categoryId,
    createdAt: date,
    updatedAt: date,
  );
}

RecurringTransaction recurring({
  String id = 'rec1',
  RecurringDirection direction = RecurringDirection.expense,
  double amount = 1000,
  PayCycle cycle = PayCycle.monthly,
  int payDay = 25,
  int weekday = DateTime.friday,
  DateTime? start,
  DateTime? lastPosted,
  bool active = true,
}) {
  return RecurringTransaction(
    id: id,
    userId: 'u1',
    name: 'Rent',
    direction: direction,
    amount: amount,
    cycle: cycle,
    monthlyPayDay: payDay,
    weeklyStartWeekday: weekday,
    startDate: start ?? DateTime(2026, 1, 1),
    lastPostedAt: lastPosted,
    active: active,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('Budget limits', () {
    test('overall limit and category limits survive json', () {
      final budget = MonthlyBudget(
        month: DateTime(2026, 10),
        salary: 300000,
        savingsGoal: 20000,
        fixedExpenses: 80000,
        overallLimit: 180000,
        categoryLimits: <String, double>{'food': 40000, 'transport': 10000},
      );
      final restored = MonthlyBudget.fromJson(<String, dynamic>{
        ...budget.toRow(),
        'id': '2026-10',
      });
      expect(restored.overallLimit, 180000);
      expect(restored.categoryLimits['food'], 40000);
      expect(restored.monthlyLimit, 180000);
      expect(restored.disposableIncome, 200000);
    });

    test('missing overall limit falls back to disposable income', () {
      final budget = MonthlyBudget(
        month: DateTime(2026, 10),
        salary: 300000,
        savingsGoal: 20000,
        fixedExpenses: 80000,
      );
      expect(budget.monthlyLimit, 200000);
    });

    test('80% and 100% limits are warning and over', () {
      expect(limitStatus(0, 1000), LimitStatus.ok);
      expect(limitStatus(799, 1000), LimitStatus.ok);
      expect(limitStatus(800, 1000), LimitStatus.warning);
      expect(limitStatus(999, 1000), LimitStatus.warning);
      expect(limitStatus(1000, 1000), LimitStatus.over);
      expect(limitStatus(1200, 1000), LimitStatus.over);
      expect(limitStatus(1200, 0), LimitStatus.none);
    });
  });

  group('Per-wallet spending', () {
    test('sums matching-currency spending and unassigned receipts', () {
      final spending = spendingByWallet(
        receipts: <Receipt>[
          receipt(id: 'a', walletId: 'cash', amount: 1000),
          receipt(id: 'b', walletId: 'cash', amount: 500),
          receipt(id: 'c', walletId: 'usd', amount: 20, currency: 'USD'),
          receipt(id: 'd', amount: 300),
          receipt(
            id: 'e',
            walletId: 'cash',
            amount: 9000,
            at: DateTime(2026, 11, 1),
          ),
        ],
        wallets: <Wallet>[
          wallet(id: 'cash'),
          wallet(id: 'usd', currency: 'USD'),
        ],
        monthStart: DateTime(2026, 10, 1),
        monthEnd: DateTime(2026, 11, 1),
      );
      expect(spending.byWallet['cash'], 1500);
      expect(spending.byWallet['usd'], 20);
      expect(spending.unassigned, 300);
    });
  });

  group('Recurring occurrences', () {
    test('monthly payday, start date and last posted date', () {
      final item = recurring(
        payDay: 25,
        start: DateTime(2026, 9, 1),
      );
      expect(
        item.occurrencesBetween(
          DateTime(2026, 10, 1),
          DateTime(2026, 11, 30),
        ),
        <DateTime>[DateTime(2026, 10, 25), DateTime(2026, 11, 25)],
      );
      expect(
        recurring(
          payDay: 25,
          start: DateTime(2026, 10, 26),
        ).occurrencesBetween(DateTime(2026, 10, 1), DateTime(2026, 11, 30)),
        <DateTime>[DateTime(2026, 11, 25)],
      );
    });

    test('weekly and daily occurrences', () {
      final weekly = recurring(
        cycle: PayCycle.weekly,
        weekday: DateTime.friday,
        start: DateTime(2026, 10, 1),
      );
      expect(
        weekly.occurrencesBetween(
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 16),
        ),
        <DateTime>[
          DateTime(2026, 10, 2),
          DateTime(2026, 10, 9),
          DateTime(2026, 10, 16),
        ],
      );
      final daily = recurring(
        cycle: PayCycle.daily,
        start: DateTime(2026, 10, 1),
      );
      expect(
        daily.occurrencesBetween(
          DateTime(2026, 10, 1),
          DateTime(2026, 10, 3),
        ),
        <DateTime>[DateTime(2026, 10, 2), DateTime(2026, 10, 3)],
      );
    });

    test('next occurrence and inactive flag', () {
      final item = recurring(payDay: 25, start: DateTime(2026, 1, 1));
      expect(
        item.nextOccurrence(after: DateTime(2026, 10, 26)),
        DateTime(2026, 11, 25),
      );
      expect(
        recurring(active: false).occurrencesBetween(
          DateTime(2026, 1, 1),
          DateTime(2026, 12, 31),
        ),
        isNotEmpty,
      );
    });
  });

  group('Full CSV export', () {
    test('contains every record type and escaped values', () {
      final cash = wallet(id: 'cash', name: 'Cash, wallet', opening: 1000);
      final csv = FullExportService.buildCsv(
        wallets: <Wallet>[cash],
        receipts: <Receipt>[
          receipt(walletId: 'cash', amount: 500, categoryId: 'food'),
        ],
        incomeSources: <IncomeSource>[
          IncomeSource(
            id: 'source1',
            name: 'Main',
            amountPerCycle: 200000,
            currency: 'JPY',
            createdAt: created,
            updatedAt: created,
          ),
        ],
        incomeEntries: <IncomeEntry>[
          IncomeEntry(
            id: 'income1',
            userId: 'u1',
            amount: 3000,
            receivedAt: created,
            source: 'Sold an item',
            createdAt: created,
            updatedAt: created,
          ),
        ],
        transfers: <WalletTransfer>[
          WalletTransfer(
            id: 'transfer1',
            userId: 'u1',
            fromWalletId: 'cash',
            toWalletId: 'cash',
            fromAmount: 100,
            toAmount: 100,
            occurredAt: created,
            createdAt: created,
            updatedAt: created,
          ),
        ],
        adjustments: <WalletAdjustment>[
          WalletAdjustment(
            id: 'adjust1',
            userId: 'u1',
            walletId: 'cash',
            amount: 50,
            occurredAt: created,
            createdAt: created,
            updatedAt: created,
          ),
        ],
        debts: <Debt>[
          Debt(
            id: 'debt1',
            userId: 'u1',
            direction: DebtDirection.iLent,
            counterparty: 'Alex',
            amount: 5000,
            date: created,
            repayments: <DebtRepayment>[
              DebtRepayment(id: 'rep1', amount: 1000, date: created),
            ],
            status: DebtStatus.partial,
            createdAt: created,
            updatedAt: created,
          ),
        ],
        recurring: <RecurringTransaction>[recurring()],
      );
      final lines = csv.split('\r\n');
      expect(lines.first, startsWith('record_type,id,date,name'));
      for (final type in <String>[
        'wallet',
        'transaction',
        'income_source',
        'debt',
        'debt_repayment',
        'recurring',
      ]) {
        expect(csv, contains('$type,'));
      }
      expect(csv, contains('"Cash, wallet"'));
      expect(lines.length, greaterThanOrEqualTo(10));
    });
  });
}
