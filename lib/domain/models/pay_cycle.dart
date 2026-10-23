/// How the user's income arrives: every day, every week or once a month.
///
/// The cycle only changes how the budget is *paced* (how much of the plan is
/// available right now, and how many days it has to last). Amounts stay stored
/// as monthly figures, so switching the cycle never rewrites saved plans.
enum PayCycle { daily, weekly, monthly }

/// Pay cycle plus the anchor day used to find the current pay period.
class PayCycleConfig {
  const PayCycleConfig({
    this.cycle = PayCycle.monthly,
    this.weeklyStartWeekday = DateTime.monday,
    this.monthlyPayDay = 1,
  });

  /// Calendar-month, monthly-on-the-1st cycle — the historical behaviour.
  static const PayCycleConfig defaults = PayCycleConfig();

  /// Sentinel for "the last day of the month".
  static const int endOfMonthPayDay = 31;

  final PayCycle cycle;

  /// 1 = Monday … 7 = Sunday (same numbering as [DateTime.weekday]).
  final int weeklyStartWeekday;

  /// Day of the month the salary arrives.
  ///
  /// [endOfMonthPayDay] means the last day of every month (28/29/30/31).
  final int monthlyPayDay;

  factory PayCycleConfig.fromJson(Map<String, Object?> json) {
    return PayCycleConfig(
      cycle: _parseCycle(json['cycle']),
      weeklyStartWeekday:
          ((json['weekly_start_weekday'] as num?)?.toInt() ?? 1).clamp(1, 7),
      monthlyPayDay: ((json['monthly_pay_day'] as num?)?.toInt() ?? 1)
          .clamp(1, endOfMonthPayDay),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'cycle': cycle.name,
        'weekly_start_weekday': weeklyStartWeekday,
        'monthly_pay_day': monthlyPayDay,
      };

  static PayCycle _parseCycle(Object? raw) {
    for (final cycle in PayCycle.values) {
      if (cycle.name == raw) return cycle;
    }
    return PayCycle.monthly;
  }

  PayCycleConfig copyWith({
    PayCycle? cycle,
    int? weeklyStartWeekday,
    int? monthlyPayDay,
  }) {
    return PayCycleConfig(
      cycle: cycle ?? this.cycle,
      weeklyStartWeekday: (weeklyStartWeekday ?? this.weeklyStartWeekday)
          .clamp(1, 7),
      monthlyPayDay: (monthlyPayDay ?? this.monthlyPayDay)
          .clamp(1, endOfMonthPayDay),
    );
  }

  bool get isMonthly => cycle == PayCycle.monthly;

  /// Human readable payday summary used in Settings.
  String get anchorLabel => switch (cycle) {
        PayCycle.daily => '毎日',
        PayCycle.weekly => '毎週',
        PayCycle.monthly =>
          monthlyPayDay >= endOfMonthPayDay ? '毎月末' : '毎月$monthlyPayDay日',
      };

  /// Number of pay periods in [month] (fractional for weekly pay).
  double periodsInMonth(DateTime month) => switch (cycle) {
        PayCycle.daily => daysInMonthOf(month).toDouble(),
        PayCycle.weekly => daysInMonthOf(month) / 7,
        PayCycle.monthly => 1,
      };

  /// Converts an amount received once per cycle into a monthly amount.
  int monthlyEquivalent(int perCycle, DateTime month) {
    if (perCycle == 0) return 0;
    return (perCycle * periodsInMonth(month)).round();
  }

  /// Converts a monthly amount into the amount received once per cycle.
  int perCycleEquivalent(int monthly, DateTime month) {
    if (monthly == 0) return 0;
    final periods = periodsInMonth(month);
    if (periods <= 0) return monthly;
    return (monthly / periods).round();
  }

  /// Payday for [month], clamped to the length of that month.
  DateTime paydayOf(DateTime month) {
    final first = DateTime(month.year, month.month);
    final length = daysInMonthOf(first);
    final day = monthlyPayDay >= endOfMonthPayDay
        ? length
        : monthlyPayDay.clamp(1, length);
    return DateTime(first.year, first.month, day);
  }

  /// The pay period that contains [date] (local midnight boundaries).
  PayPeriod periodFor(DateTime date) {
    final today = dateOnly(date);
    switch (cycle) {
      case PayCycle.daily:
        return PayPeriod(
          start: today,
          end: addDays(today, 1),
          cycle: cycle,
        );
      case PayCycle.weekly:
        final offset = (today.weekday - weeklyStartWeekday) % 7;
        final start = addDays(today, -offset);
        return PayPeriod(
          start: start,
          end: addDays(start, 7),
          cycle: cycle,
        );
      case PayCycle.monthly:
        final thisPayday = paydayOf(today);
        final start = today.isBefore(thisPayday)
            ? paydayOf(DateTime(today.year, today.month - 1))
            : thisPayday;
        final nextMonth = DateTime(start.year, start.month + 1);
        return PayPeriod(
          start: start,
          end: paydayOf(nextMonth),
          cycle: cycle,
        );
    }
  }
}

/// A single pay period: `[start, end)` in local time.
class PayPeriod {
  const PayPeriod({
    required this.start,
    required this.end,
    required this.cycle,
  });

  /// First day of the period (inclusive, local midnight).
  final DateTime start;

  /// First day *after* the period (exclusive, local midnight).
  final DateTime end;

  final PayCycle cycle;

  int get days => _daysBetween(start, end);

  DateTime get endInclusive => addDays(end, -1);

  bool contains(DateTime date) {
    final day = dateOnly(date);
    return !day.isBefore(start) && day.isBefore(end);
  }

  /// 1-based day index of [date] inside the period (clamped to `1..days`).
  int daysElapsedOn(DateTime date) {
    final day = dateOnly(date);
    if (day.isBefore(start)) return 0;
    final elapsed = _daysBetween(start, day) + 1;
    return elapsed.clamp(1, days);
  }

  /// Days left in the period including [date] (always at least 1).
  int daysRemainingOn(DateTime date) {
    final left = days - daysElapsedOn(date) + 1;
    return left < 1 ? 1 : left;
  }

  /// '今日' / '今週' / '今月' — translated by `AppText`.
  String get label => switch (cycle) {
        PayCycle.daily => '今日',
        PayCycle.weekly => '今週',
        PayCycle.monthly => '今月',
      };
}

/// First day of [month]'s calendar month.
DateTime firstDayOfMonth(DateTime month) => DateTime(month.year, month.month);

/// Number of days in the calendar month of [month].
int daysInMonthOf(DateTime month) => DateTime(month.year, month.month + 1, 0).day;

/// Local midnight of [date].
DateTime dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

/// [date] shifted by [days] calendar days (DST safe because it uses the
/// calendar, not a fixed 24-hour duration).
DateTime addDays(DateTime date, int days) =>
    DateTime(date.year, date.month, date.day + days);

int _daysBetween(DateTime a, DateTime b) {
  return DateTime.utc(b.year, b.month, b.day)
      .difference(DateTime.utc(a.year, a.month, a.day))
      .inDays;
}
