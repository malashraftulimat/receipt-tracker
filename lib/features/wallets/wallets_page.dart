import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/settings/exchange_rates_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/exchange_rates.dart';
import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_ledger.dart';
import 'widgets/wallet_editor_dialog.dart';

class WalletsPage extends ConsumerWidget {
  const WalletsPage({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final wallets = ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    await showDialog<Wallet>(
      context: context,
      builder: (context) => WalletEditorDialog(wallets: wallets),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletsAsync = ref.watch(walletsProvider);
    final ledgerAsync = ref.watch(walletLedgerProvider);
    final base = ref.watch(defaultCurrencyProvider).code;
    final knownWallets =
        ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];
    final needsFx = knownWallets.any(
      (wallet) => wallet.currency.trim().toUpperCase() != base.toUpperCase(),
    );
    final fx =
        needsFx ? ref.watch(exchangeRatesProvider).valueOrNull?.snapshot : null;

    return Scaffold(
      appBar: AppBar(
        title: const AppText('wallets'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('add_wallet'),
              onPressed: () => _add(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: walletsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppText('could_not_load_data: $error'),
            ),
          ),
          data: (wallets) {
            if (wallets.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const Icon(Icons.account_balance_wallet_outlined,
                          size: 44),
                      const SizedBox(height: 12),
                      const AppText('no_wallets_yet'),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () => _add(context, ref),
                        icon: const Icon(Icons.add),
                        label: const AppText('add_wallet'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final active =
                wallets.where((wallet) => !wallet.archived).toList(growable: false);
            final archived =
                wallets.where((wallet) => wallet.archived).toList(growable: false);
            final ledger = ledgerAsync.valueOrNull;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                context.pagePadding,
                8,
                context.pagePadding,
                40,
              ),
              children: <Widget>[
                for (final wallet in active)
                  _WalletTile(
                    wallet: wallet,
                    account: ledger?.accountFor(wallet.id),
                    fx: fx,
                    onTap: () => context.push('/wallet/${wallet.id}'),
                  ),
                if (archived.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 16),
                  AppText(
                    'archived',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 6),
                  for (final wallet in archived)
                    _WalletTile(
                      wallet: wallet,
                      account: ledger?.accountFor(wallet.id),
                      fx: fx,
                      onTap: () => context.push('/wallet/${wallet.id}'),
                    ),
                ],
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _add(context, ref),
                  icon: const Icon(Icons.add, size: 18),
                  label: const AppText('add_wallet'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WalletTile extends StatelessWidget {
  const _WalletTile({
    required this.wallet,
    required this.account,
    required this.fx,
    required this.onTap,
  });

  final Wallet wallet;
  final WalletAccount? account;
  final FxSnapshot? fx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final amount = wallet.isCredit ? (account?.owed ?? 0) : (account?.balance ?? 0);
    final missingRate = fx != null &&
        wallet.currency.toUpperCase() != fx!.base.toUpperCase() &&
        fx!.rateFor(wallet.currency, fx!.base) == null;
    final converted = fx == null || missingRate
        ? null
        : fx!.convert(amount, wallet.currency, fx!.base);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: AppPalette.card(context, accent: Color(wallet.colorValue)),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: CircleAvatar(
          backgroundColor: Color(wallet.colorValue).withValues(alpha: 0.16),
          child: Icon(walletIcon(wallet.type), color: Color(wallet.colorValue)),
        ),
        title: Row(
          children: <Widget>[
            Expanded(
              child: AppText(
                wallet.name,
                translate: false,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            if (wallet.last4 != null)
              AppText(
                '•••• ${wallet.last4}',
                style: theme.textTheme.labelSmall,
              ),
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppText(
              wallet.type.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (converted != null)
              AppText(
                '≈ ${formatMoney(converted, currency: fx!.base)}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            if (fx != null && fx!.isManual(wallet.currency, fx!.base))
              const AppText(
                'fx.manual',
                style: TextStyle(fontSize: 10),
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
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            AppText(
              formatMoney(amount, currency: wallet.currency),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: wallet.isCredit
                    ? (amount > 0 ? AppPalette.danger : AppPalette.emerald)
                    : null,
              ),
            ),
            AppText(
              wallet.isCredit ? 'owed' : 'balance',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
