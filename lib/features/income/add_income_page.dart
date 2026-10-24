import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/income_entry.dart';
import '../../domain/models/wallet.dart';
import '../wallets/widgets/wallet_selector.dart';

/// One-off income (sold an item, a single shift, a gift, ...).
///
/// Recurring salary/part-time income is configured in Settings → Income
/// sources. This screen only records a single event and never stores photos.
class AddIncomePage extends ConsumerStatefulWidget {
  const AddIncomePage({super.key});

  @override
  ConsumerState<AddIncomePage> createState() => _AddIncomePageState();
}

class _AddIncomePageState extends ConsumerState<AddIncomePage> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _source = TextEditingController();
  final _note = TextEditingController();
  final _sourceFocus = FocusNode();

  late DateTime _date;
  String? _walletId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
  }

  @override
  void dispose() {
    _amount.dispose();
    _source.dispose();
    _note.dispose();
    _sourceFocus.dispose();
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
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      // Keep the current time of day so several entries stay ordered.
      final now = DateTime.now();
      final receivedAt = DateTime(
        _date.year,
        _date.month,
        _date.day,
        now.hour,
        now.minute,
      );
      final note = _note.text.trim();
      final entry = await ref.read(incomeEntryRepositoryProvider).create(
            IncomeEntry(
              id: '',
              userId: userId,
              amount: parseAmountInput(_amount.text) ?? 0,
              currency: ref.read(defaultCurrencyProvider).code,
              receivedAt: receivedAt,
              source: _source.text.trim(),
              note: note.isEmpty ? null : note,
              walletId: _walletId,
              createdAt: now,
              updatedAt: now,
            ),
          );

      ref.invalidate(incomeEntriesProvider);
      // A monthly payday period can start in the previous month.
      final months = <DateTime>{
        DateTime(now.year, now.month),
        DateTime(entry.receivedAt.year, entry.receivedAt.month),
        DateTime(entry.receivedAt.year, entry.receivedAt.month - 1),
      };
      for (final month in months) {
        ref.invalidate(budgetSummaryProvider(month));
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('income_saved')),
      );
      if (context.canPop()) context.pop(entry);
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
    final currency = ref.watch(defaultCurrencyProvider);
    final suggestions = ref.watch(incomeSourceSuggestionsProvider);
    final wallets =
        ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return Scaffold(
      appBar: AppBar(
        title: const AppText('add_income'),
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
                'income.one_off_help',
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
                        prefixText: '${currency.symbol} ',
                        prefixIcon: const Icon(Icons.payments_outlined),
                      ),
                      validator: (value) {
                        if ((value ?? '').trim().isEmpty) {
                          return context.tr('please_enter_the_total_amount');
                        }
                        if (parseAmountInput(value!) == null) {
                          return context.tr('please_enter_a_number');
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
                      currency: currency.code,
                      excludeCredit: true,
                      label: 'wallet_optional',
                      onChanged: (value) => setState(() => _walletId = value),
                    ),
                    const SizedBox(height: 12),
                    RawAutocomplete<String>(
                      textEditingController: _source,
                      focusNode: _sourceFocus,
                      optionsBuilder: (value) {
                        final query = value.text.trim().toLowerCase();
                        if (query.isEmpty) return suggestions;
                        return suggestions.where(
                          (source) => source.toLowerCase().contains(query),
                        );
                      },
                      onSelected: (value) => _source.text = value,
                      fieldViewBuilder: (
                        context,
                        controller,
                        focusNode,
                        onFieldSubmitted,
                      ) {
                        return TextFormField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: InputDecoration(
                            labelText: context.tr('income_source'),
                            hintText: context.tr('income_source_hint'),
                            prefixIcon: const Icon(Icons.work_outline),
                          ),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? context.tr('please_enter_a_name')
                              : null,
                        );
                      },
                      optionsViewBuilder: (context, onSelected, options) {
                        return Align(
                          alignment: Alignment.topLeft,
                          child: Material(
                            elevation: 6,
                            borderRadius: BorderRadius.circular(10),
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(
                                maxHeight: 220,
                                maxWidth: 360,
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.zero,
                                shrinkWrap: true,
                                itemCount: options.length,
                                itemBuilder: (context, index) {
                                  final option = options.elementAt(index);
                                  return ListTile(
                                    dense: true,
                                    title: AppText(option, translate: false),
                                    onTap: () => onSelected(option),
                                  );
                                },
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    if (suggestions.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      AppText(
                        'income.recent_sources',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: <Widget>[
                          for (final suggestion in suggestions.take(6))
                            ActionChip(
                              label: AppText(
                                suggestion,
                                translate: false,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onPressed: () => setState(() {
                                _source.text = suggestion;
                                _source.selection = TextSelection.collapsed(
                                  offset: suggestion.length,
                                );
                              }),
                            ),
                        ],
                      ),
                    ],
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
                      const SizedBox(height: 12),
                      AppText(
                        _error!,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.check),
                      label: const AppText('save'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
