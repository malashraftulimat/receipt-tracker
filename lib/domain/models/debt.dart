import 'dart:math' as math;

import '../../core/localization/currencies.dart';

enum DebtDirection {
  iLent('i_lent'),
  iBorrowed('i_borrowed');

  const DebtDirection(this.wireName);

  final String wireName;

  bool get isLent => this == DebtDirection.iLent;

  static DebtDirection parse(Object? raw) =>
      raw == iLent.wireName ? iLent : iBorrowed;
}

enum DebtStatus {
  open('open'),
  partial('partial'),
  settled('settled');

  const DebtStatus(this.wireName);

  final String wireName;

  static DebtStatus parse(Object? raw) {
    for (final status in values) {
      if (status.wireName == raw) return status;
    }
    return open;
  }
}

/// One repayment against a debt. Stored embedded in the debt document.
class DebtRepayment {
  const DebtRepayment({
    required this.id,
    required this.amount,
    required this.date,
    this.walletId,
    this.note,
  });

  final String id;
  final double amount;
  final DateTime date;

  /// Optional wallet that received/paid the money.
  final String? walletId;
  final String? note;

  factory DebtRepayment.fromJson(Map<String, dynamic> json) {
    return DebtRepayment(
      id: json['id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      date: _parseDate(json['date']) ?? DateTime.now(),
      walletId: json['wallet_id'] as String?,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'id': id,
        'amount': amount,
        'date': date.toUtc().toIso8601String(),
        'wallet_id': walletId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      };

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// Money lent to, or borrowed from, a person.
class Debt {
  const Debt({
    required this.id,
    required this.userId,
    required this.direction,
    required this.counterparty,
    required this.amount,
    this.currency = kFallbackCurrencyCode,
    required this.date,
    this.dueDate,
    this.note,
    this.walletId,
    this.repayments = const <DebtRepayment>[],
    this.status = DebtStatus.open,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final DebtDirection direction;

  /// Free-text person / organisation name.
  final String counterparty;

  final double amount;
  final String currency;
  final DateTime date;
  final DateTime? dueDate;
  final String? note;

  /// Optional wallet used when the debt was created. Selecting it records the
  /// money movement in the wallet ledger.
  final String? walletId;

  final List<DebtRepayment> repayments;
  final DebtStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get repaidAmount =>
      repayments.fold<double>(0, (sum, item) => sum + item.amount);

  double get remaining => math.max(0, amount - repaidAmount);

  /// Settled debts contribute zero to totals.
  double get outstanding => status == DebtStatus.settled ? 0 : remaining;

  DebtStatus get derivedStatus {
    if (status == DebtStatus.settled) return DebtStatus.settled;
    if (remaining <= 0.011) return DebtStatus.settled;
    if (repaidAmount > 0) return DebtStatus.partial;
    return DebtStatus.open;
  }

  Debt copyWith({
    DebtDirection? direction,
    String? counterparty,
    double? amount,
    String? currency,
    DateTime? date,
    DateTime? dueDate,
    String? note,
    String? walletId,
    List<DebtRepayment>? repayments,
    DebtStatus? status,
    DateTime? updatedAt,
  }) {
    return Debt(
      id: id,
      userId: userId,
      direction: direction ?? this.direction,
      counterparty: counterparty ?? this.counterparty,
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      date: date ?? this.date,
      dueDate: dueDate ?? this.dueDate,
      note: note ?? this.note,
      walletId: walletId ?? this.walletId,
      repayments: repayments ?? this.repayments,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  /// Adds a repayment and recalculates open/partial/settled.
  Debt withRepayment(DebtRepayment repayment) {
    final next = <DebtRepayment>[...repayments, repayment];
    final repaid = next.fold<double>(0, (sum, item) => sum + item.amount);
    final nextStatus = repaid >= amount - 0.011
        ? DebtStatus.settled
        : repaid > 0
            ? DebtStatus.partial
            : DebtStatus.open;
    return copyWith(
      repayments: next,
      status: nextStatus,
      updatedAt: DateTime.now(),
    );
  }

  factory Debt.fromJson(Map<String, dynamic> json, {String? id}) {
    final rawRepayments = json['repayments'];
    final repayments = <DebtRepayment>[];
    if (rawRepayments is List) {
      for (final row in rawRepayments) {
        if (row is Map) {
          repayments.add(
            DebtRepayment.fromJson(Map<String, dynamic>.from(row)),
          );
        }
      }
    }
    repayments.sort((a, b) => a.date.compareTo(b.date));
    return Debt(
      id: id ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      direction: DebtDirection.parse(json['direction']),
      counterparty: (json['counterparty'] as String?)?.trim() ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : kFallbackCurrencyCode,
      date: _parseDate(json['date']) ?? DateTime.now(),
      dueDate: _parseDate(json['due_date']),
      note: json['note'] as String?,
      walletId: json['wallet_id'] as String?,
      repayments: repayments,
      status: DebtStatus.parse(json['status']),
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'direction': direction.wireName,
        'counterparty': counterparty.trim(),
        'amount': amount,
        'currency': currency.toUpperCase(),
        'date': date.toUtc().toIso8601String(),
        'due_date': dueDate?.toUtc().toIso8601String(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'wallet_id': walletId,
        'repayments': <Map<String, dynamic>>[
          for (final repayment in repayments) repayment.toRow(),
        ],
        'status': derivedStatus.wireName,
      };

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// Totals shown above the debt list (already converted to the display
/// currency when a rate is available).
class DebtTotals {
  const DebtTotals({
    this.owedToMe = 0,
    this.iOwe = 0,
    this.missingRateCount = 0,
  });

  final double owedToMe;
  final double iOwe;
  final int missingRateCount;
}
