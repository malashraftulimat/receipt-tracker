/// Money moved between two wallets.
///
/// For same-currency transfers [fromAmount] and [toAmount] are equal. For
/// different currencies the user enters both sides, so no exchange rate is
/// stored or guessed.
class WalletTransfer {
  const WalletTransfer({
    required this.id,
    required this.userId,
    required this.fromWalletId,
    required this.toWalletId,
    required this.fromAmount,
    required this.toAmount,
    required this.occurredAt,
    this.note,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final String fromWalletId;
  final String toWalletId;

  /// Amount leaving [fromWalletId], in that wallet's currency.
  final double fromAmount;

  /// Amount arriving in [toWalletId], in that wallet's currency.
  final double toAmount;

  final DateTime occurredAt;
  final String? note;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory WalletTransfer.fromJson(Map<String, dynamic> json, {String? id}) {
    return WalletTransfer(
      id: id ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      fromWalletId: json['from_wallet_id'] as String? ?? '',
      toWalletId: json['to_wallet_id'] as String? ?? '',
      fromAmount: (json['from_amount'] as num?)?.toDouble() ?? 0,
      toAmount: (json['to_amount'] as num?)?.toDouble() ?? 0,
      occurredAt: _parseDate(json['occurred_at']) ?? DateTime.now(),
      note: json['note'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'from_wallet_id': fromWalletId,
        'to_wallet_id': toWalletId,
        'from_amount': fromAmount,
        'to_amount': toAmount,
        'occurred_at': occurredAt.toUtc().toIso8601String(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
      };

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
