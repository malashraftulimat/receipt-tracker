import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings/currency_provider.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../analytics_provider.dart';
import '../../../core/localization/localization.dart';

/// Monthly trend + category breakdown + top merchants.
class AnalyticsPanel extends ConsumerWidget {
  const AnalyticsPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analyticsProvider);
    final theme = Theme.of(context);
    final currencyCode = ref.watch(defaultCurrencyProvider).code;

    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => _ChartCard(
        title: 'analytics',
        child: AppText(
          '集計を読み込めませんでした\n$error',
          style: theme.textTheme.bodySmall,
        ),
      ),
      data: (data) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            AppText(
              'spending_analytics',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                _Metric(
                  label: 'this_month_s_spending',
                  value: formatMoney(data.monthTotal, currency: currencyCode),
                  emphasized: true,
                ),
                _Metric(label: 'count', value: '${data.monthCount}件'),
                _Metric(label: 'average', value: formatMoney(data.average, currency: currencyCode)),
                _Metric(
                    label: '6_month_total',
                    value: formatCompactMoney(data.sixMonthTotal, currency: currencyCode)),
              ],
            ),
            if (data.otherCurrencyCount > 0) ...<Widget>[
              const SizedBox(height: 8),
              AppText(
                'currency.other_note',
                count: data.otherCurrencyCount,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 14),
            _ChartCard(
              title: 'last_6_months',
              child: SizedBox(
                height: 168,
                child: _MonthlyBarChart(data: data, currencyCode: currencyCode),
              ),
            ),
            const SizedBox(height: 14),
            _ChartCard(
              title: 'by_category_this_month',
              child: data.slices.isEmpty
                  ? const _EmptyChart(message: 'no_data_for_this_month')
                  : _CategoryBreakdown(data: data, currencyCode: currencyCode),
            ),
            const SizedBox(height: 14),
            _ChartCard(
              title: 'by_payment_method_this_month',
              child: data.paymentMethods.isEmpty
                  ? const _EmptyChart(message: 'no_data_for_this_month')
                  : _PaymentMethodBreakdown(
                      data: data,
                      currencyCode: currencyCode,
                    ),
            ),
            const SizedBox(height: 14),
            _ChartCard(
              title: 'vs_last_month_cumulative',
              child: _MonthComparison(data: data, currencyCode: currencyCode),
            ),
            const SizedBox(height: 14),
            _ChartCard(
              title: 'frequent_stores',
              child: data.topMerchants.isEmpty
                  ? const _EmptyChart(message: 'no_data')
                  : Column(
                      children: <Widget>[
                        for (final merchant in data.topMerchants)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: AppText(
                                    merchant.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppText(
                                  '${merchant.count}件',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                AppText(
                                  formatMoney(merchant.amount, currency: currencyCode),
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppPalette.card(
        context,
        accent: emphasized ? AppPalette.violet : null,
        radius: 14,
        glow: emphasized,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          AppText(
            label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 2),
          AppText(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: emphasized ? AppPalette.violet : AppPalette.text,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: AppPalette.card(
        context,
        accent: AppPalette.violet,
        radius: 16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppText(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  const _EmptyChart({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: 80,
      child: Center(
        child: AppText(
          message,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.data, required this.currencyCode});

  final AnalyticsData data;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxY = math.max(1000.0, data.maxMonthTotal * 1.25);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY,
        alignment: BarChartAlignment.spaceAround,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              return BarTooltipItem(
                formatMoney(rod.toY, currency: currencyCode),
                TextStyle(
                  color: theme.colorScheme.onInverseSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          leftTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= data.months.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: AppText(
                    data.months[index].label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: <BarChartGroupData>[
          for (var i = 0; i < data.months.length; i++)
            BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: data.months[i].total.toDouble(),
                  width: 18,
                  gradient: LinearGradient(
                    colors: i == data.months.length - 1
                        ? <Color>[AppPalette.cyan, AppPalette.violet]
                        : <Color>[
                            AppPalette.violet.withValues(alpha: 0.65),
                            AppPalette.sky.withValues(alpha: 0.35),
                          ],
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                  ),
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CategoryBreakdown extends StatelessWidget {
  const _CategoryBreakdown({required this.data, required this.currencyCode});

  final AnalyticsData data;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = data.monthTotal;

    return Column(
      children: <Widget>[
        SizedBox(
          height: 148,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 40,
              sections: <PieChartSectionData>[
                for (final slice in data.slices)
                  PieChartSectionData(
                    value: slice.amount.toDouble(),
                    color: slice.color,
                    radius: 28,
                    borderSide: BorderSide(
                      color: AppPalette.background.withValues(alpha: 0.55),
                      width: 1.5,
                    ),
                    showTitle: slice.percentOf(total) >= 8,
                    title: '${slice.percentOf(total).round()}%',
                    titleStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Column(
          children: <Widget>[
            for (final slice in data.slices)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: slice.color,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        slice.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    AppText(
                      '${slice.percentOf(total).toStringAsFixed(1)}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppText(
                      formatMoney(slice.amount, currency: currencyCode),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _PaymentMethodBreakdown extends StatelessWidget {
  const _PaymentMethodBreakdown({
    required this.data,
    required this.currencyCode,
  });

  final AnalyticsData data;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: <Widget>[
        for (final item in data.paymentMethods)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    item.method?.icon ?? Icons.help_outline,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: AppText(
                              item.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          AppText(
                            '${item.percentOf(data.monthTotal).toStringAsFixed(0)}%',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          AppText(
                            formatMoney(item.amount, currency: currencyCode),
                            style: theme.textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (item.percentOf(data.monthTotal) / 100)
                              .clamp(0.0, 1.0),
                          minHeight: 5,
                          backgroundColor: theme.colorScheme.outlineVariant
                              .withValues(alpha: 0.35),
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            AppPalette.cyan,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppText(
                  '${item.count}件',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _MonthComparison extends StatelessWidget {
  const _MonthComparison({required this.data, required this.currencyCode});

  final AnalyticsData data;
  final String currencyCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (data.currentDaily.isEmpty) {
      return const _EmptyChart(message: 'no_data');
    }

    final maxValue = math.max(
      data.currentDaily.isEmpty ? 0 : data.currentDaily.last,
      data.previousDaily.isEmpty ? 0 : data.previousDaily.last,
    );
    final maxY = math.max(1000.0, maxValue * 1.15).toDouble();
    final maxX = data.currentDaily.length.toDouble();
    final increased = data.momDelta > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              increased ? Icons.trending_up : Icons.trending_down,
              size: 18,
              color: increased ? AppPalette.amber : AppPalette.emerald,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AppText(
                data.previousMonthTotal == 0
                    ? 'no_data_for_last_month'
                    : '先月より ${formatMoney(data.momDelta.abs(), currency: currencyCode)} '
                        '${increased ? '多い' : '少ない'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (data.previousMonthTotal > 0)
              AppText(
                '${data.momPercent >= 0 ? '+' : ''}'
                '${data.momPercent.toStringAsFixed(1)}%',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: increased ? AppPalette.amber : AppPalette.emerald,
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 140,
          child: LineChart(
            LineChartData(
              minX: 1,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: const FlTitlesData(
                leftTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles:
                    AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              lineTouchData: const LineTouchData(enabled: false),
              lineBarsData: <LineChartBarData>[
                LineChartBarData(
                  spots: <FlSpot>[
                    for (var i = 0; i < data.currentDaily.length; i++)
                      FlSpot(
                          (i + 1).toDouble(), data.currentDaily[i].toDouble()),
                  ],
                  isCurved: false,
                  barWidth: 2.4,
                  color: AppPalette.cyan,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: AppPalette.cyan.withValues(alpha: 0.12),
                  ),
                ),
                LineChartBarData(
                  spots: <FlSpot>[
                    for (var i = 0; i < data.previousDaily.length; i++)
                      FlSpot(
                        (i + 1).toDouble(),
                        data.previousDaily[i].toDouble(),
                      ),
                  ],
                  isCurved: false,
                  barWidth: 1.6,
                  color: AppPalette.violet.withValues(alpha: 0.7),
                  dashArray: const <int>[4, 4],
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: <Widget>[
            const _LegendDot(color: AppPalette.cyan, label: 'paycycle.this_month'),
            const SizedBox(width: 14),
            const _LegendDot(
              color: AppPalette.violet,
              label: 'last_month',
            ),
            const Spacer(),
            AppText(
              '${data.monthCount}件 / ${data.previousMonthCount}件',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 14,
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        AppText(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
