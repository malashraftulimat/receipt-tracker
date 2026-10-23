import 'pay_cycle.dart';

/// Per-month income / savings / fixed-expense plan.
class MonthlyBudget {
  const MonthlyBudget({
    required this.month,
    this.id,
    this.userId,
    this.salary = 0,
    this.savingsGoal = 0,
    this.fixedExpenses = 0,
    this.note,
    this.payCycle,
    this.incomePerCycle,
  });

  final String? id;
  final String? userId;

  /// First day of the month (local time).
  final DateTime month;

  /// 手取りの月収（[incomePerCycle] を月換算した値）.
  final num salary;

  /// 毎月の貯蓄目標.
  final num savingsGoal;

  /// 家賃・光熱費・サブスクなど固定費の合計.
  final num fixedExpenses;

  final String? note;

  /// 保存したときに使っていた給与サイクル（未設定なら月給扱い）.
  final PayCycle? payCycle;

  /// ユーザーが入力した「1サイクルあたり」の手取り額.
  ///
  /// [salary] はこれを月換算した値なので、日払い・週払いでも丸め誤差なく
  /// 入力した金額をそのまま再表示できる。
  final num? incomePerCycle;

  /// 自由に使える金額 = 給与 - 貯蓄目標 - 固定費.
  num get disposableIncome => salary - savingsGoal - fixedExpenses;

  bool get isConfigured => salary > 0;

  factory MonthlyBudget.fromJson(Map<String, dynamic> json) {
    final rawMonth = json['month'];
    final parsedMonth = rawMonth is DateTime
        ? rawMonth
        : DateTime.tryParse(rawMonth?.toString() ?? '') ?? DateTime.now();
    return MonthlyBudget(
      id: json['id'] as String?,
      userId: json['user_id'] as String?,
      month: DateTime(parsedMonth.toLocal().year, parsedMonth.toLocal().month),
      salary: (json['salary'] as num?) ?? 0,
      savingsGoal: (json['savings_goal'] as num?) ?? 0,
      fixedExpenses: (json['fixed_expenses'] as num?) ?? 0,
      note: json['note'] as String?,
      payCycle: _parsePayCycle(json['pay_cycle']),
      incomePerCycle: json['income_per_cycle'] as num?,
    );
  }

  static PayCycle? _parsePayCycle(Object? raw) {
    for (final cycle in PayCycle.values) {
      if (cycle.name == raw) return cycle;
    }
    return null;
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'user_id': userId,
        'month': _monthIso,
        'salary': salary,
        'savings_goal': savingsGoal,
        'fixed_expenses': fixedExpenses,
        'note': note,
        'pay_cycle': payCycle?.name,
        'income_per_cycle': incomePerCycle,
      };

  String get _monthIso {
    final first = DateTime(month.year, month.month, 1);
    return first.toUtc().toIso8601String();
  }

  MonthlyBudget copyWith({
    num? salary,
    num? savingsGoal,
    num? fixedExpenses,
    String? note,
    PayCycle? payCycle,
    num? incomePerCycle,
  }) {
    return MonthlyBudget(
      id: id,
      userId: userId,
      month: month,
      salary: salary ?? this.salary,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      fixedExpenses: fixedExpenses ?? this.fixedExpenses,
      note: note ?? this.note,
      payCycle: payCycle ?? this.payCycle,
      incomePerCycle: incomePerCycle ?? this.incomePerCycle,
    );
  }
}

enum BudgetStatus { unset, onTrack, warning, overBudget }

/// Budget plan + actual spending for one month, computed on the client.
///
/// The monthly numbers ([spent], [disposable], [remaining]) always cover the
/// calendar month. The `period*` getters cover the **current pay period**
/// (today / this week / this month, depending on the user's [payCycle]), which
/// is what a daily- or weekly-paid user needs to see. When no period is given
/// the period falls back to the whole month, preserving the original numbers.
class BudgetSummary {
  const BudgetSummary({
    required this.month,
    required this.budget,
    required this.spent,
    required this.receiptCount,
    required this.daysInMonth,
    required this.daysElapsed,
    required this.todaySpent,
    this.payCycle = PayCycle.monthly,
    this.periodStart,
    this.periodEnd,
    this.periodDays,
    this.periodDaysElapsed,
    this.periodBudget,
    this.periodSpent,
    this.otherCurrencyCount = 0,
  });

  final DateTime month;
  final MonthlyBudget? budget;
  final double spent;
  final int receiptCount;
  final int daysInMonth;
  final int daysElapsed;
  final double todaySpent;

