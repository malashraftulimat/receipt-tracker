import '../../core/localization/currencies.dart';
import 'pay_cycle.dart';

enum RecurringDirection {
  expense('expense'),
  income('income');

  const RecurringDirection(this.wireName);

  final String wireName;

  bool get isExpense => this == RecurringDirection.expense;

  static RecurringDirection parse(Object? raw) =>
      raw == income.wireName ? income : expense;
}

/// Rent, subscriptions and fixed income posted automatically once per cycle.
class RecurringTransaction {
  const RecurringTransaction({
    required this.id,
    required this.userId,
    required this.name,
    required this.direction,
    required this.amount,
    this.currency = kFallbackCurrencyCode,
    this.categoryId,
    this.walletId,
    this.cycle = PayCycle.monthly,
    this.weeklyStartWeekday = DateTime.monday,
    this.monthlyPayDay = 1,
    required this.startDate,
    this.lastPostedAt,
    this.active = true,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String name;
  final RecurringDirection direction;
  final double amount;
  final String currency;
  final String? categoryId;
  final String? walletId;
  final PayCycle cycle;
  final int weeklyStartWeekday;
  final int monthlyPayDay;
  final DateTime startDate;
  final DateTime? lastPostedAt;
  final bool active;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  PayCycleConfig get config => PayCycleConfig(
        cycle: cycle,
        weeklyStartWeekday: weeklyStartWeekday,
        monthlyPayDay: monthlyPayDay,
      );

  /// Occurrences strictly after [afterExclusive] and on/before
  /// [throughInclusive], never before [startDate].
  List<DateTime> occurrencesBetween(
    DateTime afterExclusive,
    DateTime throughInclusive,
  ) {
    final after = dateOnly(afterExclusive);
    final through = dateOnly(throughInclusive);
    final start = dateOnly(startDate);
    final occurrences = <DateTime>[];
    if (through.isBefore(start)) return occurrences;

    switch (cycle) {
      case PayCycle.daily:
        var day = addDays(after, 1);
        if (day.isBefore(start)) day = start;
        while (!day.isAfter(through)) {
          occurrences.add(day);
          day = addDays(day, 1);
        }
        break;
      case PayCycle.weekly:
        var day = addDays(after, 1);
        if (day.isBefore(start)) day = start;
        while (!day.isAfter(through)) {
          if (day.weekday == weeklyStartWeekday) occurrences.add(day);
          day = addDays(day, 1);
        }
        break;
      case PayCycle.monthly:
        var month = DateTime(
          (after.isBefore(start) ? start : after).year,
          (after.isBefore(start) ? start : after).month,
        );
        while (!month.isAfter(through)) {
          final payday = config.paydayOf(month);
          if (payday.isAfter(after) &&
              !payday.isBefore(start) &&
              !payday.isAfter(through)) {
            occurrences.add(payday);
          }
          month = DateTime(month.year, month.month + 1);
        }
        break;
    }
    return occurrences;
  }

  /// Next occurrence after [after] (defaults to [lastPostedAt] or today).
  DateTime? nextOccurrence({DateTime? after}) {
    final from = after ?? lastPostedAt ?? dateOnly(DateTime.now());
    final horizon = addDays(from, 400);
    final occurrences = occurrencesBetween(from, horizon);
    return occurrences.isEmpty ? null : occurrences.first;
  }

  factory RecurringTransaction.fromJson(Map<String, dynamic> json, {String? id}) {
    return RecurringTransaction(
      id: id ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Recurring',
      direction: RecurringDirection.parse(json['direction']),
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : kFallbackCurrencyCode,
      categoryId: json['category_id'] as String?,
      walletId: json['wallet_id'] as String?,
      cycle: _parseCycle(json['cycle']),
      weeklyStartWeekday:
          ((json['weekly_start_weekday'] as num?)?.toInt() ?? 1).clamp(1, 7),
      monthlyPayDay: ((json['monthly_pay_day'] as num?)?.toInt() ?? 1)
          .clamp(1, PayCycleConfig.endOfMonthPayDay),
      startDate: _parseDate(json['start_date']) ?? DateTime.now(),
      lastPostedAt: _parseDate(json['last_posted_at']),
      active: json['active'] as bool? ?? true,
      note: json['note'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name.trim(),
        'direction': direction.wireName,
        'amount': amount,
        'currency': currency.toUpperCase(),
        'category_id': categoryId,
        'wallet_id': walletId,
        'cycle': cycle.name,
        'weekly_start_weekday': weeklyStartWeekday,
        'monthly_pay_day': monthlyPayDay,
        'start_date': dateOnly(startDate).toUtc().toIso8601String(),
        'last_posted_at':
            lastPostedAt == null ? null : dateOnly(lastPostedAt!).toUtc().toIso8601String(),
        'active': active,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      };

  RecurringTransaction copyWith({
    String? name,
    RecurringDirection? direction,
    double? amount,
    String? currency,
    String? categoryId,
    String? walletId,
    PayCycle? cycle,
    int? weeklyStartWeekday,
    int? monthlyPayDay,
    DateTime? startDate,
    DateTime? lastPostedAt,
    bool? active,
    String? note,
    DateTime? updatedAt,
  }) {
    return RecurringTransaction(
      id: id,
      userId: userId,
      name: name ?? this.name,
      direction: direction ?? this.direction,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      categoryId: categoryId ?? this.categoryId,
      walletId: walletId ?? this.walletId,
      cycle: cycle ?? this.cycle,
      weeklyStartWeekday:
          (weeklyStartWeekday ?? this.weeklyStartWeekday).clamp(1, 7),
      monthlyPayDay: (monthlyPayDay ?? this.monthlyPayDay)
          .clamp(1, PayCycleConfig.endOfMonthPayDay),
      startDate: startDate ?? this.startDate,
      lastPostedAt: lastPostedAt ?? this.lastPostedAt,
      active: active ?? this.active,
      note: note ?? this.note,
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
    if (value is DateTime) return dateOnly(value.toLocal());
    final parsed = DateTime.tryParse(value.toString());
    return parsed == null ? null : dateOnly(parsed.toLocal());
  }
}
