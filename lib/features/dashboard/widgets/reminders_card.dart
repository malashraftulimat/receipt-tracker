import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../data/services/calendar_export_service.dart';
import '../../../domain/models/reminder.dart';

/// In-app card/debt reminders shown when the dashboard opens.
class RemindersCard extends ConsumerWidget {
  const RemindersCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final reminders = ref.watch(remindersProvider).valueOrNull ?? const [];
    if (reminders.isEmpty) return const SizedBox.shrink();
    final now = DateTime.now();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: AppPalette.card(context, accent: AppPalette.amber),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.notifications_active_outlined,
                  size: 18,
                  color: AppPalette.amber,
                ),
                const SizedBox(width: 8),
                AppText(
                  'reminders.title',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: context.tr('reminders.how_they_work'),
                  onPressed: () => _showInfo(context),
                  icon: const Icon(Icons.info_outline, size: 18),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final reminder in reminders.take(4))
              _ReminderRow(reminder: reminder, now: now),
            if (reminders.length > 4)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: AppText(
                  'reminders.more',
                  params: <String, Object?>{
                    'count': reminders.length - 4,
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('reminders.how_they_work'),
        content: const SingleChildScrollView(
          child: AppText('reminders.explanation'),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('close'),
          ),
        ],
      ),
    );
  }
}

class _ReminderRow extends StatelessWidget {
  const _ReminderRow({required this.reminder, required this.now});

  final ReminderItem reminder;
  final DateTime now;

  String get _dueLabel {
    final days = reminder.daysUntil(now);
    if (days < 0) return 'reminders.overdue_days';
    if (days == 0) return 'reminders.due_today';
    return 'reminders.due_in_days';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final days = reminder.daysUntil(now);
    final color = days < 0
        ? AppPalette.danger
        : days <= 1
            ? AppPalette.amber
            : theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            reminder.kind == ReminderKind.creditCard
                ? Icons.credit_card
                : Icons.handshake_outlined,
            size: 18,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reminder.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                AppText(
                  _dueLabel,
                  count: days < 0 ? -days : days,
                  style: theme.textTheme.labelSmall?.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          AppText(
            formatMoney(reminder.amount, currency: reminder.currency),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: context.tr('add_to_calendar'),
            onPressed: () => _export(context),
            icon: const Icon(Icons.event_available_outlined, size: 18),
          ),
        ],
      ),
    );
  }

  Future<void> _export(BuildContext context) async {
    final result = await CalendarExportService.exportReminder(
      reminder,
      description: '${formatMoney(reminder.amount, currency: reminder.currency)} '
          'due ${formatDateJa(reminder.dueDate)}',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText('calendar_exported: $result')),
    );
  }
}
