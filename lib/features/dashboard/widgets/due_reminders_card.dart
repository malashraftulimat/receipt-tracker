import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../core/localization/localization.dart';

/// Upcoming 支払期限 (utility bills / 振込用紙) with a countdown.
class DueRemindersCard extends ConsumerWidget {
  const DueRemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncDue = ref.watch(upcomingDueProvider);

    final receipts = asyncDue.valueOrNull ?? const [];
    if (receipts.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final visible = receipts.take(3).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(
                  Icons.event_note_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                AppText(
                  '支払期限が近いもの',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                AppText(
                  '${receipts.length}件',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            for (final receipt in visible)
              _DueRow(
                title: receipt.displayMerchant,
                amount: receipt.totalAmount,
                dueDate: receipt.dueDate!,
                today: today,
                onTap: () => context.push('/receipt/${receipt.id}'),
              ),
          ],
        ),
      ),
    );
  }
}

class _DueRow extends StatelessWidget {
  const _DueRow({
    required this.title,
    required this.amount,
    required this.dueDate,
    required this.today,
    required this.onTap,
  });

  final String title;
  final int amount;
  final DateTime dueDate;
  final DateTime today;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = target.difference(today).inDays;

    final color = days < 0 || days <= 3
        ? theme.colorScheme.error
        : days <= 7
            ? const Color(0xFFEF6C00)
            : theme.colorScheme.primary;

    final label = days < 0
        ? '${-days}日超過'
        : days == 0
            ? '今日'
            : 'あと$days日';

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppText(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  AppText(
                    '${formatDateShortJa(dueDate)} ・ ${formatYen(amount)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: AppText(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
