import 'dart:math' as math;

import 'income_entry.dart';
import 'pay_cycle.dart';
import 'receipt.dart';
import 'wallet.dart';
import 'wallet_adjustment.dart';
import 'wallet_transfer.dart';

enum WalletEntryKind { expense, income, transferIn, transferOut, adjustment }

/// One derived ledger line for a wallet. Nothing here is stored separately.
class WalletEntry {
  const WalletEntry({
    required this.kind,
    required this.date,
    required this.signedAmount,
    required this.title,
    this.subtitle,
    this.referenceId,
  });

  final WalletEntryKind kind;
  final DateTime date;

  /// Signed in the wallet's own currency. Expenses/outgoing transfers are
  /// negative, income/incoming transfers positive. For credit cards a negative
  /// amount increases the amount owed.
  final double signedAmount;

  /// Merchant, income source, counterparty wallet or adjustment note.
  final String title;

  final String? subtitle;
  final String? referenceId;

  bool get isIncoming => signedAmount >= 0;
}

/// A wallet plus its computed balance and ledger lines.
class WalletAccount {
  const WalletAccount({
    required this.wallet,
    required this.signedTotal,
    required this.entries,
  });

  final Wallet wallet;

  /// Sum of all signed ledger lines (credit charges are negative).
  final double signedTotal;

  /// Newest first.
  final List<WalletEntry> entries;

  /// Non-credit wallets only. Credit cards have no balance.
  double get balance => wallet.isCredit ? 0 : wallet.openingBalance + signedTotal;

  /// Credit cards only: positive amount owed.
  double get owed {
    if (!wallet.isCredit) return 0;
    return math.max(0, wallet.openingOwed - signedTotal);
  }

  double get availableCredit {
    if (!wallet.isCredit) return 0;
    return math.max(0, (wallet.creditLimit ?? 0) - owed);
  }

  /// Charges minus repayments since the most recent statement closing date.
  double owedThisCycle({DateTime? asOf}) {
    if (!wallet.isCredit) return 0;
    final closingDay = wallet.closingDay;
    if (closingDay == null) return owed;
    final start = walletClosingOnOrBefore(asOf ?? DateTime.now(), closingDay);
    final delta = entries
        .where((entry) => !entry.date.isBefore(start))
        .fold<double>(0, (sum, entry) => sum - entry.signedAmount);
    return math.max(0, delta);
  }

  /// Next payment due date for a credit card (local midnight).
  DateTime? nextDueDate({DateTime? asOf}) {
    if (!wallet.isCredit) return null;
    final closingDay = wallet.closingDay;
    final dueDay = wallet.paymentDueDay;
    if (closingDay == null || dueDay == null) return null;
    return walletNextDueDate(asOf ?? DateTime.now(), closingDay, dueDay);
  }

  List<WalletEntry> latest({int limit = 5}) =>
      entries.length <= limit ? entries : entries.sublist(0, limit);
}

/// All wallets with balances derived from transactions.
class WalletLedger {
  const WalletLedger({
    required this.accounts,
    this.mismatchedTransactionCount = 0,
  });

  final Map<String, WalletAccount> accounts;

  /// Receipts / income entries skipped because their currency differs from the
  /// selected wallet's currency. They are never silently converted.
  final int mismatchedTransactionCount;

  WalletAccount? accountFor(String walletId) => accounts[walletId];

  List<WalletAccount> get all => accounts.values.toList(growable: false);
}

