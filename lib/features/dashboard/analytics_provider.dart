import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  const MerchantTotal({required this.name, required this.amount, required this.count});

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
  });

  final List<MonthTotal> months;
  final List<CategorySlice> slices;
  final int monthTotal;
  final int monthCount;
  final int sixMonthTotal;
  final List<MerchantTotal> topMerchants;

  int get average => monthCount == 0 ? 0 : monthTotal ~/ monthCount;

  int get maxMonthTotal =>
      months.isEmpty ? 0 : months.map((m) => m.total).reduce((a, b) => a > b ? a : b);

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
        color: receipt.category?.colorValue ??
            const Color(0xFF9E9E9E),
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
      () => _CategoryBucket(label: key, color: const Color(0xFF9E9E9E)),
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

  return AnalyticsData(
    months: months,
    slices: slices,
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
