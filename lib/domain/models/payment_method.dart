import 'package:flutter/material.dart';

/// How a payment was made (cash, card, bank transfer, e-money, ...).
///
/// Stored in Firestore by [wireName] (snake_case) so renaming the Dart enum
/// never corrupts existing documents. [label] is the Japanese source string
/// that `AppText` translates into English / Arabic.
enum PaymentMethod {
  cash('cash', 'cash', Icons.payments_outlined),
  creditCard('credit_card', 'credit_card', Icons.credit_card),
  debitCard('debit_card', 'debit_card', Icons.credit_score_outlined),
  bankTransfer('bank_transfer', 'bank_transfer', Icons.account_balance_outlined),
  directDebit(
    'direct_debit',
    'direct_debit_utility_bills',
    Icons.receipt_long_outlined,
  ),
  qrEmoney('qr_emoney', 'qr_e_money', Icons.qr_code_2),
  icCard('ic_card', 'ic_card_suica_pasmo', Icons.contactless_outlined),
  convenienceStore(
    'convenience_store',
    'convenience_store_payment',
    Icons.storefront_outlined,
  ),
  other('other', 'other', Icons.more_horiz);

  const PaymentMethod(this.wireName, this.label, this.icon);

  /// Value written to the `payment_method` document field.
  final String wireName;

  /// Japanese source string, translated by `AppText` at render time.
  final String label;

  final IconData icon;

  /// Label for a possibly unset method ('未設定' / 'Not set').
  static String labelOf(PaymentMethod? method) => method?.label ?? 'not_set';

  /// Parses a stored / legacy value ('credit_card', 'creditCard', ...).
  static PaymentMethod? tryParse(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_');
    for (final method in PaymentMethod.values) {
      if (method.wireName == normalized ||
          method.name.toLowerCase() == normalized) {
        return method;
      }
    }
    return null;
  }
}
