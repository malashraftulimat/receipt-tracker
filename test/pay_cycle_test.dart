import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/models/monthly_budget.dart';
import 'package:receipt_tracker/domain/models/pay_cycle.dart';

void main() {
  group('PayCycleConfig periods', () {
    test('monthly pay on the 1st is the calendar month', () {
      const config = PayCycleConfig();
      final period = config.periodFor(DateTime(2026, 10, 21, 15, 30));

      expect(period.start, DateTime(2026, 10, 1));
      expect(period.end, DateTime(2026, 11, 1));
      expect(period.days, 31);
      expect(period.label, 'paycycle.this_month');
      expect(period.contains(DateTime(2026, 10, 31, 23, 59)), isTrue);
      expect(period.contains(DateTime(2026, 11, 1)), isFalse);
      expect(period.daysElapsedOn(DateTime(2026, 10, 21)), 21);
      expect(period.daysRemainingOn(DateTime(2026, 10, 21)), 11);
    });

    test('monthly payday runs from payday to the day before the next', () {
      const config = PayCycleConfig(cycle: PayCycle.monthly, monthlyPayDay: 25);

      final before = config.periodFor(DateTime(2026, 10, 21));
      expect(before.start, DateTime(2026, 9, 25));
      expect(before.end, DateTime(2026, 10, 25));

      final onPayday = config.periodFor(DateTime(2026, 10, 25, 8));
      expect(onPayday.start, DateTime(2026, 10, 25));
      expect(onPayday.end, DateTime(2026, 11, 25));
      expect(onPayday.daysElapsedOn(DateTime(2026, 10, 25)), 1);
    });

    test('end-of-month payday clamps to the length of each month', () {
      const config = PayCycleConfig(
        cycle: PayCycle.monthly,
        monthlyPayDay: PayCycleConfig.endOfMonthPayDay,
      );

      final january = config.periodFor(DateTime(2026, 2, 10));
      expect(january.start, DateTime(2026, 1, 31));
      expect(january.end, DateTime(2026, 2, 28));

      final february = config.periodFor(DateTime(2026, 2, 28));
      expect(february.start, DateTime(2026, 2, 28));
      expect(february.end, DateTime(2026, 3, 31));

      final march = config.periodFor(DateTime(2026, 3, 31));
      expect(march.start, DateTime(2026, 3, 31));
      expect(march.end, DateTime(2026, 4, 30));
    });

    test('weekly pay starts on the configured weekday', () {
      const config = PayCycleConfig(
        cycle: PayCycle.weekly,
        weeklyStartWeekday: DateTime.monday,
      );
      final date = DateTime(2026, 10, 21, 15, 30);
      final period = config.periodFor(date);

      expect(period.start.weekday, DateTime.monday);
      expect(period.days, 7);
      expect(period.contains(date), isTrue);
      expect(period.start.isAfter(date), isFalse);
      expect(period.end.isAfter(date), isTrue);
      expect(period.label, 'paycycle.this_week');

      // Every day of the week maps to the same period.
      for (var i = 0; i < period.days; i++) {
        expect(config.periodFor(addDays(period.start, i)).start, period.start);
      }
      expect(
        config.periodFor(addDays(period.start, 7)).start,
        addDays(period.start, 7),
      );
    });

    test('daily pay is a single day', () {
      const config = PayCycleConfig(cycle: PayCycle.daily);
      final period = config.periodFor(DateTime(2026, 10, 21, 9));

      expect(period.start, DateTime(2026, 10, 21));
      expect(period.end, DateTime(2026, 10, 22));
      expect(period.days, 1);
      expect(period.label, 'paycycle.today');
      expect(period.contains(DateTime(2026, 10, 21, 23, 59)), isTrue);
      expect(period.contains(DateTime(2026, 10, 22)), isFalse);
      expect(period.daysElapsedOn(DateTime(2026, 10, 21, 23)), 1);
      expect(period.daysRemainingOn(DateTime(2026, 10, 21)), 1);
    });
  });

  group('PayCycleConfig conversions', () {
    test('daily income scales with the days of the month', () {
      const config = PayCycleConfig(cycle: PayCycle.daily);
      expect(config.monthlyEquivalent(10000, DateTime(2026, 10)), 310000);
      expect(config.perCycleEquivalent(310000, DateTime(2026, 10)), 10000);
      expect(config.monthlyEquivalent(9000, DateTime(2026, 2)), 252000);
    });

    test('weekly income uses days ÷ 7 periods', () {
      const config = PayCycleConfig(cycle: PayCycle.weekly);
      expect(config.periodsInMonth(DateTime(2026, 2)), 4);
      expect(config.monthlyEquivalent(50000, DateTime(2026, 2)), 200000);
      expect(config.perCycleEquivalent(200000, DateTime(2026, 2)), 50000);
    });

    test('monthly income is unchanged', () {
      const config = PayCycleConfig();
      expect(config.monthlyEquivalent(250000, DateTime(2026, 10)), 250000);
      expect(config.perCycleEquivalent(250000, DateTime(2026, 10)), 250000);
    });

    test('json round trip', () {
      const config = PayCycleConfig(
        cycle: PayCycle.weekly,
        weeklyStartWeekday: DateTime.sunday,
        monthlyPayDay: 25,
      );
      final restored = PayCycleConfig.fromJson(config.toJson());
      expect(restored.cycle, PayCycle.weekly);
      expect(restored.weeklyStartWeekday, DateTime.sunday);
      expect(restored.monthlyPayDay, 25);

      // Unknown / corrupt values fall back to safe defaults.
      final fallback = PayCycleConfig.fromJson(const <String, Object?>{
        'cycle': 'hourly',
        'weekly_start_weekday': 42,
        'monthly_pay_day': 99,
      });
      expect(fallback.cycle, PayCycle.monthly);
      expect(fallback.weeklyStartWeekday, 7);
      expect(fallback.monthlyPayDay, PayCycleConfig.endOfMonthPayDay);
    });
  });

  group('MonthlyBudget pay cycle fields', () {
    test('per-cycle income survives a json round trip', () {
      final budget = MonthlyBudget(
        month: DateTime(2026, 10),
        salary: 310000,
        payCycle: PayCycle.daily,
        incomePerCycle: 10000,
      );
      final restored = MonthlyBudget.fromJson(<String, dynamic>{
        ...budget.toRow(),
        'id': '2026-10',
      });

      expect(restored.salary, 310000);
      expect(restored.payCycle, PayCycle.daily);
      expect(restored.incomePerCycle, 10000);
    });

    test('plans saved before the cycle existed stay monthly', () {
      final restored = MonthlyBudget.fromJson(<String, dynamic>{
        'month': '2026-10-01T00:00:00.000Z',
        'salary': 250000,
      });
      expect(restored.payCycle, isNull);
      expect(restored.incomePerCycle, isNull);
      expect(restored.disposableIncome, 250000);
    });
  });

  group('BudgetSummary pay period', () {
    final budget = MonthlyBudget(
      month: DateTime(2026, 10),
      salary: 310000,
      savingsGoal: 0,
      fixedExpenses: 0,
    );

    BudgetSummary weeklySummary({double periodSpent = 15000}) => BudgetSummary(
          month: DateTime(2026, 10),
          budget: budget,
          spent: 150000,
          receiptCount: 4,
          daysInMonth: 31,
          daysElapsed: 21,
          todaySpent: 2000,
          payCycle: PayCycle.weekly,
          periodStart: DateTime(2026, 10, 19),
          periodEnd: DateTime(2026, 10, 26),
          periodDays: 7,
          periodDaysElapsed: 3,
          periodBudget: 70000,
          periodSpent: periodSpent,
        );

    test('period numbers drive the dashboard while the month stays intact', () {
      final summary = weeklySummary();

      expect(summary.cycleBudget, 70000);
      expect(summary.cycleSpent, 15000);
      expect(summary.periodRemaining, 55000);
      expect(summary.periodDaysRemaining, 5);
      expect(summary.dailyAllowance, 11000);
      expect(summary.periodProgress, closeTo(15000 / 70000, 1e-9));
      expect(summary.periodStatus, BudgetStatus.onTrack);
      expect(summary.periodRemainingLabel, 'remaining_budget_this_week');

      // Calendar-month view is untouched.
      expect(summary.remaining, 160000);
      expect(summary.progress, closeTo(150000 / 310000, 1e-9));
    });

    test('overspending the pay period is flagged', () {
      final summary = weeklySummary(periodSpent: 80000);

      expect(summary.periodRemaining, -10000);
      expect(summary.dailyAllowance, 0);
      expect(summary.periodStatus, BudgetStatus.overBudget);
    });

    test('without a period the month is the period', () {
      final summary = BudgetSummary(
        month: DateTime(2026, 10),
        budget: budget,
        spent: 60000,
        receiptCount: 5,
        daysInMonth: 30,
        daysElapsed: 10,
        todaySpent: 2000,
      );

      expect(summary.periodRemaining, summary.remaining);
      expect(summary.periodDaysRemaining, summary.daysRemaining);
      expect(summary.periodProgress, summary.progress);
      expect(summary.dailyAllowance, summary.remaining ~/ summary.daysRemaining);
      expect(summary.periodStatus, summary.status);
    });
  });
}
