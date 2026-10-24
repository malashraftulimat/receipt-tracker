import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/debt.dart';
import 'widgets/debt_editor_dialog.dart';

class DebtsPage extends ConsumerStatefulWidget {
  const DebtsPage({super.key});

  @override
  ConsumerState<DebtsPage> createState() => _DebtsPageState();
}

class _DebtsPageState extends ConsumerState<DebtsPage> {
  DebtStatus? _status;
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    await showDialog<Debt>(
      context: context,
      builder: (context) => const DebtEditorDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final debtsAsync = ref.watch(debtsProvider);
    final totalsAsync = ref.watch(debtTotalsProvider);
    final base = ref.watch(defaultCurrencyProvider).code;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('debts'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('add_debt'),
              onPressed: _add,
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: debtsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppText('could_not_load_data: $error'),
            ),
          ),
          data: (debts) {
            final totals = totalsAsync.valueOrNull ?? const DebtTotals();
            final filtered = debts.where((debt) {
              if (_status != null && debt.derivedStatus != _status) {
                return false;
              }
              if (_query.trim().isNotEmpty &&
                  !debt.counterparty
                      .toLowerCase()
                      .contains(_query.trim().toLowerCase())) {
                return false;
              }
              return true;
            }).toList(growable: false);

            return ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                8,
                context.pagePadding,
                40,
              ),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: _TotalCard(
                        label: 'owed_to_me',
                        amount: totals.owedToMe,
                        currency: base,
                        color: AppPalette.emerald,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TotalCard(
                        label: 'i_owe',
                        amount: totals.iOwe,
                        currency: base,
                        color: AppPalette.danger,
                      ),
                    ),
                  ],
                ),
                if (totals.missingRateCount > 0) ...<Widget>[
                  const SizedBox(height: 6),
                  AppText(
                    'debt_totals_missing_rate',
                    count: totals.missingRateCount,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _search,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: context.tr('search_person'),
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: <Widget>[
                      ChoiceChip(
                        label: const AppText('all'),
                        selected: _status == null,
                        onSelected: (_) => setState(() => _status = null),
                      ),
                      const SizedBox(width: 8),
                      for (final status in DebtStatus.values) ...<Widget>[
                        ChoiceChip(
                          label: AppText('debt_status_${status.wireName}'),
                          selected: _status == status,
                          onSelected: (_) => setState(() => _status = status),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: <Widget>[
                        const Icon(Icons.handshake_outlined, size: 40),
                        const SizedBox(height: 10),
                        const AppText('no_debts_yet'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _add,
                          icon: const Icon(Icons.add),
                          label: const AppText('add_debt'),
                        ),
                      ],
                    ),
                  )
                else
                  for (final debt in filtered)
                    _DebtTile(
                      debt: debt,
                      onTap: () => context.push('/debt/${debt.id}'),
                    ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  const _TotalCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
  });

  final String label;
  final double amount;
  final String currency;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: AppPalette.card(context, accent: color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AppText(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          AppText(
            formatMoney(amount, currency: currency),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  const _DebtTile({required this.debt, required this.onTap});

  final Debt debt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (debt.derivedStatus) {
      DebtStatus.open => AppPalette.cyan,
      DebtStatus.partial => AppPalette.amber,
      DebtStatus.settled => AppPalette.emerald,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppPalette.card(context, accent: statusColor),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.16),
          child: Icon(
            debt.direction.isLent
                ? Icons.call_received_outlined
                : Icons.call_made_outlined,
            color: statusColor,
          ),
        ),
        title: Text(
          debt.counterparty,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppText(debt.direction.isLent ? 'i_lent' : 'i_borrowed'),
            if (debt.dueDate != null)
              AppText(
                'due_date_value',
                params: <String, Object?>{
                  'date': formatDateShortJa(debt.dueDate!),
                },
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
              formatMoney(debt.remaining, currency: debt.currency),
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: AppPalette.tintedPill(statusColor, radius: 8),
              child: AppText(
                'debt_status_${debt.derivedStatus.wireName}',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
