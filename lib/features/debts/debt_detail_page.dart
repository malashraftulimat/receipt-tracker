import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../data/services/calendar_export_service.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/reminder.dart';
import 'widgets/debt_editor_dialog.dart';
import 'widgets/repayment_dialog.dart';

class DebtDetailPage extends ConsumerWidget {
  const DebtDetailPage({super.key, required this.debtId});

  final String debtId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Debt debt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('delete_debt'),
        content: const AppText('delete_debt_confirm'),
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
    await ref.read(debtRepositoryProvider).delete(debt.id);
    ref.invalidate(debtsProvider);
    if (context.mounted) Navigator.pop(context);
  }

  Future<void> _markSettled(
    BuildContext context,
    WidgetRef ref,
    Debt debt,
  ) async {
    await ref.read(debtRepositoryProvider).save(
          debt.copyWith(status: DebtStatus.settled),
        );
    ref.invalidate(debtsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debt = ref.watch(debtByIdProvider(debtId));
    final debtsAsync = ref.watch(debtsProvider);
    final theme = Theme.of(context);

    if (debt == null && debtsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (debt == null) {
      return Scaffold(
        appBar: AppBar(title: const AppText('debt')),
        body: const Center(child: AppText('debt_not_found')),
      );
    }

    final wallet = _walletName(ref, debt.walletId);
    final statusColor = switch (debt.derivedStatus) {
      DebtStatus.open => AppPalette.cyan,
      DebtStatus.partial => AppPalette.amber,
      DebtStatus.settled => AppPalette.emerald,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(
          debt.counterparty,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('edit'),
              onPressed: () => showDialog<Debt>(
                context: context,
                builder: (context) => DebtEditorDialog(debt: debt),
              ),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.tr('delete'),
              onPressed: () => _delete(context, ref, debt),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            40,
          ),
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(18),
              decoration: AppPalette.card(
                context,
                accent: statusColor,
                radius: 20,
                glow: true,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        debt.direction.isLent
                            ? Icons.call_received_outlined
                            : Icons.call_made_outlined,
                        color: statusColor,
                      ),
                      const SizedBox(width: 8),
                      AppText(
                        debt.direction.isLent ? 'i_lent' : 'i_borrowed',
                        style: theme.textTheme.labelLarge,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: AppPalette.tintedPill(statusColor, radius: 8),
                        child: AppText(
                          'debt_status_${debt.derivedStatus.wireName}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  AppText(
                    'remaining_amount',
                    params: <String, Object?>{
                      'amount': formatMoney(
                        debt.remaining,
                        currency: debt.currency,
                      ),
                    },
                    style: theme.textTheme.labelSmall,
                  ),
                  AppText(
                    formatMoney(debt.remaining, currency: debt.currency),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _Row(
                    label: 'amount',
                    value: formatMoney(debt.amount, currency: debt.currency),
                  ),
                  _Row(
                    label: 'repaid_amount',
                    value: formatMoney(
                      debt.repaidAmount,
                      currency: debt.currency,
                    ),
                  ),
                  _Row(label: 'date', value: formatDateJa(debt.date)),
                  if (debt.dueDate != null)
                    _Row(
                      label: 'due_date',
                      value: formatDateJa(debt.dueDate!),
                    ),
                  if (wallet != null)
                    _Row(label: 'wallet', value: wallet),
                  if ((debt.note ?? '').trim().isNotEmpty)
                    _Row(label: 'note', value: debt.note!.trim()),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                if (debt.derivedStatus != DebtStatus.settled) ...<Widget>[
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => showDialog<bool>(
                        context: context,
                        builder: (context) => RepaymentDialog(debt: debt),
                      ),
                      icon: const Icon(Icons.add, size: 18),
                      label: const AppText('add_repayment'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: context.tr('mark_settled'),
                    onPressed: () => _markSettled(context, ref, debt),
                    icon: const Icon(Icons.check_circle_outline),
                  ),
                ],
                if (debt.dueDate != null) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: context.tr('add_to_calendar'),
                    onPressed: () => _addToCalendar(context, debt),
                    icon: const Icon(Icons.event_available_outlined),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            AppText(
              'repayments',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (debt.repayments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: AppText('no_repayments_yet'),
              )
            else
              for (final repayment in debt.repayments.reversed)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.check_circle_outline),
                  title: AppText(
                    formatMoney(repayment.amount, currency: debt.currency),
                  ),
                  subtitle: AppText(formatDateJa(repayment.date)),
                  trailing: repayment.note == null
                      ? null
                      : Text(
                          repayment.note!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
          ],
        ),
      ),
    );
  }

  static String? _walletName(WidgetRef ref, String? id) {
    if (id == null) return null;
    final wallets = ref.watch(walletsProvider).valueOrNull;
    if (wallets == null) return null;
    for (final wallet in wallets) {
      if (wallet.id == id) return wallet.name;
    }
    return null;
  }

  static Future<void> _addToCalendar(BuildContext context, Debt debt) async {
    final due = debt.dueDate;
    if (due == null) return;
    final reminder = ReminderItem(
      id: 'debt_${debt.id}',
      kind: ReminderKind.debt,
      title: debt.counterparty,
      amount: debt.outstanding,
      currency: debt.currency,
      dueDate: due,
      sourceId: debt.id,
    );
    final result = await CalendarExportService.exportReminder(
      reminder,
      description: '${formatMoney(debt.outstanding, currency: debt.currency)} '
          'due ${formatDateJa(due)}',
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: AppText('calendar_exported: $result')),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: AppText(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
