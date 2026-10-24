import 'income_entry.dart';
import 'income_source.dart';
import 'pay_cycle.dart';

/// Income totals used by the budget page and dashboard.
///
/// Amounts are only summed when they share the display currency. Other
/// currencies are counted and excluded; conversion arrives in Phase 2.
class IncomeSummary {
  const IncomeSummary({
    this.monthlyEquivalent = 0,
    this.scheduledInPeriod = 0,
    this.oneOffInPeriod = 0,
    this.otherCurrencyCount = 0,
  });

  /// Monthly-equivalent total of all active recurring sources.
  final double monthlyEquivalent;

  /// Recurring income whose paydays fall inside the period.
  final double scheduledInPeriod;

  /// One-off income entries inside the period.
  final double oneOffInPeriod;

  /// Recurring sources / one-off entries in another currency that were
  /// excluded from the totals above.
  final int otherCurrencyCount;

  double get periodTotal => scheduledInPeriod + oneOffInPeriod;
}

/// Sums recurring and one-off income for [period].
///
/// [month] is the month used for the monthly-equivalent figure (daily/weekly
/// sources scale by the number of periods in that month).
IncomeSummary summarizeIncome({
  required Iterable<IncomeSource> sources,
  required Iterable<IncomeEntry> entries,
  required PayPeriod period,
  required DateTime month,
  required String currencyCode,
}) {
  final currency = currencyCode.trim().toUpperCase();
  var monthlyEquivalent = 0.0;
  var scheduledInPeriod = 0.0;
  var oneOffInPeriod = 0.0;
  var otherCurrencyCount = 0;

  for (final source in sources) {
    if (!source.active) continue;
    if (source.currency.trim().toUpperCase() != currency) {
      otherCurrencyCount += 1;
      continue;
    }
    monthlyEquivalent += source.monthlyEquivalent(month).toDouble();
    scheduledInPeriod +=
        source.paydaysIn(period).length * source.amountPerCycle;
  }

  for (final entry in entries) {
    if (!period.contains(entry.receivedAt)) continue;
    if (entry.currency.trim().toUpperCase() != currency) {
      otherCurrencyCount += 1;
      continue;
    }
    oneOffInPeriod += entry.amount;
  }

  return IncomeSummary(
    monthlyEquivalent: monthlyEquivalent,
    scheduledInPeriod: scheduledInPeriod,
    oneOffInPeriod: oneOffInPeriod,
    otherCurrencyCount: otherCurrencyCount,
  );
}
