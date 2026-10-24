import 'receipt.dart';
import 'wallet.dart';

/// Spending in a calendar month grouped by wallet.
class WalletSpending {
  const WalletSpending({
    this.byWallet = const <String, double>{},
    this.currencyByWallet = const <String, String>{},
    this.unassigned = 0,
  });

  final Map<String, double> byWallet;
  final Map<String, String> currencyByWallet;

  /// Spending without a wallet link, in the receipt currency (usually the
  /// display currency). Shown separately so no money silently disappears.
  final double unassigned;
}

WalletSpending spendingByWallet({
  required Iterable<Receipt> receipts,
  required Iterable<Wallet> wallets,
  required DateTime monthStart,
  required DateTime monthEnd,
}) {
  final walletById = <String, Wallet>{
    for (final wallet in wallets) wallet.id: wallet,
  };
  final byWallet = <String, double>{};
  final currencyByWallet = <String, String>{
    for (final wallet in wallets) wallet.id: wallet.currency,
  };
  var unassigned = 0.0;

  for (final receipt in receipts) {
    final date = receipt.purchasedAt;
    if (date.isBefore(monthStart) || !date.isBefore(monthEnd)) continue;
    final walletId = receipt.walletId;
    final wallet = walletId == null ? null : walletById[walletId];
    if (wallet == null) {
      unassigned += receipt.totalAmount;
      continue;
    }
    if (receipt.currency.toUpperCase() != wallet.currency.toUpperCase()) {
      unassigned += receipt.totalAmount;
      continue;
    }
    byWallet[wallet.id] = (byWallet[wallet.id] ?? 0) + receipt.totalAmount;
  }

  return WalletSpending(
    byWallet: byWallet,
    currencyByWallet: currencyByWallet,
    unassigned: unassigned,
  );
}
