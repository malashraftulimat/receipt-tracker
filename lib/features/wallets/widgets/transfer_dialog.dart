import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/wallet.dart';
import '../../../domain/models/wallet_transfer.dart';

class TransferDialog extends ConsumerStatefulWidget {
  const TransferDialog({
    super.key,
    required this.wallets,
    this.initialFromId,
    this.initialToId,
  });

  final List<Wallet> wallets;
  final String? initialFromId;
  final String? initialToId;

  @override
  ConsumerState<TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends ConsumerState<TransferDialog> {
  final _formKey = GlobalKey<FormState>();
  final _fromAmount = TextEditingController();
  final _toAmount = TextEditingController();
  final _note = TextEditingController();

  late String? _fromId;
  late String? _toId;
  late DateTime _date;
  bool _saving = false;
  String? _error;

  List<Wallet> get _wallets =>
      widget.wallets.where((wallet) => !wallet.archived).toList(growable: false);

  Wallet? get _from => _find(_fromId);
  Wallet? get _to => _find(_toId);

  Wallet? _find(String? id) {
    if (id == null) return null;
    for (final wallet in _wallets) {
      if (wallet.id == id) return wallet;
    }
    return null;
  }

  bool get _sameCurrency =>
      _from != null && _to != null && _from!.currency == _to!.currency;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _fromId = widget.initialFromId;
    _toId = widget.initialToId;
    if (_fromId == null || _find(_fromId) == null) {
      for (final wallet in _wallets) {
        if (wallet.id != _toId) {
          _fromId = wallet.id;
          break;
        }
      }
    }
    if (_toId == null || _find(_toId) == null || _toId == _fromId) {
      _toId = null;
      for (final wallet in _wallets) {
        if (wallet.id != _fromId) {
          _toId = wallet.id;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _fromAmount.dispose();
    _toAmount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: context.tr('select_date'),
      locale: Localizations.localeOf(context),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final from = _from;
    final to = _to;
    if (from == null || to == null || from.id == to.id) return;
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final fromAmount = parseAmountInput(_fromAmount.text) ?? 0;
      final toAmount = _sameCurrency
          ? fromAmount
          : (parseAmountInput(_toAmount.text) ?? 0);
      await ref.read(walletTransferRepositoryProvider).create(
            WalletTransfer(
              id: '',
              userId: userId,
              fromWalletId: from.id,
              toWalletId: to.id,
              fromAmount: fromAmount,
              toAmount: toAmount,
              occurredAt: DateTime(
                _date.year,
                _date.month,
                _date.day,
                now.hour,
                now.minute,
              ),
              note: _note.text.trim().isEmpty ? null : _note.text.trim(),
              createdAt: now,
              updatedAt: now,
            ),
          );
      ref.invalidate(walletTransfersProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('transfer_saved')),
      );
      Navigator.pop(context, true);
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
    final wallets = _wallets;
    final from = _from;
    final to = _to;

    return AlertDialog(
      title: const AppText('transfer'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (wallets.length < 2)
                  const AppText('add_two_wallets_to_transfer')
                else ...<Widget>[
                  DropdownButtonFormField<String>(
                    initialValue: _fromId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('from_wallet'),
                      prefixIcon: const Icon(Icons.upload_outlined),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final wallet in wallets)
                        DropdownMenuItem<String>(
                          value: wallet.id,
                          child: AppText(
                            '${wallet.name} (${wallet.currency})',
                            translate: false,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      _fromId = value;
                      if (_fromId == _toId) _toId = null;
                    }),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _toId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('to_wallet'),
                      prefixIcon: const Icon(Icons.download_outlined),
                    ),
                    items: <DropdownMenuItem<String>>[
                      for (final wallet in wallets)
                        if (wallet.id != _fromId)
                          DropdownMenuItem<String>(
                            value: wallet.id,
                            child: AppText(
                              '${wallet.name} (${wallet.currency})',
                              translate: false,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                    ],
                    onChanged: (value) => setState(() => _toId = value),
                    validator: (value) => value == null
                        ? context.tr('please_choose_a_wallet')
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _fromAmount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr(
                        _sameCurrency ? 'amount' : 'amount_sent',
                      ),
                      prefixText: from == null ? null : '${from.currency} ',
                      prefixIcon: const Icon(Icons.payments_outlined),
                    ),
                    validator: (value) {
                      final amount = parseAmountInput(value ?? '');
                      if (amount == null || amount <= 0) {
                        return context.tr('enter_an_amount_greater_than_0');
                      }
                      return null;
                    },
                  ),
                  if (!_sameCurrency) ...<Widget>[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _toAmount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      decoration: InputDecoration(
                        labelText: context.tr('amount_received'),
                        helperText: context.tr(
                          'different_currencies_both_amounts_are_required',
                        ),
                        prefixText: to == null ? null : '${to.currency} ',
                        prefixIcon: const Icon(Icons.download_outlined),
                      ),
                      validator: (value) {
                        final amount = parseAmountInput(value ?? '');
                        if (amount == null || amount <= 0) {
                          return context.tr('enter_an_amount_greater_than_0');
                        }
                        return null;
                      },
                    ),
                  ],
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: AppText(formatDateJa(_date)),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: context.tr('note'),
                      prefixIcon: const Icon(Icons.notes_outlined),
                    ),
                  ),
                  if (to?.isCredit == true) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      context.tr('credit_card_repayment_help'),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
                if (_error != null) ...<Widget>[
                  const SizedBox(height: 10),
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
          onPressed: wallets.length < 2 || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const AppText('transfer'),
        ),
      ],
    );
  }
}