  /// Salary cycle the plan is paced against.
  final PayCycle payCycle;

  /// Current pay period (local midnight); `null` = calendar month.
  final DateTime? periodStart;

  /// Exclusive end of the current pay period.
  final DateTime? periodEnd;

  final int? periodDays;
  final int? periodDaysElapsed;

  /// Amount available for the current pay period.
  final double? periodBudget;

  /// Spending inside the current pay period.
  final double? periodSpent;

  /// Receipts in this month that use a different currency and are excluded
  /// from the totals above.
  final int otherCurrencyCount;

  /// True when this month or the current pay period has a plan.
  bool get configured => (budget?.isConfigured ?? false) || cycleBudget != 0;

  double get disposable => (budget?.disposableIncome ?? 0).toDouble();

  double get remaining => disposable - spent;

  /// Days left including today.
  int get daysRemaining {
    final left = daysInMonth - daysElapsed + 1;
    return left < 1 ? 1 : left;
  }

  // --- current pay period ------------------------------------------------

  double get cycleBudget => periodBudget ?? disposable;

  double get cycleSpent => periodSpent ?? spent;

  double get periodRemaining => cycleBudget - cycleSpent;

  int get cycleDays => periodDays ?? daysInMonth;

  int get cycleDaysElapsed => periodDaysElapsed ?? daysElapsed;

  /// Days left in the current pay period including today.
  int get periodDaysRemaining {
    final left = cycleDays - cycleDaysElapsed + 1;
    return left < 1 ? 1 : left;
  }

  /// 0..1+ progress of the current pay period's budget.
  double get periodProgress {
    if (!configured || cycleBudget <= 0) return 0;
    return cycleSpent / cycleBudget;
  }

  /// Expected spending by today inside the current pay period.
  double get periodExpectedSpent {
    if (!configured) return 0;
    return cycleBudget * cycleDaysElapsed / cycleDays;
  }

  /// Positive = spending faster than the pay-period plan.
  double get periodVelocityDelta => cycleSpent - periodExpectedSpent;

  /// '今日の残り予算' / '今週の残り予算' / '今月の残り予算'.
  String get periodRemainingLabel => switch (payCycle) {
        PayCycle.daily => 'remaining_budget_today',
        PayCycle.weekly => 'remaining_budget_this_week',
        PayCycle.monthly => 'remaining_budget_this_month',
      };

  BudgetStatus get periodStatus {
    if (!configured) return BudgetStatus.unset;
    if (periodRemaining < 0) return BudgetStatus.overBudget;
    if (periodProgress >= 0.9 ||
        periodVelocityDelta > cycleBudget * 0.15) {
      return BudgetStatus.warning;
    }
    return BudgetStatus.onTrack;
  }

  /// How much can still be spent per remaining day of the pay period.
  int get dailyAllowance {
    if (!configured) return 0;
    final remainingNow = periodRemaining;
    return remainingNow <= 0
        ? 0
        : remainingNow.floor() ~/ periodDaysRemaining;
  }

  /// 0..1+ progress of the disposable budget.
  double get progress {
    if (!configured || disposable <= 0) return 0;
    return spent / disposable;
  }

  double get savingsProgress {
    final goal = (budget?.savingsGoal ?? 0).toDouble();
    if (goal <= 0) return 0;
    final saved = (disposable - spent).clamp(0.0, goal);
    return saved / goal;
  }

  /// Expected spend by today if the budget were spread evenly.
  int get expectedSpentByToday {
    if (!configured) return 0;
    return (disposable * daysElapsed / daysInMonth).round();
  }

  /// Positive = spending faster than plan.
  double get velocityDelta => spent - expectedSpentByToday;

  BudgetStatus get status {
    if (!configured) return BudgetStatus.unset;
    if (remaining < 0) return BudgetStatus.overBudget;
    if (progress >= 0.9 || velocityDelta > disposable * 0.15) {
      return BudgetStatus.warning;
    }
    return BudgetStatus.onTrack;
  }

  String get statusLabel => _labelFor(status);

  /// Status of the current pay period (today / week / month).
  String get periodStatusLabel => _labelFor(periodStatus);

  static String _labelFor(BudgetStatus status) {
    switch (status) {
      case BudgetStatus.unset:
        return 'budget_not_set';
      case BudgetStatus.onTrack:
        return 'on_track';
      case BudgetStatus.warning:
        return 'watch_spending_pace';
      case BudgetStatus.overBudget:
        return 'over_budget_2';
    }
  }
}
