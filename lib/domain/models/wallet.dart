import '../../core/localization/currencies.dart';

/// Kind of money container. These are labels only; the user types every bank,
/// card or service name as free text.
enum WalletType {
  cash('cash', 'wallet.type_cash'),
  bank('bank', 'wallet.type_bank'),
  credit('credit', 'wallet.type_credit'),
  debit('debit', 'wallet.type_debit'),
  emoney('e_money', 'wallet.type_emoney'),
  transit('transit', 'wallet.type_transit'),
  savings('savings', 'wallet.type_savings'),
  points('points', 'wallet.type_points'),
  other('other', 'wallet.type_other');

  const WalletType(this.wireName, this.label);

  final String wireName;

  /// Localized label key (translations in ja/en/ar).
  final String label;

  bool get isCredit => this == WalletType.credit;

  /// Savings and points are excluded from "available money" by default.
  bool get defaultIncludeInTotal =>
      this != WalletType.savings && this != WalletType.points;

  static WalletType parse(Object? raw) {
    final value = raw?.toString().trim().toLowerCase().replaceAll('-', '_');
    for (final type in WalletType.values) {
      if (type.wireName == value || type.name.toLowerCase() == value) {
        return type;
      }
    }
    return WalletType.other;
  }
}

/// A cash / bank / card / e-money / savings wallet.
///
/// Balances are **never stored**. They are derived from the opening balance,
/// receipts, income entries, transfers and adjustment transactions. Money is
/// kept in [currency]; conversion happens only for display.
class Wallet {
  const Wallet({
    required this.id,
    required this.name,
    this.type = WalletType.cash,
    this.currency = kFallbackCurrencyCode,
    this.openingBalance = 0,
    this.colorValue = 0xFF10B981,
    this.archived = false,
    this.last4,
    this.includeInTotal,
    this.reserved = false,
    this.creditLimit,
    this.openingAvailable,
    this.closingDay,
    this.paymentDueDay,
    this.settlementWalletId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// Free text, e.g. "Wallet", "MUFG", "Suica", "Rakuten Card".
  final String name;

  final WalletType type;

  /// ISO-4217 code. Any currency in the catalog is allowed.
  final String currency;

  /// Balance before any tracked transaction (non-credit wallets).
  final double openingBalance;

  /// Material colour value (ARGB int).
  final int colorValue;

  final bool archived;

  /// Optional last four digits. Never a full card number, CVV or PIN.
  final String? last4;

  /// `null` means "use the type default": false for savings and points, true
  /// for everything else. Archived wallets are always excluded from totals.
  final bool? includeInTotal;

  /// Optional "do not spend this" marker (display only in Phase 2).
  final bool reserved;

  /// Credit cards only: the approved limit.
  final double? creditLimit;

  /// Credit cards only: available credit entered at setup.
  /// The amount owed at setup is `creditLimit - openingAvailable`.
  final double? openingAvailable;

  /// Credit cards only: statement closing day (1–28, or 31 = month end).
  final int? closingDay;

  /// Credit cards only: payment due day (1–28, or 31 = month end).
  final int? paymentDueDay;

  /// Credit cards only: optional default bank wallet for repayments.
  final String? settlementWalletId;

  final DateTime createdAt;
  final DateTime updatedAt;

  bool get isCredit => type.isCredit;

  bool get countsInTotal =>
      !archived && (includeInTotal ?? type.defaultIncludeInTotal);

  /// Owed at setup (credit cards).
  double get openingOwed {
    if (!isCredit) return 0;
    final limit = creditLimit ?? 0;
    final available = (openingAvailable ?? limit).clamp(0, limit);
    return (limit - available).clamp(0, limit).toDouble();
  }

  /// Only 4 digits are kept; anything longer is rejected to protect the user
  /// from accidentally storing a full card number.
  static String? sanitizeLast4(Object? value) {
    final digits = value?.toString().replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.length != 4) return null;
    return digits;
  }

  factory Wallet.fromJson(Map<String, dynamic> json, {String? id}) {
    final type = WalletType.parse(json['type']);
    return Wallet(
      id: id ?? json['id'] as String? ?? '',
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : 'Wallet',
      type: type,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : kFallbackCurrencyCode,
      openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
      colorValue: (json['color_value'] as num?)?.toInt() ??
          (type.isCredit ? 0xFF6366F1 : 0xFF10B981),
      archived: json['archived'] as bool? ?? false,
      last4: sanitizeLast4(json['last4']),
      includeInTotal: json['include_in_total'] as bool?,
      reserved: json['reserved'] as bool? ?? false,
      creditLimit: (json['credit_limit'] as num?)?.toDouble(),
      openingAvailable: (json['opening_available'] as num?)?.toDouble(),
      closingDay: (json['closing_day'] as num?)?.toInt(),
      paymentDueDay: (json['payment_due_day'] as num?)?.toInt(),
      settlementWalletId: json['settlement_wallet_id'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toRow() => <String, dynamic>{
        'name': name.trim(),
        'type': type.wireName,
        'currency': currency.toUpperCase(),
        'opening_balance': openingBalance,
        'color_value': colorValue,
        'archived': archived,
        'last4': sanitizeLast4(last4),
        'include_in_total': includeInTotal ?? type.defaultIncludeInTotal,
        'reserved': reserved,
        'credit_limit': isCredit ? creditLimit : null,
        'opening_available': isCredit ? openingAvailable : null,
        'closing_day': isCredit ? closingDay : null,
        'payment_due_day': isCredit ? paymentDueDay : null,
        'settlement_wallet_id': isCredit ? settlementWalletId : null,
      };

  Wallet copyWith({
    String? name,
    WalletType? type,
    String? currency,
    double? openingBalance,
    int? colorValue,
    bool? archived,
    bool? includeInTotal,
    bool? reserved,
    double? creditLimit,
    double? openingAvailable,
    int? closingDay,
    int? paymentDueDay,
    DateTime? updatedAt,
  }) {
    return Wallet(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      currency: currency ?? this.currency,
      openingBalance: openingBalance ?? this.openingBalance,
      colorValue: colorValue ?? this.colorValue,
      archived: archived ?? this.archived,
      last4: last4,
      includeInTotal: includeInTotal ?? this.includeInTotal,
      reserved: reserved ?? this.reserved,
      creditLimit: creditLimit ?? this.creditLimit,
      openingAvailable: openingAvailable ?? this.openingAvailable,
      closingDay: closingDay ?? this.closingDay,
      paymentDueDay: paymentDueDay ?? this.paymentDueDay,
      settlementWalletId: settlementWalletId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}

/// Day of [month] clamped to the month length, with 31 meaning month end.
int clampWalletDay(DateTime month, int day) {
  final length = DateTime(month.year, month.month + 1, 0).day;
  if (day >= 31) return length;
  return day.clamp(1, length);
}
