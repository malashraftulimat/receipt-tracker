import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/models/income_entry.dart';
import 'package:receipt_tracker/domain/models/income_source.dart';
import 'package:receipt_tracker/domain/models/income_summary.dart';
import 'package:receipt_tracker/domain/models/monthly_budget.dart';
import 'package:receipt_tracker/domain/models/pay_cycle.dart';

IncomeSource source({
  String id = 's1',
  String name = 'Main',
  PayCycle cycle = PayCycle.monthly,
  int weekday = DateTime.monday,
  int payDay = 25,
  double amount = 200000,
  String currency = 'JPY',
  bool active = true,
  bool defines = false,
}) {
  final now = DateTime(2026, 10, 1);
  return IncomeSource(
    id: id,
    name: name,
    cycle: cycle,
    weeklyStartWeekday: weekday,
    monthlyPayDay: payDay,
    amountPerCycle: amount,
    currency: currency,
    active: active,
    definesBudgetPeriod: defines,
    createdAt: now,
    updatedAt: now,
  );
}

IncomeEntry entry({
  double amount = 5000,
  String currency = 'JPY',
  DateTime? receivedAt,
  String source = 'Sold an item',
}) {
  final at = receivedAt ?? DateTime(2026, 10, 20, 12);
  return IncomeEntry(
    id: 'e1',
    userId: 'u1',
    amount: amount,
    currency: currency,
    receivedAt: at,
    source: source,
    createdAt: at,
    updatedAt: at,
  );
}

