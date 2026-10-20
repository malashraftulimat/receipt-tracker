import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../data/providers.dart';
import '../../domain/models/receipt_filter.dart';

class MonthTotal {
  const MonthTotal({required this.month, required this.total});

  final DateTime month;
  final int total;

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
  final int amount;
  final int count;
  final Color color;

  double percentOf(int total) => total <= 0 ? 0 : amount / total * 100;
}

class MerchantTotal {
  const MerchantTotal(
      {required this.name, required this.amount, required this.count});

  final String name;
  final int amount;
  final int count;
}

class AnalyticsData {
  const AnalyticsData({
    required this.months,
    required this.slices,
    required this.monthTotal,
    required this.monthCount,
    required this.sixMonthTotal,
    required this.topMerchants,
    this.previousMonthTotal = 0,
    this.previousMonthCount = 0,
    this.currentDaily = const <int>[],
    this.previousDaily = const <int>[],
  });

  final List<MonthTotal> months;
  final List<CategorySlice> slices;
  final int monthTotal;
  final int monthCount;
  final int sixMonthTotal;
  final List<MerchantTotal> topMerchants;

  /// Month-over-month comparison (current vs previous month).
  final int previousMonthTotal;
  final int previousMonthCount;

  /// Cumulative spend per day of month (index 0 = day 1).
  final List<int> currentDaily;
  final List<int> previousDaily;

  int get momDelta => monthTotal - previousMonthTotal;

  double get momPercent {
    if (previousMonthTotal <= 0) return 0;
    return (monthTotal - previousMonthTotal) / previousMonthTotal * 100;
  }

  int get average => monthCount == 0 ? 0 : monthTotal ~/ monthCount;

  int get maxMonthTotal => months.isEmpty
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
    }).fold<int>(0, (sum, receipt) => sum + receipt.totalAmount);
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
      previousMonthReceipts.fold<int>(0, (sum, r) => sum + r.totalAmount);

  List<int> dailyCumulative(int year, int month) {
    final days = DateTime(year, month + 1, 0).day;
    final daily = List<int>.filled(days, 0);
    for (final receipt in receipts) {
      final date = receipt.purchasedAt;
      if (date.year != year || date.month != month) continue;
      final index = date.day - 1;
      if (index >= 0 && index < days) daily[index] += receipt.totalAmount;
    }
    var running = 0;
    return <int>[for (final value in daily) running += value];
  }

  return AnalyticsData(
    months: months,
    slices: slices,
    previousMonthTotal: previousMonthTotal,
    previousMonthCount: previousMonthReceipts.length,
    currentDaily: dailyCumulative(now.year, now.month),
    previousDaily: dailyCumulative(previousMonth.year, previousMonth.month),
    monthTotal: currentMonth.fold<int>(0, (sum, r) => sum + r.totalAmount),
    monthCount: currentMonth.length,
    sixMonthTotal: receipts.fold<int>(0, (sum, r) => sum + r.totalAmount),
    topMerchants: topMerchants.take(3).toList(growable: false),
  );
});

class _CategoryBucket {
  _CategoryBucket({required this.label, required this.color});

  final String label;
  final Color color;
  int amount = 0;
  int count = 0;
}
