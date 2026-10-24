import '../../core/localization/currencies.dart';

/// A one-off income event typed by the user (sold an item, a single shift,
/// a gift, ...). Recurring income lives in `IncomeSource`.
class IncomeEntry {
  const IncomeEntry({
    required this.id,
    required this.userId,
    required this.amount,
    this.currency = kFallbackCurrencyCode,
    required this.receivedAt,
    required this.source,
    this.note,
    this.walletId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final double amount;

  /// ISO-4217 currency code. No conversion is stored.
  final String currency;

  /// Local date (and time when available) the money arrived.
  final DateTime receivedAt;

  /// Free-text source, e.g. "sold an item" or "Open Campus shift".
  final String source;

  final String? note;

  /// Destination wallet; `null` until wallets exist (Phase 2).
  final String? walletId;

  final DateTime createdAt;
  final DateTime updatedAt;

  factory IncomeEntry.fromJson(Map<String, dynamic> json, {String? id}) {
    return IncomeEntry(
      id: id ?? json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : kFallbackCurrencyCode,
      receivedAt: _parseDate(json['received_at']) ?? DateTime.now(),
      source: (json['source'] as String?)?.trim() ?? '',
      note: json['note'] as String?,
      walletId: json['wallet_id'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'amount': amount,
        'currency': currency.toUpperCase(),
        'received_at': receivedAt.toUtc().toIso8601String(),
        'source': source.trim(),
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'wallet_id': walletId,
      };

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// Distinct source texts typed before, newest first, for autocomplete.
List<String> previousIncomeSources(Iterable<IncomeEntry> entries) {
  final seen = <String>{};
  final sources = <String>[];
  for (final entry in entries) {
    final source = entry.source.trim();
    if (source.isEmpty) continue;
    if (seen.add(source.toLowerCase())) sources.add(source);
  }
  return sources;
}
