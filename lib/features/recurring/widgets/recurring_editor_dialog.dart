import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/localization/currencies.dart';
import '../../../core/localization/localization.dart';
import '../../../core/settings/currency_provider.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/providers.dart';
import '../../../domain/models/category.dart';
import '../../../domain/models/pay_cycle.dart';
import '../../../domain/models/recurring_transaction.dart';
import '../../../domain/models/wallet.dart';
import '../../settings/widgets/currency_picker.dart';
import '../../wallets/widgets/wallet_selector.dart';

class RecurringEditorDialog extends ConsumerStatefulWidget {
  const RecurringEditorDialog({super.key, this.item});

  final RecurringTransaction? item;

  @override
  ConsumerState<RecurringEditorDialog> createState() =>
      _RecurringEditorDialogState();
}

class _RecurringEditorDialogState extends ConsumerState<RecurringEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late final TextEditingController _note;

  late RecurringDirection _direction;
  late Currency _currency;
  late PayCycle _cycle;
  late int _weekday;
  late int _monthlyDay;
  late DateTime _startDate;
  String? _categoryId;
  String? _walletId;
  late bool _active;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final item = widget.item;
    final now = DateTime.now();
    _name = TextEditingController(text: item?.name ?? '');
    _amount = TextEditingController(
      text: item == null ? '' : formatAmountDigits(item.amount),
    );
    _note = TextEditingController(text: item?.note ?? '');
    _direction = item?.direction ?? RecurringDirection.expense;
    _currency =
        currencyByCode(item?.currency) ?? ref.read(defaultCurrencyProvider);
    _cycle = item?.cycle ?? PayCycle.monthly;
    _weekday = item?.weeklyStartWeekday ?? DateTime.monday;
    _monthlyDay = item?.monthlyPayDay ?? 1;
    _startDate = item?.startDate ?? DateTime(now.year, now.month, now.day);
    _categoryId = item?.categoryId;
    _walletId = item?.walletId;
    _active = item?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
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
      final now = DateTime.now();
      final existing = widget.item;
      final item = RecurringTransaction(
        id: existing?.id ?? '',
        userId: userId,
        name: _name.text.trim(),
        direction: _direction,
        amount: parseAmountInput(_amount.text) ?? 0,
        currency: _currency.code,
        categoryId: _direction.isExpense ? _categoryId : null,
        walletId: _walletId,
        cycle: _cycle,
        weeklyStartWeekday: _weekday,
        monthlyPayDay: _monthlyDay,
        startDate: _startDate,
        lastPostedAt: existing?.lastPostedAt,
        active: _active,
        note: _note.text.trim().isEmpty ? null : _note.text.trim(),
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      );
      await ref.read(recurringRepositoryProvider).save(item);
      ref.invalidate(recurringTransactionsProvider);
      if (!mounted) return;
      Navigator.pop(context, item);
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
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return AlertDialog(
      title: AppText(widget.item == null ? 'add_recurring' : 'edit_recurring'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                SegmentedButton<RecurringDirection>(
                  segments: const <ButtonSegment<RecurringDirection>>[
                    ButtonSegment<RecurringDirection>(
                      value: RecurringDirection.expense,
                      label: AppText('expense'),
                    ),
                    ButtonSegment<RecurringDirection>(
                      value: RecurringDirection.income,
                      label: AppText('income'),
                    ),
                  ],
                  selected: <RecurringDirection>{_direction},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _direction = selection.first),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _name,
                  autofocus: widget.item == null,
                  decoration: InputDecoration(
                    labelText: context.tr('recurring_name'),
                    hintText: context.tr('recurring_name_hint'),
                    prefixIcon: const Icon(Icons.repeat),
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
                if (_direction.isExpense) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: _categoryId ?? '',
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: context.tr('category'),
                      prefixIcon: const Icon(Icons.sell_outlined),
                    ),
                    items: <DropdownMenuItem<String>>[
                      const DropdownMenuItem<String>(
                        value: '',
                        child: AppText('uncategorised'),
                      ),
                      for (final category in categories)
                        DropdownMenuItem<String>(
                          value: category.id,
                          child: AppText(category.name),
                        ),
                    ],
                    onChanged: (value) => setState(
                      () => _categoryId =
                          value == null || value.isEmpty ? null : value,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                WalletSelector(
                  wallets: wallets,
                  selectedId: _walletId,
                  currency: _currency.code,
                  excludeCredit: !_direction.isExpense,
                  label: 'wallet_optional',
                  onChanged: (value) => setState(() => _walletId = value),
                ),
                const SizedBox(height: 12),
                SegmentedButton<PayCycle>(
                  segments: const <ButtonSegment<PayCycle>>[
                    ButtonSegment<PayCycle>(
                      value: PayCycle.daily,
                      label: AppText('daily'),
                    ),
                    ButtonSegment<PayCycle>(
                      value: PayCycle.weekly,
                      label: AppText('weekly'),
                    ),
                    ButtonSegment<PayCycle>(
                      value: PayCycle.monthly,
                      label: AppText('monthly'),
                    ),
                  ],
                  selected: <PayCycle>{_cycle},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) =>
                      setState(() => _cycle = selection.first),
                ),
                if (_cycle == PayCycle.weekly) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _weekday,
                    decoration: InputDecoration(
                      labelText: context.tr('payday_weekday'),
                      prefixIcon: const Icon(Icons.event_repeat_outlined),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (var day = DateTime.monday;
                          day <= DateTime.sunday;
                          day++)
                        DropdownMenuItem<int>(
                          value: day,
                          child: AppText(formatWeekdayJa(day)),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _weekday = value);
                    },
                  ),
                ],
                if (_cycle == PayCycle.monthly) ...<Widget>[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _monthlyDay,
                    decoration: InputDecoration(
                      labelText: context.tr('payday'),
                      prefixIcon: const Icon(Icons.pin_outlined),
                    ),
                    items: <DropdownMenuItem<int>>[
                      for (var day = 1; day <= 28; day++)
                        DropdownMenuItem<int>(
                          value: day,
                          child: Text('$day'),
                        ),
                      const DropdownMenuItem<int>(
                        value: PayCycleConfig.endOfMonthPayDay,
                        child: AppText('end_of_month'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) setState(() => _monthlyDay = value);
                    },
                  ),
                ],
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final now = DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _startDate,
                      firstDate: DateTime(now.year - 5),
                      lastDate: DateTime(now.year + 2, 12, 31),
                      helpText: context.tr('start_date'),
                      locale: Localizations.localeOf(context),
                    );
                    if (picked != null) setState(() => _startDate = picked);
                  },
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: AppText(
                    '${context.tr('start_date')}: ${formatDateJa(_startDate)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const AppText('active'),
                ),
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
