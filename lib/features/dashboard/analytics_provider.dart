import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/providers.dart';
import '../../domain/models/payment_method.dart';
import '../../domain/models/receipt_filter.dart';

class MonthTotal {
  const MonthTotal({required this.month, required this.total});

  final DateTime month;
  final double total;

  String get label => '${month.month}月';
}

class CategorySlice {
  const CategorySlice({
    required this.label,
    required this.amount,
    required this.count,
    required this.color,
  });

  final String label;
  final double amount;
  final int count;
  final Color color;

  double percentOf(double total) => total <= 0 ? 0 : amount / total * 100;
}

class MerchantTotal {
  const MerchantTotal(
      {required this.name, required this.amount, required this.count});

  final String name;
  final double amount;
  final int count;
}

/// Current-month spending grouped by payment method.
class PaymentMethodTotal {
  const PaymentMethodTotal({
    required this.method,
    required this.amount,
    required this.count,
  });

  /// Null = unset (receipts saved before the field existed).
  final PaymentMethod? method;
  final double amount;
  final int count;

  String get label => PaymentMethod.labelOf(method);

  double percentOf(double total) => total <= 0 ? 0 : amount / total * 100;
}

class AnalyticsData {
  const AnalyticsData({
    required this.months,
    required this.slices,
    required this.monthTotal,
    required this.monthCount,
    required this.sixMonthTotal,
    required this.topMerchants,
    this.paymentMethods = const <PaymentMethodTotal>[],
    this.previousMonthTotal = 0,
    this.previousMonthCount = 0,
    this.currentDaily = const <double>[],
    this.previousDaily = const <double>[],
  });

  final List<MonthTotal> months;
  final List<CategorySlice> slices;
  final double monthTotal;
  final int monthCount;
  final double sixMonthTotal;
  final List<MerchantTotal> topMerchants;

  /// Current-month spend per payment method (cash, cards, e-money, ...).
  final List<PaymentMethodTotal> paymentMethods;

  /// Month-over-month comparison (current vs previous month).
  final double previousMonthTotal;
  final int previousMonthCount;

  /// Cumulative spend per day of month (index 0 = day 1).
  final List<double> currentDaily;
  final List<double> previousDaily;

  double get momDelta => monthTotal - previousMonthTotal;

  double get momPercent {
    if (previousMonthTotal <= 0) return 0;
    return (monthTotal - previousMonthTotal) / previousMonthTotal * 100;
  }

  double get average => monthCount == 0 ? 0 : monthTotal / monthCount;

  double get maxMonthTotal => months.isEmpty
      ? 0
      : months.map((m) => m.total).reduce((a, b) => a > b ? a : b);

  bool get isEmpty => sixMonthTotal == 0;

  static const AnalyticsData empty = AnalyticsData(
    months: <MonthTotal>[],
    slices: <CategorySlice>[],
    monthTotal: 0,
    monthCount: 0,
    sixMonthTotal: 0,
    topMerchants: <MerchantTotal>[],
    paymentMethods: <PaymentMethodTotal>[],
  );
}