void main() {
  group('IncomeSource', () {
    test('json round trip keeps cycle, payday, amount and flags', () {
      final original = source(
        id: 'job',
        name: 'Part-time',
        cycle: PayCycle.weekly,
        weekday: DateTime.friday,
        payDay: 10,
        amount: 12000,
        currency: 'usd',
        active: false,
        defines: true,
      );
      final restored = IncomeSource.fromJson(<String, dynamic>{
        ...original.toRow(),
        'id': original.id,
      });

      expect(restored.id, 'job');
      expect(restored.name, 'Part-time');
      expect(restored.cycle, PayCycle.weekly);
      expect(restored.weeklyStartWeekday, DateTime.friday);
      expect(restored.monthlyPayDay, 10);
      expect(restored.amountPerCycle, 12000);
      expect(restored.currency, 'USD');
      expect(restored.active, isFalse);
      expect(restored.definesBudgetPeriod, isTrue);
    });

    test('monthly equivalent follows each cycle', () {
      expect(
        source(cycle: PayCycle.daily, amount: 10000)
            .monthlyEquivalent(DateTime(2026, 10)),
        310000,
      );
      expect(
        source(cycle: PayCycle.weekly, amount: 50000)
            .monthlyEquivalent(DateTime(2026, 2)),
        200000,
      );
      expect(
        source(cycle: PayCycle.monthly, amount: 250000)
            .monthlyEquivalent(DateTime(2026, 10)),
        250000,
      );
    });

    test('paydays inside a period', () {
      final period = PayPeriod(
        start: DateTime(2026, 9, 25),
        end: DateTime(2026, 10, 25),
        cycle: PayCycle.monthly,
      );

      expect(
        source(cycle: PayCycle.daily).paydaysIn(period).length,
        period.days,
      );
      expect(
        source(cycle: PayCycle.weekly, weekday: DateTime.monday)
            .paydaysIn(period)
            .length,
        4,
      );
      expect(
        source(cycle: PayCycle.monthly, payDay: 25).paydaysIn(period),
        <DateTime>[DateTime(2026, 9, 25)],
      );
      expect(
        source(cycle: PayCycle.monthly, payDay: 10).paydaysIn(period),
        <DateTime>[DateTime(2026, 10, 10)],
      );
      expect(
        source(
          cycle: PayCycle.monthly,
          payDay: PayCycleConfig.endOfMonthPayDay,
        ).paydaysIn(period),
        <DateTime>[DateTime(2026, 9, 30)],
      );
    });

    test('exactly one source is flagged as the budget anchor', () {
      final normalized = normalizeBudgetPeriodFlag(<IncomeSource>[
        source(id: 'a', defines: false),
        source(id: 'b', defines: true),
        source(id: 'c', defines: true),
      ]);
      expect(
        normalized.where((item) => item.definesBudgetPeriod).map((e) => e.id),
        <String>['b'],
      );

      final promoted = normalizeBudgetPeriodFlag(<IncomeSource>[
        source(id: 'a'),
        source(id: 'b'),
      ]);
      expect(promoted.first.definesBudgetPeriod, isTrue);
      expect(promoted[1].definesBudgetPeriod, isFalse);
      expect(normalizeBudgetPeriodFlag(<IncomeSource>[]), isEmpty);
    });

    test('budgetDefiningSource prefers the flag, then an active source', () {
      expect(
        budgetDefiningSource(<IncomeSource>[
          source(id: 'a', active: false, defines: false),
          source(id: 'b', active: true, defines: false),
          source(id: 'c', active: false, defines: true),
        ])?.id,
        'c',
      );
      expect(
        budgetDefiningSource(<IncomeSource>[
          source(id: 'a', active: false),
          source(id: 'b', active: true),
        ])?.id,
        'b',
      );
      expect(budgetDefiningSource(<IncomeSource>[]), isNull);
    });

    test('legacy single cycle migrates to one source named Main', () {
      final legacy = legacyIncomeSource(
        legacyConfig: const PayCycleConfig(
          cycle: PayCycle.monthly,
          monthlyPayDay: 25,
        ),
        latestBudget: MonthlyBudget(
          month: DateTime(2026, 10),
          salary: 300000,
          payCycle: PayCycle.monthly,
          incomePerCycle: 300000,
        ),
        currency: 'JPY',
        createdAt: DateTime(2026, 10, 1),
      );

      expect(legacy.name, 'Main');
      expect(legacy.cycle, PayCycle.monthly);
      expect(legacy.monthlyPayDay, 25);
      expect(legacy.amountPerCycle, 300000);
      expect(legacy.definesBudgetPeriod, isTrue);
      expect(legacy.active, isTrue);
    });

    test('legacy migration converts a weekly plan back to per-cycle pay', () {
      final legacy = legacyIncomeSource(
        legacyConfig: const PayCycleConfig(
          cycle: PayCycle.weekly,
          weeklyStartWeekday: DateTime.friday,
        ),
        latestBudget: MonthlyBudget(
          month: DateTime(2026, 10),
          salary: 200000,
          payCycle: PayCycle.weekly,
        ),
        currency: 'JPY',
        createdAt: DateTime(2026, 10, 1),
      );

      expect(legacy.cycle, PayCycle.weekly);
      expect(legacy.weeklyStartWeekday, DateTime.friday);
      expect(legacy.amountPerCycle, closeTo(45161.2903, 0.01));
    });
  });

  group('IncomeSummary', () {
    final period = PayPeriod(
      start: DateTime(2026, 10, 1),
      end: DateTime(2026, 10, 31),
      cycle: PayCycle.monthly,
    );

    test('counts recurring paydays in the period and one-off entries', () {
      final summary = summarizeIncome(
        sources: <IncomeSource>[
          source(id: 'salary', amount: 200000, payDay: 25, defines: true),
          source(id: 'job', cycle: PayCycle.weekly, amount: 10000),
          source(id: 'inactive', amount: 999999, active: false),
        ],
        entries: <IncomeEntry>[entry(amount: 5000)],
        period: period,
        month: DateTime(2026, 10),
        currencyCode: 'JPY',
      );

      expect(summary.scheduledInPeriod, 200000 + 4 * 10000);
      expect(summary.oneOffInPeriod, 5000);
      expect(summary.periodTotal, 245000);
      expect(summary.monthlyEquivalent, closeTo(244285.714, 0.01));
      expect(summary.otherCurrencyCount, 0);
    });

    test('excludes other currencies instead of guessing a rate', () {
      final summary = summarizeIncome(
        sources: <IncomeSource>[source(currency: 'USD')],
        entries: <IncomeEntry>[
          entry(amount: 5000),
          entry(amount: 100, currency: 'USD'),
        ],
        period: period,
        month: DateTime(2026, 10),
        currencyCode: 'JPY',
      );

      expect(summary.monthlyEquivalent, 0);
      expect(summary.oneOffInPeriod, 5000);
      expect(summary.otherCurrencyCount, 2);
    });
  });

  group('IncomeEntry', () {
    test('json round trip and previous source suggestions', () {
      final first = entry(source: 'Sold an item');
      final restored = IncomeEntry.fromJson(<String, dynamic>{
        ...first.toRow(),
        'id': 'e1',
        'user_id': 'u1',
      });
      expect(restored.amount, 5000);
      expect(restored.source, 'Sold an item');
      expect(restored.currency, 'JPY');
      expect(restored.receivedAt, DateTime(2026, 10, 20, 12));

      final suggestions = previousIncomeSources(<IncomeEntry>[
        entry(source: 'Open Campus shift'),
        entry(source: 'sold an item'),
        entry(source: 'Open Campus shift'),
        entry(source: '  '),
      ]);
      expect(suggestions, <String>['Open Campus shift', 'sold an item']);
    });
  });
}
