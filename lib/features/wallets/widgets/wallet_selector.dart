import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/localization/localization.dart';
import '../../../domain/models/wallet.dart';

/// Optional wallet dropdown used by receipts, quick payments and income.
///
/// Only wallets with the same currency are offered, because money is stored in
/// each wallet's own currency. Different currencies are handled by transfers
/// where the user enters both amounts.
class WalletSelector extends StatelessWidget {
  const WalletSelector({
    super.key,
    required this.wallets,
    required this.selectedId,
    required this.onChanged,
    this.currency,
    this.allowNone = true,
    this.label = 'wallet',
  });

  final List<Wallet> wallets;
  final String? selectedId;
  final ValueChanged<String?> onChanged;
  final String? currency;
  final bool allowNone;
  final String label;

  @override
  Widget build(BuildContext context) {
    final matching = wallets
        .where((wallet) => !wallet.archived)
        .where((wallet) =>
            currency == null ||
            wallet.currency.toUpperCase() == currency!.toUpperCase())
        .toList(growable: false);
    final selected = matching.any((wallet) => wallet.id == selectedId)
        ? selectedId
        : null;

    return DropdownButtonFormField<String>(
      initialValue: allowNone ? (selected ?? '') : selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: context.tr(label),
        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
      ),
      items: <DropdownMenuItem<String>>[
        if (allowNone)
          const DropdownMenuItem<String>(
            value: '',
            child: AppText('not_set'),
          ),
        for (final wallet in matching)
          DropdownMenuItem<String>(
            value: wallet.id,
            child: Row(
              children: <Widget>[
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: Color(wallet.colorValue),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AppText(
                    wallet.name,
                    translate: false,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                AppText(
                  wallet.currency,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
      ],
      onChanged: (value) => onChanged(value == null || value.isEmpty ? null : value),
      validator: allowNone
          ? null
          : (value) => (value == null || value.isEmpty)
              ? context.tr('please_choose_a_wallet')
              : null,
    );
  }
}

/// Small inline hint + link when no wallets exist yet.
class NoWalletsHint extends StatelessWidget {
  const NoWalletsHint({super.key});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        const Icon(Icons.info_outline, size: 16),
        const SizedBox(width: 6),
        const Expanded(child: AppText('no_wallets_yet')),
        TextButton(
          onPressed: () => context.push('/wallets'),
          child: const AppText('manage_wallets'),
        ),
      ],
    );
  }
}