/// Last 6 months trend + current month breakdown.
final analyticsProvider = FutureProvider<AnalyticsData>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return AnalyticsData.empty;

  final now = DateTime.now();
  final start = DateTime(now.year, now.month - 5, 1);
  final end = DateTime(now.year, now.month + 1, 1);

  final receipts = await ref.watch(receiptRepositoryProvider).fetch(
        ReceiptFilter(from: start, to: end),
      );

  // --- monthly trend ------------------------------------------------------
  final months = <MonthTotal>[];
  for (var i = 0; i < 6; i++) {
    final monthStart = DateTime(now.year, now.month - 5 + i, 1);
    final monthEnd = DateTime(monthStart.year, monthStart.month + 1, 1);
    final total = receipts.where((receipt) {
      final date = receipt.purchasedAt;
      return !date.isBefore(monthStart) && date.isBefore(monthEnd);
    }).fold<double>(0, (sum, receipt) => sum + receipt.totalAmount);
    months.add(MonthTotal(month: monthStart, total: total));
  }

  // --- current month breakdown -------------------------------------------
  final currentMonth = receipts.where((receipt) {
    final date = receipt.purchasedAt;
    return date.year == now.year && date.month == now.month;
  }).toList(growable: false);

  final buckets = <String, _CategoryBucket>{};
  for (final receipt in currentMonth) {
    final key = receipt.category?.id ?? '__uncategorized__';
    final bucket = buckets.putIfAbsent(
      key,
      () => _CategoryBucket(
        label: receipt.displayCategory,
        color: AppPalette.categoryAccent(
          receipt.category?.name,
          fallback: receipt.category?.colorValue ?? AppPalette.textFaint,
        ),
      ),
    );
    bucket.amount += receipt.totalAmount;
    bucket.count += 1;
  }

  final slices = buckets.values
      .map(
        (bucket) => CategorySlice(
          label: bucket.label,
          amount: bucket.amount,
          count: bucket.count,
          color: bucket.color,
        ),
      )
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  // --- current month by payment method ------------------------------------
  final paymentBuckets = <PaymentMethod?, _TotalBucket>{};
  for (final receipt in currentMonth) {
    final bucket = paymentBuckets.putIfAbsent(
      receipt.paymentMethod,
      _TotalBucket.new,
    );
    bucket.amount += receipt.totalAmount;
    bucket.count += 1;
  }
  final paymentMethods = paymentBuckets.entries
      .map(
        (entry) => PaymentMethodTotal(
          method: entry.key,
          amount: entry.value.amount,
          count: entry.value.count,
        ),
      )
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  // --- top merchants ------------------------------------------------------
  final merchantBuckets = <String, _CategoryBucket>{};
  for (final receipt in receipts) {
    final key = receipt.displayMerchant;
    final bucket = merchantBuckets.putIfAbsent(
      key,
      () => _CategoryBucket(label: key, color: AppPalette.textFaint),
    );
    bucket.amount += receipt.totalAmount;
    bucket.count += 1;
  }
  final topMerchants = merchantBuckets.values
      .map(
        (bucket) => MerchantTotal(
          name: bucket.label,
          amount: bucket.amount,
          count: bucket.count,
        ),
      )
      .toList()
    ..sort((a, b) => b.amount.compareTo(a.amount));

  // --- month-over-month ---------------------------------------------------
  final previousMonth = DateTime(now.year, now.month - 1);
  final previousMonthReceipts = receipts.where((receipt) {
    final date = receipt.purchasedAt;
    return date.year == previousMonth.year && date.month == previousMonth.month;
  }).toList(growable: false);

  final previousMonthTotal =
      previousMonthReceipts.fold<double>(0, (sum, r) => sum + r.totalAmount);

  List<double> dailyCumulative(int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    final daily = List<double>.filled(days, 0);
    for (final receipt in receipts) {
      final date = receipt.purchasedAt;
      if (date.year != year || date.month != month) continue;
      final index = date.day - 1;
      if (index >= 0 && index < days) daily[index] += receipt.totalAmount;
    }
    var running = 0.0;
    return <double>[for (final value in daily) running += value];
  }

  return AnalyticsData(
    months: months,
    slices: slices,
    previousMonthTotal: previousMonthTotal,
    previousMonthCount: previousMonthReceipts.length,
    currentDaily: dailyCumulative(now.year, now.month),
    previousDaily: dailyCumulative(previousMonth.year, previousMonth.month),
    monthTotal: currentMonth.fold<double>(0, (sum, r) => sum + r.totalAmount),
    monthCount: currentMonth.length,
    sixMonthTotal: receipts.fold<double>(0, (sum, r) => sum + r.totalAmount),
    topMerchants: topMerchants.take(3).toList(growable: false),
    paymentMethods: paymentMethods,
  );
});

class _TotalBucket {
  double amount = 0;
  int count = 0;
}

class _CategoryBucket {
  _CategoryBucket({required this.label, required this.color});

  final String label;
  final Color color;
  double amount = 0;
  int count = 0;
}