WalletLedger buildWalletLedger({
  required Iterable<Wallet> wallets,
  required Iterable<Receipt> receipts,
  required Iterable<IncomeEntry> incomeEntries,
  required Iterable<WalletTransfer> transfers,
  required Iterable<WalletAdjustment> adjustments,
}) {
  final walletById = <String, Wallet>{
    for (final wallet in wallets) wallet.id: wallet,
  };
  final entries = <String, List<WalletEntry>>{
    for (final wallet in wallets) wallet.id: <WalletEntry>[],
  };
  var mismatched = 0;

  void add(Wallet wallet, WalletEntry entry) {
    entries[wallet.id]!.add(entry);
  }

  for (final receipt in receipts) {
    final walletId = receipt.walletId;
    if (walletId == null) continue;
    final wallet = walletById[walletId];
    if (wallet == null) continue;
    if (receipt.currency.toUpperCase() != wallet.currency.toUpperCase()) {
      mismatched += 1;
      continue;
    }
    final title = (receipt.merchant ?? '').trim().isNotEmpty
        ? receipt.merchant!.trim()
        : (receipt.note ?? '').trim();
    add(
      wallet,
      WalletEntry(
        kind: WalletEntryKind.expense,
        date: receipt.purchasedAt,
        signedAmount: -receipt.totalAmount,
        title: title,
        subtitle: receipt.note?.trim(),
        referenceId: receipt.id,
      ),
    );
  }

  for (final income in incomeEntries) {
    final walletId = income.walletId;
    if (walletId == null) continue;
    final wallet = walletById[walletId];
    if (wallet == null) continue;
    if (income.currency.toUpperCase() != wallet.currency.toUpperCase()) {
      mismatched += 1;
      continue;
    }
    add(
      wallet,
      WalletEntry(
        kind: WalletEntryKind.income,
        date: income.receivedAt,
        signedAmount: income.amount,
        title: income.source.trim(),
        subtitle: income.note?.trim(),
        referenceId: income.id,
      ),
    );
  }

  for (final transfer in transfers) {
    if (transfer.fromWalletId == transfer.toWalletId) continue;
    final fromWallet = walletById[transfer.fromWalletId];
    final toWallet = walletById[transfer.toWalletId];
    if (fromWallet == null || toWallet == null) continue;
    add(
      fromWallet,
      WalletEntry(
        kind: WalletEntryKind.transferOut,
        date: transfer.occurredAt,
        signedAmount: -transfer.fromAmount,
        title: toWallet.name,
        subtitle: transfer.note?.trim(),
        referenceId: transfer.id,
      ),
    );
    add(
      toWallet,
      WalletEntry(
        kind: WalletEntryKind.transferIn,
        date: transfer.occurredAt,
        signedAmount: transfer.toAmount,
        title: fromWallet.name,
        subtitle: transfer.note?.trim(),
        referenceId: transfer.id,
      ),
    );
  }

  for (final adjustment in adjustments) {
    final wallet = walletById[adjustment.walletId];
    if (wallet == null) continue;
    add(
      wallet,
      WalletEntry(
        kind: WalletEntryKind.adjustment,
        date: adjustment.occurredAt,
        signedAmount: adjustment.amount,
        title: adjustment.note?.trim() ?? '',
        referenceId: adjustment.id,
      ),
    );
  }

  final accounts = <String, WalletAccount>{};
  for (final wallet in wallets) {
    final rows = entries[wallet.id]!
      ..sort((a, b) => b.date.compareTo(a.date));
    final signedTotal =
        rows.fold<double>(0, (sum, entry) => sum + entry.signedAmount);
    accounts[wallet.id] = WalletAccount(
      wallet: wallet,
      signedTotal: signedTotal,
      entries: List<WalletEntry>.unmodifiable(rows),
    );
  }

  return WalletLedger(
    accounts: accounts,
    mismatchedTransactionCount: mismatched,
  );
}

/// Most recent statement closing date on or before [asOf].
DateTime walletClosingOnOrBefore(DateTime asOf, int closingDay) {
  final day = dateOnly(asOf);
  final thisMonth = DateTime(
    day.year,
    day.month,
    clampWalletDay(day, closingDay),
  );
  if (!thisMonth.isAfter(day)) return thisMonth;
  final previous = DateTime(day.year, day.month - 1);
  return DateTime(
    previous.year,
    previous.month,
    clampWalletDay(previous, closingDay),
  );
}

/// Next payment due date for a credit card.
///
/// A due day on or before the closing day belongs to the following month.
/// If this month's due date has already passed, the next cycle is returned.
DateTime walletNextDueDate(DateTime asOf, int closingDay, int dueDay) {
  final day = dateOnly(asOf);
  final lastClosing = walletClosingOnOrBefore(day, closingDay);
  var due = _dueAfter(lastClosing, dueDay);
  if (due.isBefore(day)) {
    final nextClosing = DateTime(
      lastClosing.year,
      lastClosing.month + 1,
      clampWalletDay(DateTime(lastClosing.year, lastClosing.month + 1),
          closingDay),
    );
    due = _dueAfter(nextClosing, dueDay);
  }
  return due;
}

DateTime _dueAfter(DateTime closing, int dueDay) {
  final due = DateTime(
    closing.year,
    closing.month,
    clampWalletDay(closing, dueDay),
  );
  if (due.isAfter(closing)) return due;
  final nextMonth = DateTime(closing.year, closing.month + 1);
  return DateTime(
    nextMonth.year,
    nextMonth.month,
    clampWalletDay(nextMonth, dueDay),
  );
}
