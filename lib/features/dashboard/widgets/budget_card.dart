import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/budget_gradient_bar.dart';
import '../../../data/providers.dart';
import '../../../domain/models/monthly_budget.dart';
import '../../../core/localization/localization.dart';

/// Compact "remaining budget / daily allowance / pacing" widget.
class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final month = DateTime(now.year, now.month);
    final asyncSummary = ref.watch(budgetSummaryProvider(month));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: asyncSummary.when(
        loading: () => const SizedBox(
          height: 72,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
        error: (error, _) => _Shell(
          child: AppText(
            '予算を読み込めませんでした',
            style: theme.textTheme.bodySmall,
          ),
        ),
        data: (summary) {
          if (!summary.configured) {
            return _Shell(
              accent: AppPalette.violet,
              child: Row(
                children: <Widget>[
                  const Icon(
                    Icons.savings_outlined,
                    color: AppPalette.amber,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        AppText(
                          '今月の予算を設定',
                          style: theme.textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        AppText(
                          '月収・貯蓄目標・固定費から、1日に使える金額を計算します',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: () => context.push('/budget'),
                    child: const AppText('設定'),
                  ),
                ],
              ),
            );
          }

          final statusColor = switch (summary.periodStatus) {
            BudgetStatus.onTrack => AppPalette.emerald,
            BudgetStatus.warning => AppPalette.amber,
            BudgetStatus.overBudget => AppPalette.danger,
            BudgetStatus.unset => AppPalette.violet,
          };
          final remainingLabel = summary.periodStart == null
              ? '今月の残り予算'
              : summary.periodRemainingLabel;

          return _Shell(
            accent: statusColor,
            onTap: () => context.push('/budget'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    AppText(
                      remainingLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: AppPalette.tintedPill(statusColor, radius: 8),
                      child: AppText(
                        summary.periodStatusLabel,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                AppText(
                  formatYen(summary.periodRemaining.abs()),
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: summary.periodRemaining < 0
                        ? AppPalette.danger
                        : AppPalette.emerald,
                  ),
                ),
                const SizedBox(height: 8),
                BudgetGradientBar(
                  value: summary.periodProgress,
                  height: 9,
                ),
                const SizedBox(height: 8),
                Row(
                  children: <Widget>[
                    AppText(
                      '1日 ${formatYen(summary.dailyAllowance)}',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    AppText(
                      '今日 ${formatYen(summary.todaySpent)}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    AppText(
                      '貯蓄 ${(summary.savingsProgress * 100).round()}%',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Shell extends StatelessWidget {
  const _Shell({required this.child, this.onTap, this.accent});

  final Widget child;
  final VoidCallback? onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: AppPalette.card(context, accent: accent, glow: true),
          child: child,
        ),
      ),
    );
  }
}
