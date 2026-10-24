import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/currencies.dart';
import '../../../core/localization/localization.dart';
import '../../../core/settings/currency_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/wallet.dart';
import '../../settings/widgets/currency_picker.dart';
import '../../wallets/widgets/wallet_selector.dart';

class DebtEditorDialog extends ConsumerStatefulWidget {
  const DebtEditorDialog({super.key, this.debt});

  final Debt? debt;

  @override
  ConsumerState<DebtEditorDialog> createState() => _DebtEditorDialogState();
}

class _DebtEditorDialogState extends ConsumerState<DebtEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _counterparty;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late DebtDirection _direction;
  late Currency _currency;
  late DateTime _date;
  DateTime? _dueDate;
  String? _walletId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final debt = widget.debt;
    final now = DateTime.now();
    _counterparty = TextEditingController(text: debt?.counterparty ?? '');
    _amount = TextEditingController(
      text: debt == null ? '' : formatAmountDigits(debt.amount),
    );
    _note = TextEditingController(text: debt?.note ?? '');
    _direction = debt?.direction ?? DebtDirection.iLent;
    _currency = currencyByCode(debt?.currency) ?? ref.read(defaultCurrencyProvider);
    _date = debt?.date ?? DateTime(now.year, now.month, now.day);
    _dueDate = debt?.dueDate;
    _walletId = debt?.walletId;
  }

  @override
  void dispose() {
    _counterparty.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool due}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: due ? (_dueDate ?? _date) : _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: context.tr(due ? 'select_due_date' : 'select_date'),
      locale: Localizations.localeOf(context),
    );
    if (picked == null) return;
    setState(() {
      if (due) {
        _dueDate = picked;
      } else {
        _date = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final existing = widget.debt;
      final now = DateTime.now();
      final debt = Debt(
        id: existing?.id ?? '',
        userId: userId,
        direction: _direction,
        counterparty: _counterparty.text.trim(),
        amount: parseAmountInput(_amount.text) ?? 0,
        currency: _currency.code,
        date: _date,
        dueDate: _dueDate,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        walletId: _walletId,
        repayments: existing?.repayments ?? const <DebtRepayment>[],
        status: existing?.status ?? DebtStatus.open,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(debtRepositoryProvider).save(debt);
      ref.invalidate(debtsProvider);
      if (!mounted) return;
      Navigator.pop(context, debt);
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
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return AlertDialog(
      title: AppText(widget.debt == null ? 'add_debt' : 'edit_debt'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<DebtDirection>(
                  segments: const <ButtonSegment<DebtDirection>>[
                    ButtonSegment<DebtDirection>(
                      value: DebtDirection.iLent,
                      label: AppText('i_lent'),
                    ),
                    ButtonSegment<DebtDirection>(
                      value: DebtDirection.iBorrowed,
                      label: AppText('i_borrowed'),
                    ),
                  ],
                  selected: <DebtDirection>{_direction},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _direction = selection.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _counterparty,
                  autofocus: widget.debt == null,
                  decoration: InputDecoration(
                    labelText: context.tr('counterparty'),
                    hintText: context.tr('counterparty_hint'),
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? context.tr('please_enter_a_name')
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('amount'),
                    prefixText: '${_currency.symbol} ',
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
                        _walletId = null;
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
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(due: false),
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: AppText(
                          formatDateJa(_date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(due: true),
                        icon: const Icon(Icons.event_available_outlined,
                            size: 18),
                        label: AppText(
                          _dueDate == null
                              ? 'set_due_date_optional'
                              : formatDateShortJa(_dueDate!),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (_dueDate != null)
                      IconButton(
                        tooltip: context.tr('clear_due_date'),
                        onPressed: () => setState(() => _dueDate = null),
                        icon: const Icon(Icons.close, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                WalletSelector(
                  wallets: wallets,
                  selectedId: _walletId,
                  currency: _currency.code,
                  label: 'debt_wallet_optional',
                  onChanged: (value) => setState(() => _walletId = value),
                ),
                const SizedBox(height: 4),
                AppText(
                  'debt_wallet_help',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
}
