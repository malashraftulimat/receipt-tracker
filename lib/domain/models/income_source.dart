import '../../core/localization/currencies.dart';
import 'monthly_budget.dart';
import 'pay_cycle.dart';

/// One recurring way the user receives money (salary, part-time job, daily
/// pay, allowance, ...).
///
/// The pay cycle and payday anchors live here. Exactly one source is flagged
/// [definesBudgetPeriod]; its [config] decides where the budget period starts
/// and ends. Amounts are kept **per cycle** and converted to a monthly
/// equivalent only for display/planning.
class IncomeSource {
  const IncomeSource({
    required this.id,
    required this.name,
    this.cycle = PayCycle.monthly,
    this.weeklyStartWeekday = DateTime.monday,
    this.monthlyPayDay = 1,
    this.amountPerCycle = 0,
    this.currency = kFallbackCurrencyCode,
    this.walletId,
    this.active = true,
    this.definesBudgetPeriod = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final PayCycle cycle;

  /// 1 = Monday … 7 = Sunday (same numbering as [DateTime.weekday]).
  final int weeklyStartWeekday;

  /// Day of the month the income arrives; [PayCycleConfig.endOfMonthPayDay]
  /// means the last day of the month.
  final int monthlyPayDay;

  /// Amount received once per [cycle], in [currency].
  final double amountPerCycle;

  /// ISO-4217 currency code. No conversion is stored.
  final String currency;

  /// Destination wallet; `null` until wallets exist (Phase 2).
  final String? walletId;

  final bool active;

  /// True for the single source whose payday drives the budget period.
  final bool definesBudgetPeriod;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// The pay-cycle view of this source, reused by the existing pacing code.
  PayCycleConfig get config => PayCycleConfig(
        cycle: cycle,
        weeklyStartWeekday: weeklyStartWeekday,
        monthlyPayDay: monthlyPayDay,
      );

  /// Monthly equivalent for [month] (fractional for daily/weekly pay).
  num monthlyEquivalent(DateTime month) =>
      config.monthlyEquivalent(amountPerCycle, month);

  /// Every payday of this source inside [period] (`[start, end)`).
  ///
  /// * daily  → every day
  /// * weekly → the configured weekday
  /// * monthly → the configured day (clamped per month, or month end)
  List<DateTime> paydaysIn(PayPeriod period) {
    final paydays = <DateTime>[];
    switch (cycle) {
      case PayCycle.daily:
        for (var day = period.start;
            day.isBefore(period.end);
            day = addDays(day, 1)) {
          paydays.add(day);
        }
        break;
      case PayCycle.weekly:
        var day = period.start;
        while (day.weekday != weeklyStartWeekday &&
            day.isBefore(period.end)) {
          day = addDays(day, 1);
        }
        while (day.isBefore(period.end)) {
          paydays.add(day);
          day = addDays(day, 7);
        }
        break;
      case PayCycle.monthly:
        var month = DateTime(period.start.year, period.start.month);
        while (month.isBefore(period.end)) {
          final payday = config.paydayOf(month);
          if (period.contains(payday)) paydays.add(payday);
          month = DateTime(month.year, month.month + 1);
        }
        break;
    }
    return paydays;
  }

  factory IncomeSource.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    return IncomeSource(
      id: id ?? json['id'] as String? ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Main',
      cycle: _parseCycle(json['cycle']),
      weeklyStartWeekday:
          ((json['weekly_start_weekday'] as num?)?.toInt() ?? 1).clamp(1, 7),
      monthlyPayDay: ((json['monthly_pay_day'] as num?)?.toInt() ?? 1)
          .clamp(1, PayCycleConfig.endOfMonthPayDay),
      amountPerCycle: (json['amount_per_cycle'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : kFallbackCurrencyCode,
      walletId: json['wallet_id'] as String?,
      active: json['active'] as bool? ?? true,
      definesBudgetPeriod: json['defines_budget_period'] as bool? ?? false,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name.trim(),
        'cycle': cycle.name,
        'weekly_start_weekday': weeklyStartWeekday,
        'monthly_pay_day': monthlyPayDay,
        'amount_per_cycle': amountPerCycle,
        'currency': currency.toUpperCase(),
        'wallet_id': walletId,
        'active': active,
        'defines_budget_period': definesBudgetPeriod,
      };

  IncomeSource copyWith({
    String? name,
    PayCycle? cycle,
    int? weeklyStartWeekday,
    int? monthlyPayDay,
    double? amountPerCycle,
    String? currency,
    String? walletId,
    bool? active,
    bool? definesBudgetPeriod,
    DateTime? updatedAt,
  }) {
    return IncomeSource(
      id: id,
      name: name ?? this.name,
      cycle: cycle ?? this.cycle,
      weeklyStartWeekday:
          (weeklyStartWeekday ?? this.weeklyStartWeekday).clamp(1, 7),
      monthlyPayDay: (monthlyPayDay ?? this.monthlyPayDay)
          .clamp(1, PayCycleConfig.endOfMonthPayDay),
      amountPerCycle: amountPerCycle ?? this.amountPerCycle,
      currency: currency ?? this.currency,
      walletId: walletId ?? this.walletId,
      active: active ?? this.active,
      definesBudgetPeriod:
          definesBudgetPeriod ?? this.definesBudgetPeriod,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  static PayCycle _parseCycle(Object? raw) {
    for (final cycle in PayCycle.values) {
      if (cycle.name == raw) return cycle;
    }
    return PayCycle.monthly;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// Builds the first income source from the pre-Phase-1 single pay cycle and
/// the latest stored monthly plan.
///
/// The legacy local preference supplies the weekday/monthly payday anchors;
/// the plan supplies the per-cycle amount when it was saved with the same
/// cycle, otherwise its monthly salary is converted back.
IncomeSource legacyIncomeSource({
  required PayCycleConfig legacyConfig,
  required MonthlyBudget? latestBudget,
  required String currency,
  DateTime? createdAt,
}) {
  final now = createdAt ?? DateTime.now();
  final cycle = latestBudget?.payCycle ?? legacyConfig.cycle;
  final config = legacyConfig.copyWith(cycle: cycle);
  final storedPerCycle = latestBudget?.incomePerCycle;
  final perCycle = storedPerCycle != null && latestBudget?.payCycle == cycle
      ? storedPerCycle.toDouble()
      : config.perCycleEquivalent(latestBudget?.salary ?? 0, now).toDouble();

  return IncomeSource(
    id: 'main',
    name: 'Main',
    cycle: cycle,
    weeklyStartWeekday: config.weeklyStartWeekday,
    monthlyPayDay: config.monthlyPayDay,
    amountPerCycle: perCycle,
    currency: currency,
    active: true,
    definesBudgetPeriod: true,
    createdAt: now,
    updatedAt: now,
  );
}

/// The source whose payday anchors the budget period.
///
/// The flagged source wins even when it is inactive; without a flag the first
/// active source is used, then the first source.
IncomeSource? budgetDefiningSource(Iterable<IncomeSource> sources) {
  final list = sources.toList(growable: false);
  for (final source in list) {
    if (source.definesBudgetPeriod) return source;
  }
  for (final source in list) {
    if (source.active) return source;
  }
  return list.isEmpty ? null : list.first;
}

/// Ensures exactly one source is flagged as defining the budget period.
///
/// The first already-flagged source is kept; otherwise the first source is
/// promoted. An empty list stays empty.
List<IncomeSource> normalizeBudgetPeriodFlag(List<IncomeSource> sources) {
  if (sources.isEmpty) return sources;
  final flagged = sources.where((source) => source.definesBudgetPeriod);
  final keepId = (flagged.isNotEmpty ? flagged.first : sources.first).id;
  return <IncomeSource>[
    for (final source in sources)
      source.definesBudgetPeriod == (source.id == keepId)
          ? source
          : source.copyWith(definesBudgetPeriod: source.id == keepId),
  ];
}
