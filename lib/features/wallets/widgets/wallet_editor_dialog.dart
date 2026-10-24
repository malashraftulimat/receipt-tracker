import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/currencies.dart';
import '../../../core/localization/localization.dart';
import '../../../core/settings/currency_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/wallet.dart';
import '../../settings/widgets/currency_picker.dart';

const List<int> kWalletColors = <int>[
  0xFF10B981,
  0xFF6366F1,
  0xFFF59E0B,
  0xFFEF4444,
  0xFF06B6D4,
  0xFF8B5CF6,
  0xFFEC4899,
  0xFF64748B,
];

IconData walletIcon(WalletType type) => switch (type) {
      WalletType.cash => Icons.payments_outlined,
      WalletType.bank => Icons.account_balance_outlined,
      WalletType.credit => Icons.credit_card,
      WalletType.debit => Icons.credit_score_outlined,
      WalletType.emoney => Icons.contactless_outlined,
      WalletType.transit => Icons.train_outlined,
      WalletType.savings => Icons.savings_outlined,
      WalletType.points => Icons.stars_outlined,
      WalletType.other => Icons.account_balance_wallet_outlined,
    };

class WalletEditorDialog extends ConsumerStatefulWidget {
  const WalletEditorDialog({
    super.key,
    this.wallet,
    required this.wallets,
  });

  final Wallet? wallet;
  final List<Wallet> wallets;

  @override
  ConsumerState<WalletEditorDialog> createState() => _WalletEditorDialogState();
}

