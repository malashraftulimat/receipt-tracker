import 'dart:math' as math;

import 'exchange_rates.dart';
import 'pay_cycle.dart';
import 'wallet_ledger.dart';

/// The three dashboard headline numbers.
class MoneyTotals {
  const MoneyTotals({
    required this.availableMoney,
    required this.afterObligations,
    required this.netWorth,
    this.cardOwed = 0,
    this.nextCardDueDate,
    this.nextCardAmount = 0,
    this.cardWarning = false,
    this.missingRateCount = 0,
    this.recurringDue = 0,
    this.debtsOwedToMe = 0,
    this.debtsIOwe = 0,
  });

  /// Sum of wallets with `includeInTotal` (archived and credit cards excluded).
  final double availableMoney;

  /// Available money minus card dues and recurring bills before the next payday.
  final double afterObligations;

  /// All non-archived wallets (including savings/points) minus card dues and
  /// debts I owe, plus debts owed to me.
  final double netWorth;

  final double cardOwed;
  final DateTime? nextCardDueDate;
  final double nextCardAmount;

  /// True when card dues are large relative to available money and due soon.
  final bool cardWarning;

  /// Wallets whose currency had no rate; they are excluded (not guessed).
  final int missingRateCount;

  final double recurringDue;
  final double debtsOwedToMe;
  final double debtsIOwe;
}

/// Computes all three totals in [fx.base] using fetched/cached/manual rates.
///
/// [recurringDue], [debtsOwedToMe] and [debtsIOwe] are zero in Phase 2 and are
/// filled by Phase 3/4 without changing the callers.
MoneyTotals computeMoneyTotals({
  required WalletLedger ledger,
  required FxSnapshot fx,
  required DateTime asOf,
  double recurringDue = 0,
  double debtsOwedToMe = 0,
  double debtsIOwe = 0,
  int extraMissingRateCount = 0,
}) {
  var available = 0.0;
  var cardOwed = 0.0;
  var netWorth = 0.0;
  var missingRates = extraMissingRateCount;
  DateTime? nextCardDue;
  var nextCardAmount = 0.0;

  for (final account in ledger.all) {
    final wallet = account.wallet;
    if (wallet.archived) continue;

    if (wallet.isCredit) {
      final converted = fx.convert(account.owed, wallet.currency, fx.base);
      if (converted == null) {
        missingRates += 1;
        continue;
      }
      cardOwed += converted;
      if (account.owed > 0) {
        final due = account.nextDueDate(asOf: asOf);
        if (due != null && (nextCardDue == null || due.isBefore(nextCardDue))) {
          nextCardDue = due;
          nextCardAmount = converted;
        }
      }
      continue;
    }

    final converted = fx.convert(account.balance, wallet.currency, fx.base);
    if (converted == null) {
      missingRates += 1;
      continue;
    }
    if (wallet.countsInTotal) available += converted;
    netWorth += converted;
  }

  netWorth += debtsOwedToMe - debtsIOwe - cardOwed;
  final afterObligations = available - cardOwed - recurringDue;
  final warning = cardWarning(
    available: available,
    cardOwed: cardOwed,
    nextDueDate: nextCardDue,
    asOf: asOf,
  );

  return MoneyTotals(
    availableMoney: available,
    afterObligations: afterObligations,
    netWorth: netWorth,
    cardOwed: cardOwed,
    nextCardDueDate: nextCardDue,
    nextCardAmount: nextCardAmount,
    cardWarning: warning,
    missingRateCount: missingRates,
    recurringDue: recurringDue,
    debtsOwedToMe: debtsOwedToMe,
    debtsIOwe: debtsIOwe,
  );
}

/// Warning rule: card dues must be large relative to available money **and**
/// due within the next seven days.
bool cardWarning({
  required double available,
  required double cardOwed,
  required DateTime? nextDueDate,
  required DateTime asOf,
  int daysBefore = 7,
  double ratio = 0.30,
}) {
  if (cardOwed <= 0 || nextDueDate == null) return false;
  final days = dateOnly(nextDueDate).difference(dateOnly(asOf)).inDays;
  if (days < 0 || days > daysBefore) return false;
  if (available <= 0) return true;
  return cardOwed >= math.max(0, available * ratio);
}
