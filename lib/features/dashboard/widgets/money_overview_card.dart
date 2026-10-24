import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/localization.dart';
import '../../../core/settings/currency_provider.dart';
import '../../../core/settings/exchange_rates_provider.dart';
import '../../../core/settings/money_view_provider.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/exchange_rates.dart';
import '../../../domain/models/money_totals.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/wallet_ledger.dart';
import '../../wallets/widgets/wallet_editor_dialog.dart';

class MoneyOverviewCard extends ConsumerWidget {
  const MoneyOverviewCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncTotals = ref.watch(moneyTotalsProvider);
    final view = ref.watch(moneyViewProvider);
    final base = ref.watch(defaultCurrencyProvider).code;
    final ledger = ref.watch(walletLedgerProvider).valueOrNull;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];
    final needsFx = wallets.any(
      (wallet) =>
          wallet.currency.trim().toUpperCase() != base.toUpperCase(),
    );
    final fx = needsFx
        ? ref.watch(exchangeRatesProvider).valueOrNull?.snapshot
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/wallets'),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: AppPalette.card(
              context,
              accent: AppPalette.emerald,
              radius: 20,
              glow: true,
            ),
            child: asyncTotals.when(
              loading: () => const SizedBox(
                height: 120,
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
              error: (error, _) => AppText(
                'could_not_load_data: $error',
                style: theme.textTheme.bodySmall,
              ),
              data: (totals) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _ViewSwitcher(
                    view: view,
                    onChanged: (value) =>
                        ref.read(moneyViewProvider.notifier).setView(value),
                  ),
                  const SizedBox(height: 10),
                  AppText(
                    view.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  AppText(
                    formatMoney(_amountFor(view, totals), currency: base),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  AppText(
                    'money.after_card_obligations',
                    params: <String, Object?>{
                      'amount': formatMoney(
                        totals.afterObligations,
                        currency: base,
                      ),
                    },
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: totals.cardWarning
                          ? AppPalette.danger
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight:
                          totals.cardWarning ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                  if (totals.cardWarning) ...<Widget>[
                    const SizedBox(height: 4),
                    AppText(
                      'money.card_warning',
                      params: <String, Object?>{
                        'amount': formatMoney(
                          totals.nextCardAmount,
                          currency: base,
                        ),
                        'date': totals.nextCardDueDate == null
                            ? '—'
                            : formatDateJa(totals.nextCardDueDate!),
                      },
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: AppPalette.danger,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (totals.missingRateCount > 0) ...<Widget>[
                    const SizedBox(height: 4),
                    AppText(
                      'fx.missing_rate_note',
                      count: totals.missingRateCount,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                  if (wallets.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 10),
                    _WalletList(
                      wallets: wallets,
                      ledger: ledger,
                      fx: fx,
                      fxBase: base,
                      onManage: () => context.push('/wallets'),
                    ),
                  ] else ...<Widget>[
                    const SizedBox(height: 10),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: AppText(
                            'no_wallets_yet',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _addWallet(context, ref, wallets),
                          child: const AppText('add_wallet'),
                        ),
                      ],
                    ),
                  ],
                  if (fx != null) ...<Widget>[
                    const SizedBox(height: 6),
                    AppText(
                      'fx.rates_as_of',
                      params: <String, Object?>{
                        'date': formatDateJa(fx.fetchedAt),
                      },
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _amountFor(MoneyView view, MoneyTotals totals) => switch (view) {
        MoneyView.available => totals.availableMoney,
        MoneyView.afterObligations => totals.afterObligations,
        MoneyView.netWorth => totals.netWorth,
      };

  static Future<void> _addWallet(
    BuildContext context,
    WidgetRef ref,
    List<Wallet> wallets,
  ) async {
    await showDialog<Wallet>(
      context: context,
      builder: (context) => WalletEditorDialog(wallets: wallets),
    );
  }
}

class _ViewSwitcher extends StatelessWidget {
  const _ViewSwitcher({required this.view, required this.onChanged});

  final MoneyView view;
  final ValueChanged<MoneyView> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SegmentedButton<MoneyView>(
        segments: const <ButtonSegment<MoneyView>>[
          ButtonSegment<MoneyView>(
            value: MoneyView.available,
            label: AppText('money.short_available'),
          ),
          ButtonSegment<MoneyView>(
            value: MoneyView.afterObligations,
            label: AppText('money.short_after'),
          ),
          ButtonSegment<MoneyView>(
            value: MoneyView.netWorth,
            label: AppText('money.short_net'),
          ),
        ],
        selected: <MoneyView>{view},
        showSelectedIcon: false,
        onSelectionChanged: (selection) => onChanged(selection.first),
      ),
    );
  }
}

class _WalletList extends StatelessWidget {
  const _WalletList({
    required this.wallets,
    required this.ledger,
    required this.fx,
    required this.fxBase,
    required this.onManage,
  });

  final List<Wallet> wallets;
  final WalletLedger? ledger;
  final FxSnapshot? fx;
  final String fxBase;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = wallets.where((wallet) => !wallet.archived).toList();
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 4),
      title: AppText(
        'wallets',
        style: theme.textTheme.labelLarge
            ?.copyWith(fontWeight: FontWeight.w700),
      ),
      children: <Widget>[
        for (final wallet in active)
          _WalletRow(
            wallet: wallet,
            account: ledger?.accountFor(wallet.id),
            fx: fx,
            fxBase: fxBase,
            onTap: () => context.push('/wallet/${wallet.id}'),
          ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: onManage,
            child: const AppText('manage_wallets'),
          ),
        ),
      ],
    );
  }
}

class _WalletRow extends StatelessWidget {
  const _WalletRow({
    required this.wallet,
    required this.account,
    required this.fx,
    required this.fxBase,
    required this.onTap,
  });

  final Wallet wallet;
  final WalletAccount? account;
  final FxSnapshot? fx;
  final String fxBase;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = wallet.isCredit ? (account?.owed ?? 0) : (account?.balance ?? 0);
    final missingRate = fx != null &&
        wallet.currency.toUpperCase() != fxBase.toUpperCase() &&
        fx!.rateFor(wallet.currency, fxBase) == null;
    final converted = missingRate || fx == null
        ? null
        : fx!.convert(amount, wallet.currency, fxBase);
    final latestRows = account?.latest(limit: 1) ?? const <WalletEntry>[];
    final latest = latestRows.isEmpty ? null : latestRows.first;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: Color(wallet.colorValue).withValues(alpha: 0.16),
        child: Icon(
          walletIcon(wallet.type),
          size: 16,
          color: Color(wallet.colorValue),
        ),
      ),
      title: Row(
        children: <Widget>[
          Expanded(
            child: AppText(
              wallet.name,
              translate: false,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          AppText(
            formatMoney(amount, currency: wallet.currency),
            style: theme.textTheme.bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
      subtitle: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              latest == null
                  ? (wallet.isCredit ? context.tr('owed') : context.tr('balance'))
                  : (latest.title.isEmpty
                      ? context.tr('transaction')
                      : latest.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (converted != null && wallet.currency != fxBase)
            AppText(
              '≈ ${formatMoney(converted, currency: fxBase)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    );
  }
}
