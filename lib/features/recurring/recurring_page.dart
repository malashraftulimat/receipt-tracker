import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/pay_cycle.dart';
import '../../domain/models/recurring_transaction.dart';
import '../dashboard/analytics_provider.dart';
import 'widgets/recurring_editor_dialog.dart';

class RecurringPage extends ConsumerWidget {
  const RecurringPage({super.key});

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    RecurringTransaction? item,
  }) async {
    await showDialog<RecurringTransaction>(
      context: context,
      builder: (context) => RecurringEditorDialog(item: item),
    );
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    RecurringTransaction item,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('delete_recurring'),
        content: const AppText('delete_recurring_confirm'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(recurringRepositoryProvider).delete(item.id);
    ref.invalidate(recurringTransactionsProvider);
  }

  Future<void> _postNow(BuildContext context, WidgetRef ref) async {
    try {
      final result = await ref.read(recurringPostingServiceProvider).postDue();
      if (result.postedAnything) {
        ref.invalidate(receiptsProvider);
        ref.invalidate(walletReceiptsProvider);
        ref.invalidate(incomeEntriesProvider);
        ref.invalidate(recurringTransactionsProvider);
        ref.invalidate(analyticsProvider);
        final now = DateTime.now();
        ref.invalidate(budgetSummaryProvider(DateTime(now.year, now.month)));
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: AppText(
            result.postedAnything
                ? 'recurring.posted_count'
                : 'recurring.nothing_due',
            params: <String, Object?>{'count': result.total},
          ),
        ),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('could_not_save: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncItems = ref.watch(recurringTransactionsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('recurring'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('add_recurring'),
              onPressed: () => _edit(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: asyncItems.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppText('could_not_load_data: $error'),
            ),
          ),
          data: (items) {
            return ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                8,
                context.pagePadding,
                40,
              ),
              children: <Widget>[
                AppText(
                  'recurring.help',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _postNow(context, ref),
                    icon: const Icon(Icons.play_circle_outline, size: 18),
                    label: const AppText('recurring.post_now'),
                  ),
                ),
                if (items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: <Widget>[
                        const Icon(Icons.repeat, size: 40),
                        const SizedBox(height: 10),
                        const AppText('recurring.none'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: () => _edit(context, ref),
                          icon: const Icon(Icons.add),
                          label: const AppText('add_recurring'),
                        ),
                      ],
                    ),
                  )
                else
                  for (final item in items)
                    _RecurringTile(
                      item: item,
                      onTap: () => _edit(context, ref, item: item),
                      onActive: (active) async {
                        await ref.read(recurringRepositoryProvider).save(
                              item.copyWith(active: active),
                            );
                        ref.invalidate(recurringTransactionsProvider);
                      },
                      onDelete: () => _delete(context, ref, item),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({
    required this.item,
    required this.onTap,
    required this.onActive,
    required this.onDelete,
  });

  final RecurringTransaction item;
  final VoidCallback onTap;
  final ValueChanged<bool> onActive;
  final VoidCallback onDelete;

  String _cycleLabel(BuildContext context) {
    final cycle = context.tr(item.cycle.name);
    if (item.cycle == PayCycle.weekly) {
      return '$cycle · ${formatWeekdayJa(item.weeklyStartWeekday)}';
    }
    if (item.cycle == PayCycle.monthly) {
      return '$cycle · ${item.monthlyPayDay == PayCycleConfig.endOfMonthPayDay ? context.tr('end_of_month') : item.monthlyPayDay}';
    }
    return cycle;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = item.nextOccurrence();
    final color = item.direction.isExpense ? AppPalette.danger : AppPalette.emerald;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppPalette.card(context, accent: color),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(
            item.direction.isExpense
                ? Icons.arrow_upward
                : Icons.arrow_downward,
            color: color,
          ),
        ),
        title: Text(
          item.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppText(
              item.direction.isExpense ? 'expense' : 'income',
              style: theme.textTheme.labelSmall,
            ),
            AppText(
              _cycleLabel(context),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (next != null)
              AppText(
                'recurring.next_date',
                params: <String, Object?>{'date': formatDateShortJa(next)},
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            AppText(
              formatMoney(item.amount, currency: item.currency),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.tr('active'),
                  onPressed: () => onActive(!item.active),
                  icon: Icon(
                    item.active
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 20,
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    if (value == 'delete') onDelete();
                  },
                  itemBuilder: (context) => const <PopupMenuEntry<String>>[
                    PopupMenuItem<String>(
                      value: 'delete',
                      child: AppText('delete'),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
