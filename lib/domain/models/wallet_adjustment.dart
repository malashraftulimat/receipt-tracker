/// Manual balance correction.
///
/// Corrections are recorded as transactions (never by editing a stored balance)
/// so the wallet keeps an audit trail. A positive [amount] increases the
/// wallet balance; a negative amount decreases it.
class WalletAdjustment {
  const WalletAdjustment({
    required this.id,
    required this.userId,
    required this.walletId,
    required this.amount,
    required this.occurredAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String walletId;
  final double amount;
  final DateTime occurredAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WalletAdjustment.fromJson(
    Map<String, dynamic> json, {
    String? id,
  }) {
    return WalletAdjustment(
      id: id ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      walletId: json['wallet_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      occurredAt: _parseDate(json['occurred_at']) ?? DateTime.now(),
      note: json['note'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'wallet_id': walletId,
        'amount': amount,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      };

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