class _WalletEditorDialogState extends ConsumerState<WalletEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _opening;
  late final TextEditingController _limit;
  late final TextEditingController _available;
  late final TextEditingController _last4;

  late WalletType _type;
  late Currency _currency;
  late int _color;
  late bool _includeInTotal;
  bool _includeTouched = false;
  late bool _reserved;
  late bool _archived;
  late int _closingDay;
  late int _dueDay;
  String? _settlementWalletId;
  bool _saving = false;
  String? _error;

  bool get _isCredit => _type.isCredit;

  @override
  void initState() {
    super.initState();
    final wallet = widget.wallet;
    _name = TextEditingController(text: wallet?.name ?? '');
    _opening = TextEditingController(
      text: wallet == null ? '' : formatEditable(wallet.openingBalance),
    );
    _limit = TextEditingController(
      text: wallet?.creditLimit == null
          ? ''
          : formatEditable(wallet!.creditLimit!),
    );
    _available = TextEditingController(
      text: wallet?.openingAvailable == null
          ? ''
          : formatEditable(wallet!.openingAvailable!),
    );
    _last4 = TextEditingController(text: wallet?.last4 ?? '');
    _type = wallet?.type ?? WalletType.cash;
    _currency = currencyByCode(wallet?.currency) ?? ref.read(defaultCurrencyProvider);
    _color = wallet?.colorValue ?? kWalletColors.first;
    _includeInTotal =
        wallet?.includeInTotal ?? _type.defaultIncludeInTotal;
    _includeTouched = wallet?.includeInTotal != null;
    _reserved = wallet?.reserved ?? false;
    _archived = wallet?.archived ?? false;
    _closingDay = wallet?.closingDay ?? 15;
    _dueDay = wallet?.paymentDueDay ?? 27;
    _settlementWalletId = wallet?.settlementWalletId;
  }

  @override
  void dispose() {
    _name.dispose();
    _opening.dispose();
    _limit.dispose();
    _available.dispose();
    _last4.dispose();
    super.dispose();
  }

  String formatEditable(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    return value.toString();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final existing = widget.wallet;
      final wallet = Wallet(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        type: _type,
        currency: _currency.code,
        openingBalance: _isCredit
            ? 0
            : (parseAmountInput(_opening.text) ?? 0),
        colorValue: _color,
        archived: _archived,
        last4: Wallet.sanitizeLast4(_last4.text),
        includeInTotal: _includeInTotal,
        reserved: _reserved,
        creditLimit:
            _isCredit ? parseAmountInput(_limit.text) ?? 0 : null,
        openingAvailable: _isCredit
            ? parseAmountInput(_available.text) ?? 0
            : null,
        closingDay: _isCredit ? _closingDay : null,
        paymentDueDay: _isCredit ? _dueDay : null,
        settlementWalletId: _isCredit ? _settlementWalletId : null,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(walletRepositoryProvider).save(wallet);
      ref.invalidate(walletsProvider);
      if (!mounted) return;
      Navigator.pop(context, wallet);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'could_not_save: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settlements = widget.wallets
        .where((wallet) => !wallet.isCredit && !wallet.archived)
        .where((wallet) => wallet.currency == _currency.code)
        .toList(growable: false);
    final nameSuggestions = <String>[];
    final seenNames = <String>{};
    for (final wallet in widget.wallets) {
      if (wallet.id == widget.wallet?.id) continue;
      final name = wallet.name.trim();
      if (name.isEmpty) continue;
      if (seenNames.add(name.toLowerCase())) nameSuggestions.add(name);
    }

    return AlertDialog(
      title: AppText(widget.wallet == null ? 'add_wallet' : 'edit_wallet'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  autofocus: widget.wallet == null,
                  decoration: InputDecoration(
                    labelText: context.tr('wallet_name'),
                    hintText: context.tr('wallet_name_hint'),
                    prefixIcon: const Icon(Icons.label_outline),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? context.tr('please_enter_a_name')
                      : null,
                ),
                if (nameSuggestions.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  AppText(
                    'wallet.recent_names',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: <Widget>[
                      for (final suggestion in nameSuggestions.take(6))
                        ActionChip(
                          label: Text(
                            suggestion,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          onPressed: () => setState(() {
                            _name.text = suggestion;
                            _name.selection = TextSelection.collapsed(
                              offset: suggestion.length,
                            );
                          }),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                DropdownButtonFormField<WalletType>(
                  initialValue: _type,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: context.tr('wallet_type'),
                    prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                  ),
                  items: <DropdownMenuItem<WalletType>>[
                    for (final type in WalletType.values)
                      DropdownMenuItem<WalletType>(
                        value: type,
                        child: Row(
                          children: <Widget>[
                            Icon(walletIcon(type), size: 18),
                            const SizedBox(width: 8),
                            AppText(type.label),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _type = value;
                      if (!_includeTouched) {
                        _includeInTotal = value.defaultIncludeInTotal;
                      }
                    });
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final picked = await showCurrencyPicker(
                      context,
                      selected: _currency,
                    );
                    if (picked != null) {
                      setState(() {
                        _currency = picked;
                        _settlementWalletId = null;
                      });
                    }
                  },
                  icon: const Icon(Icons.currency_exchange_outlined, size: 18),
                  label: Text(
                    '${_currency.code} · '
                    '${_currency.name(context.l10n.language)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!_isCredit) ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _opening,
                    enabled: widget.wallet == null,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr('opening_balance'),
                      helperText: widget.wallet == null
                          ? null
                          : context.tr('opening_balance_locked_use_adjust'),
                      prefixText: '${_currency.symbol} ',
                      prefixIcon: const Icon(Icons.start_outlined),
                    ),
                    validator: (value) {
                      if ((value ?? '').trim().isEmpty) return null;
                      return parseAmountInput(value!) == null
                          ? context.tr('please_enter_a_number')
                          : null;
                    },
                  ),
                ] else ...<Widget>[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _limit,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr('credit_limit'),
                      prefixText: '${_currency.symbol} ',
                      prefixIcon: const Icon(Icons.speed_outlined),
                    ),
                    validator: (value) {
                      final amount = parseAmountInput(value ?? '');
                      if (amount == null || amount <= 0) {
                        return context.tr('enter_an_amount_greater_than_0');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _available,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr('available_credit_at_setup'),
                      prefixText: '${_currency.symbol} ',
                      prefixIcon: const Icon(Icons.credit_score_outlined),
                    ),
                    validator: (value) {
                      final available = parseAmountInput(value ?? '');
                      final limit = parseAmountInput(_limit.text) ?? 0;
                      if (available == null || available < 0) {
                        return context.tr('please_enter_a_number');
                      }
                      if (available > limit) {
                        return context.tr('available_credit_cannot_exceed_limit');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _closingDay,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.tr('closing_day'),
                            prefixIcon: const Icon(Icons.event_outlined),
                          ),
                          items: _dayItems(context),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _closingDay = value);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          initialValue: _dueDay,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: context.tr('payment_due_day'),
                            prefixIcon: const Icon(Icons.event_available_outlined),
                          ),
                          items: _dayItems(context),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _dueDay = value);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: settlements.any(
                      (wallet) => wallet.id == _settlementWalletId,
                    )
                        ? _settlementWalletId
                        : '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('settlement_wallet_optional'),
                      prefixIcon: const Icon(Icons.account_balance_outlined),
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: AppText('not_set'),
                      ),
                      for (final wallet in settlements)
                        DropdownMenuItem<String>(
                          value: wallet.id,
                          child: AppText(
                            wallet.name,
                            translate: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _settlementWalletId =
                          value == null || value.isEmpty ? null : value,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                TextFormField(
                  controller: _last4,
                  keyboardType: TextInputType.number,
                  maxLength: 4,
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('card_last4_optional'),
                    helperText: context.tr('never_enter_full_card_number_cvv_or_pin'),
                    prefixIcon: const Icon(Icons.pin_outlined),
                  ),
                  validator: (value) {
                    final text = (value ?? '').trim();
                    if (text.isEmpty) return null;
                    if (!RegExp(r'^\d{4}$').hasMatch(text)) {
                      return context.tr('last4_must_be_four_digits');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 8,
                  children: <Widget>[
                    for (final color in kWalletColors)
                      InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => setState(() => _color = color),
                        child: Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: Color(color),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _color == color
                                  ? theme.colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: _color == color
                              ? const Icon(Icons.check,
                                  size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _includeInTotal,
                  onChanged: (value) => setState(() {
                    _includeInTotal = value;
                    _includeTouched = true;
                  }),
                  title: const AppText('include_in_available_money'),
                  subtitle: AppText(
                    _isCredit
                        ? 'credit_cards_are_always_excluded_from_available_money'
                        : 'savings_and_points_are_excluded_by_default',
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _reserved,
                  onChanged: (value) => setState(() => _reserved = value),
                  title: const AppText('reserved_not_for_spending'),
                ),
                if (widget.wallet != null)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _archived,
                    onChanged: (value) => setState(() => _archived = value),
                    title: const AppText('archived'),
                    subtitle: const AppText('archived_wallets_are_excluded_from_totals'),
                  ),
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 8),
                  AppText(
                    _error!,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppText('save'),
        ),
      ],
    );
  }

  List<DropdownMenuItem<int>> _dayItems(BuildContext context) {
    return <DropdownMenuItem<int>>[
      for (var day = 1; day <= 28; day++)
        DropdownMenuItem<int>(
          value: day,
          child: Text('$day'),
        ),
      const DropdownMenuItem<int>(
        value: 31,
        child: AppText('end_of_month'),
      ),
    ];
  }
}
