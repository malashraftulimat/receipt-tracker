import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/settings/exchange_rates_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_adjustment.dart';
import '../../domain/models/wallet_ledger.dart';
import 'widgets/transfer_dialog.dart';
import 'widgets/wallet_editor_dialog.dart';

class WalletDetailPage extends ConsumerWidget {
  const WalletDetailPage({super.key, required this.walletId});

  final String walletId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Wallet wallet,
  ) async {
    final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    await showDialog<Wallet>(
      context: context,
      builder: (context) => WalletEditorDialog(
        wallet: wallet,
        wallets: wallets,
      ),
    );
  }

  Future<void> _transfer(
    BuildContext context,
    WidgetRef ref,
    Wallet wallet,
  ) async {
    final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    await showDialog<bool>(
      context: context,
      builder: (context) => TransferDialog(
        wallets: wallets,
        initialFromId: wallet.id,
      ),
    );
  }

  Future<void> _adjust(
    BuildContext context,
    WidgetRef ref,
    Wallet wallet,
    WalletAccount account,
  ) async {
    final target = TextEditingController(
      text: formatAmountDigits(account.balance),
    );
    final note = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final delta = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('adjust_balance'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AppText(
                'current_balance_amount',
                params: <String, Object?>{
                  'amount': formatMoney(
                    account.balance,
                    currency: wallet.currency,
                  ),
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: target,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                  signed: true,
                ),
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                ],
                decoration: InputDecoration(
                  labelText: context.tr('target_balance'),
                  prefixText: '${wallet.currency} ',
                  prefixIcon: const Icon(Icons.tune_outlined),
                ),
                validator: (value) {
                  final parsed = parseAmountInput(value ?? '');
                  if (parsed == null) {
                    return context.tr('please_enter_a_number');
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: note,
                decoration: InputDecoration(
                  labelText: context.tr('note'),
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 8),
              const AppText(
                'adjustments_are_recorded_as_transactions',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              final desired = parseAmountInput(target.text);
              if (desired == null) return;
              Navigator.pop(context, desired - account.balance);
            },
            child: const AppText('save'),
          ),
        ],
      ),
    );
    final noteText = note.text.trim();
    target.dispose();
    note.dispose();
    if (delta == null || delta.abs() < 0.0001) return;

    try {
      final now = DateTime.now();
      await ref.read(walletAdjustmentRepositoryProvider).create(
            WalletAdjustment(
              id: '',
              userId: ref.read(userIdProvider) ?? '',
              walletId: wallet.id,
              amount: delta,
              occurredAt: now,
              note: noteText.isEmpty ? null : noteText,
              createdAt: now,
              updatedAt: now,
            ),
          );
      ref.invalidate(walletAdjustmentsProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('could_not_save: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wallet = ref.watch(walletByIdProvider(walletId));
    final account = ref.watch(walletAccountProvider(walletId));
    final ledgerAsync = ref.watch(walletLedgerProvider);
    final base = ref.watch(defaultCurrencyProvider).code;
    final needsFx = wallet != null &&
        wallet.currency.trim().toUpperCase() != base.toUpperCase();
    final fx = needsFx
        ? ref.watch(exchangeRatesProvider).valueOrNull?.snapshot
        : null;

    if (wallet == null && ledgerAsync.isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const AppText('wallet')),
        body: const Center(child: AppText('wallet_not_found')),
      );
    }

    final theme = Theme.of(context);
    final amount = wallet.isCredit ? (account?.owed ?? 0) : (account?.balance ?? 0);
    final missingRate = fx != null &&
        wallet.currency.toUpperCase() != fx.base.toUpperCase() &&
        fx.rateFor(wallet.currency, fx.base) == null;
    final converted = fx == null || missingRate
        ? null
        : fx.convert(amount, wallet.currency, fx.base);
    final settlement = _settlementName(ref, wallet);

    return Scaffold(
      appBar: AppBar(
        title: AppText(wallet.name, translate: false),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('edit'),
              onPressed: () => _edit(context, ref, wallet),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: context.tr('transfer'),
              onPressed: () => _transfer(context, ref, wallet),
              icon: const Icon(Icons.swap_horiz),
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
                accent: Color(wallet.colorValue),
                radius: 20,
                glow: true,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      CircleAvatar(
                        backgroundColor:
                            Color(wallet.colorValue).withValues(alpha: 0.18),
                        child: Icon(
                          walletIcon(wallet.type),
                          color: Color(wallet.colorValue),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            AppText(wallet.type.label,
                                style: theme.textTheme.labelSmall),
                            AppText(
                              wallet.currency,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (wallet.archived)
                        const Chip(label: AppText('archived')),
                      if (wallet.reserved)
                        const Chip(label: AppText('reserved')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  AppText(
                    wallet.isCredit ? 'amount_owed' : 'balance',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  AppText(
                    formatMoney(amount, currency: wallet.currency),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: wallet.isCredit && amount > 0
                          ? AppPalette.danger
                          : null,
                    ),
                  ),
                  if (fx != null &&
                      converted != null &&
                      wallet.currency != fx.base)
                    AppText(
                      '≈ ${formatMoney(converted, currency: fx.base)}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  if (fx != null && fx.isManual(wallet.currency, fx.base))
                    const AppText(
                      'fx.manual',
                      style: TextStyle(fontSize: 11),
                    ),
                  if (missingRate)
                    AppText(
                      'rate_missing_for_currency',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (wallet.isCredit) ...<Widget>[
              _Section(
                title: 'credit_card',
                children: <Widget>[
                  _Row(
                    label: 'credit_limit',
                    value: formatMoney(
                      wallet.creditLimit ?? 0,
                      currency: wallet.currency,
                    ),
                  ),
                  _Row(
                    label: 'available_credit',
                    value: formatMoney(
                      account?.availableCredit ?? 0,
                      currency: wallet.currency,
                    ),
                  ),
                  _Row(
                    label: 'amount_owed',
                    value: formatMoney(
                      account?.owed ?? 0,
                      currency: wallet.currency,
                    ),
                    emphasize: true,
                  ),
                  _Row(
                    label: 'owed_this_cycle',
                    value: formatMoney(
                      account?.owedThisCycle() ?? 0,
                      currency: wallet.currency,
                    ),
                  ),
                  _Row(
                    label: 'next_due_date',
                    value: account?.nextDueDate() == null
                        ? '—'
                        : formatDateJa(account!.nextDueDate()!),
                  ),
                  _Row(
                    label: 'amount_due',
                    value: formatMoney(
                      account?.owed ?? 0,
                      currency: wallet.currency,
                    ),
                  ),
                  if (wallet.closingDay != null)
                    _Row(
                      label: 'closing_day',
                      value: '${wallet.closingDay}',
                    ),
                  if (wallet.paymentDueDay != null)
                    _Row(
                      label: 'payment_due_day',
                      value: '${wallet.paymentDueDay}',
                    ),
                  if (settlement != null)
                    _Row(label: 'settlement_wallet', value: settlement),
                ],
              ),
              const SizedBox(height: 14),
            ] else ...<Widget>[
              _Section(
                title: 'wallet',
                children: <Widget>[
                  _Row(
                    label: 'opening_balance',
                    value: formatMoney(
                      wallet.openingBalance,
                      currency: wallet.currency,
                    ),
                  ),
                  _Row(
                    label: 'balance',
                    value: formatMoney(
                      account?.balance ?? 0,
                      currency: wallet.currency,
                    ),
                    emphasize: true,
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _transfer(context, ref, wallet),
                    icon: const Icon(Icons.swap_horiz, size: 18),
                    label: const AppText('transfer'),
                  ),
                ),
                if (!wallet.isCredit) ...<Widget>[
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: account == null
                          ? null
                          : () => _adjust(context, ref, wallet, account),
                      icon: const Icon(Icons.tune_outlined, size: 18),
                      label: const AppText('adjust_balance'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 18),
            AppText(
              'latest_transactions',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            if (account == null || account.entries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: AppText('no_transactions_yet'),
              )
            else
              for (final entry in account.latest(limit: 20))
                _EntryTile(entry: entry, wallet: wallet),
          ],
        ),
      ),
    );
  }

  String? _settlementName(WidgetRef ref, Wallet wallet) {
    final id = wallet.settlementWalletId;
    if (id == null) return null;
    final wallets = ref.watch(walletsProvider).valueOrNull;
    if (wallets == null) return null;
    for (final candidate in wallets) {
      if (candidate.id == id) return candidate.name;
    }
    return null;
  }
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({required this.entry, required this.wallet});

  final WalletEntry entry;
  final Wallet wallet;

  IconData get _icon => switch (entry.kind) {
        WalletEntryKind.expense => Icons.remove_circle_outline,
        WalletEntryKind.income => Icons.add_circle_outline,
        WalletEntryKind.transferIn => Icons.download_outlined,
        WalletEntryKind.transferOut => Icons.upload_outlined,
        WalletEntryKind.adjustment => Icons.tune_outlined,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final incoming = entry.signedAmount >= 0;
    final color = incoming ? AppPalette.emerald : AppPalette.danger;
    final title = entry.title.trim().isEmpty
        ? switch (entry.kind) {
            WalletEntryKind.expense => 'no_store_name',
            WalletEntryKind.adjustment => 'adjustment',
            _ => 'transaction',
          }
        : null;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icon, color: color, size: 20),
      title: title == null
          ? Text(
              entry.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            )
          : AppText(title),
      subtitle: AppText(
        formatDateJa(entry.date) +
            (entry.subtitle == null || entry.subtitle!.trim().isEmpty
                ? ''
                : ' · ${entry.subtitle!.trim()}'),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: AppText(
        '${incoming ? '+' : '−'}'
        '${formatMoney(entry.signedAmount.abs(), currency: wallet.currency)}',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppPalette.card(context, radius: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppText(
            title,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

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
          AppText(
            value,
            style: emphasize
                ? theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w800)
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
