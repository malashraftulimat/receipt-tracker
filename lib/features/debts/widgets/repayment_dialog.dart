import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/localization.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/debt.dart';
import '../../../domain/models/wallet.dart';
import '../../wallets/widgets/wallet_selector.dart';

class RepaymentDialog extends ConsumerStatefulWidget {
  const RepaymentDialog({super.key, required this.debt});

  final Debt debt;

  @override
  ConsumerState<RepaymentDialog> createState() => _RepaymentDialogState();
}

class _RepaymentDialogState extends ConsumerState<RepaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  final _note = TextEditingController();
  late DateTime _date;
  String? _walletId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _amount = TextEditingController(
      text: formatAmountDigits(widget.debt.remaining),
    );
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 10, 12, 31),
      helpText: context.tr('select_date'),
      locale: Localizations.localeOf(context),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repayment = DebtRepayment(
        id: 'repayment_${now.microsecondsSinceEpoch}',
        amount: parseAmountInput(_amount.text) ?? 0,
        date: _date,
        walletId: _walletId,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );
      final updated = widget.debt.withRepayment(repayment);
      await ref.read(debtRepositoryProvider).save(updated);
      ref.invalidate(debtsProvider);
      if (!mounted) return;
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
    final debt = widget.debt;
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return AlertDialog(
      title: const AppText('add_repayment'),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
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
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amount,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: <TextInputFormatter>[
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.tr('amount'),
                    prefixText: '${debt.currency} ',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    final amount = parseAmountInput(value ?? '');
                    if (amount == null || amount <= 0) {
                      return context.tr('enter_an_amount_greater_than_0');
                    }
                    if (amount > debt.remaining + 0.011) {
                      return context.tr('repayment_cannot_exceed_remaining');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: AppText(formatDateJa(_date)),
                ),
                const SizedBox(height: 12),
                WalletSelector(
                  wallets: wallets,
                  selectedId: _walletId,
                  currency: debt.currency,
                  label: 'repayment_wallet_optional',
                  onChanged: (value) => setState(() => _walletId = value),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _note,
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
          child: const AppText('save'),
        ),
      ],
    );
  }
}
