import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/currencies.dart';
import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/widgets/press_scale.dart';
import '../../data/providers.dart';
import '../../domain/models/category.dart';
import '../../domain/models/payment_method.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../dashboard/analytics_provider.dart';
import '../settings/widgets/currency_picker.dart';

/// Quick entry for expenses that have no receipt (rent, money lent to a
/// friend, bank transfers, ...).
///
/// It writes into the same `receipts` collection with `source = manual`, so
/// the dashboard, budget, pay-cycle periods and analytics pick the payment up
/// automatically — there is no parallel "payments" store.
class AddPaymentPage extends ConsumerStatefulWidget {
  const AddPaymentPage({super.key});

  @override
  ConsumerState<AddPaymentPage> createState() => _AddPaymentPageState();
}

class _AddPaymentPageState extends ConsumerState<AddPaymentPage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  late DateTime _date;
  late Currency _currency;
  String? _categoryId;
  PaymentMethod? _method;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _currency = ref.read(defaultCurrencyProvider);
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
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: context.tr('select_date'),
      confirmText: context.tr('ok'),
      cancelText: context.tr('cancel'),
      locale: Localizations.localeOf(context),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_method == null) return;
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Keep the current time of day so several quick payments stay ordered.
      final now = DateTime.now();
      final purchasedAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
      );
      final note = _note.text.trim();
      final draft = ReceiptDraft(
        purchasedAt: purchasedAt,
        currency: _currency.code,
        totalAmount: parseAmountInput(_amount.text) ?? 0,
        categoryId: _categoryId,
        note: note.isEmpty ? null : note,
        paymentMethod: _method,
        source: ReceiptSource.manual,
      );

      final saved = await ref.read(receiptRepositoryProvider).create(draft);
      ref.invalidate(receiptsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(
        budgetSummaryProvider(
          DateTime(saved.purchasedAt.year, saved.purchasedAt.month),
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('record.payment_saved')),
      );
      if (context.canPop()) context.pop(saved);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存に失敗しました: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];

    return Scaffold(
      appBar: AppBar(
        title: const AppText('add_payment'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              8,
              context.pagePadding,
              32,
            ),
            children: <Widget>[
              AppText(
                'payments.no_receipt_help',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppPalette.card(
                  context,
                  accent: AppPalette.emerald,
                  radius: 18,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextFormField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      style: theme.textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        labelText: context.tr('amount'),
                        prefixText: '${_currency.symbol} ',
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return context.tr('currency.amount_required');
                        }
                        final amount = parseAmountInput(value!);
                        if (amount == null) {
                          return context.tr('please_enter_a_number');
                        }
                        if (amount <= 0) {
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
                        if (picked != null) setState(() => _currency = picked);
                      },
                      icon: const Icon(Icons.currency_exchange_outlined,
                          size: 18),
                      label: Text(
                        '${_currency.code} · '
                        '${_currency.name(context.l10n.language)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.event_outlined, size: 18),
                        label: AppText(
                          formatDateJa(_date),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    AppText(
                      'categories',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        ChoiceChip(
                          label: const AppText('uncategorised'),
                          selected: _categoryId == null,
                          onSelected: (_) =>
                              setState(() => _categoryId = null),
                        ),
                        for (final category in categories)
                          Builder(
                            builder: (context) {
                              final accent = AppPalette.categoryAccent(
                                category.name,
                                fallback: category.colorValue,
                              );
                              final selected = _categoryId == category.id;
                              return ChoiceChip(
                                avatar: Icon(
                                  category.iconData,
                                  size: 16,
                                  color: selected ? Colors.white : accent,
                                ),
                                label: AppText(category.name),
                                selected: selected,
                                selectedColor: accent,
                                labelStyle: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : theme.colorScheme.onSurface,
                                  fontSize: 12.5,
                                ),
                                onSelected: (_) => setState(
                                  () => _categoryId = category.id,
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<PaymentMethod>(
                      initialValue: _method,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: context.tr('payment_method_required'),
                        prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                      ),
                      items: <DropdownMenuItem<PaymentMethod>>[
                        for (final method in PaymentMethod.values)
                          DropdownMenuItem<PaymentMethod>(
                            value: method,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(method.icon, size: 18),
                                const SizedBox(width: 8),
                                ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 220),
                                  child: AppText(
                                    method.label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                      onChanged: (value) => setState(() => _method = value),
                      validator: (value) => value == null
                          ? context.tr('please_choose_a_payment_method')
                          : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _note,
                      minLines: 2,
                      maxLines: 4,
                      textInputAction: TextInputAction.done,
                      decoration: InputDecoration(
                        labelText: context.tr('note_what_it_was_for'),
                        hintText: context.tr('e_g_rent_money_lent_to_a_friend'),
                        prefixIcon: const Icon(Icons.notes_outlined),
                      ),
                    ),
                    if (_error != null) ...<Widget>[
                      const SizedBox(height: 12),
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
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            12,
          ),
          child: PressScale(
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.emerald,
                foregroundColor: AppPalette.backgroundDeep,
                minimumSize: const Size(0, 52),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: const AppText('save_2'),
            ),
          ),
        ),
      ),
    );
  }
}
