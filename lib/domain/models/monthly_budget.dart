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
  });

  final String? id;
  final String? userId;

  /// First day of the month (local time).
  final DateTime month;

  /// 手取りの月収.
  final int salary;

  /// 毎月の貯蓄目標.
  final int savingsGoal;

  /// 家賃・光熱費・サブスクなど固定費の合計.
  final int fixedExpenses;

  final String? note;

  /// 自由に使える金額 = 給与 - 貯蓄目標 - 固定費.
  int get disposableIncome => salary - savingsGoal - fixedExpenses;

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
      salary: (json['salary'] as num?)?.toInt() ?? 0,
      savingsGoal: (json['savings_goal'] as num?)?.toInt() ?? 0,
      fixedExpenses: (json['fixed_expenses'] as num?)?.toInt() ?? 0,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'user_id': userId,
        'month': _monthIso,
        'salary': salary,
        'savings_goal': savingsGoal,
        'fixed_expenses': fixedExpenses,
        'note': note,
      };

  String get _monthIso {
    final first = DateTime(month.year, month.month, 1);
    return first.toUtc().toIso8601String();
  }

  MonthlyBudget copyWith({
    int? salary,
    int? savingsGoal,
    int? fixedExpenses,
    String? note,
  }) {
    return MonthlyBudget(
      id: id,
      userId: userId,
      month: month,
      salary: salary ?? this.salary,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      fixedExpenses: fixedExpenses ?? this.fixedExpenses,
      note: note ?? this.note,
    );
  }
}

enum BudgetStatus { unset, onTrack, warning, overBudget }

/// Budget plan + actual spending for one month, computed on the client.
class BudgetSummary {
  const BudgetSummary({
    required this.month,
    required this.budget,
    required this.spent,
    required this.receiptCount,
    required this.daysInMonth,
    required this.daysElapsed,
    required this.todaySpent,
  });

  final DateTime month;
  final MonthlyBudget? budget;
  final int spent;
  final int receiptCount;
  final int daysInMonth;
  final int daysElapsed;
  final int todaySpent;

  bool get configured => budget?.isConfigured ?? false;

  int get disposable => budget?.disposableIncome ?? 0;

  int get remaining => disposable - spent;

  /// Days left including today.
  int get daysRemaining {
    final left = daysInMonth - daysElapsed + 1;
    return left < 1 ? 1 : left;
  }

  /// How much can still be spent per remaining day.
  int get dailyAllowance {
    if (!configured) return 0;
    return remaining <= 0 ? 0 : remaining ~/ daysRemaining;
  }

  /// 0..1+ progress of the disposable budget.
  double get progress {
    if (!configured || disposable <= 0) return 0;
    return spent / disposable;
  }

  double get savingsProgress {
    final goal = budget?.savingsGoal ?? 0;
    if (goal <= 0) return 0;
    final saved = (disposable - spent).clamp(0, goal);
    return saved / goal;
  }

  /// Expected spend by today if the budget were spread evenly.
  int get expectedSpentByToday {
    if (!configured) return 0;
    return (disposable * daysElapsed / daysInMonth).round();
  }

  /// Positive = spending faster than plan.
  int get velocityDelta => spent - expectedSpentByToday;

  BudgetStatus get status {
    if (!configured) return BudgetStatus.unset;
    if (remaining < 0) return BudgetStatus.overBudget;
    if (progress >= 0.9 || velocityDelta > disposable * 0.15) {
      return BudgetStatus.warning;
    }
    return BudgetStatus.onTrack;
  }

  String get statusLabel {
    switch (status) {
      case BudgetStatus.unset:
        return '予算未設定';
      case BudgetStatus.onTrack:
        return '順調';
      case BudgetStatus.warning:
        return 'ペース注意';
      case BudgetStatus.overBudget:
        return '予算オーバー';
    }
  }
}
