import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/settings/exchange_rates_provider.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../data/services/ai_key_store.dart';
import '../../data/services/export_service.dart';
import '../../data/services/full_export_service.dart';
import '../../data/services/ocr/ai_receipt_ocr_service.dart';
import '../../domain/models/exchange_rates.dart';
import '../../domain/models/income_source.dart';
import '../../domain/models/pay_cycle.dart';
import '../../domain/models/wallet.dart';
import '../wallets/widgets/wallet_selector.dart';
import '../../domain/models/receipt_filter.dart';
import 'widgets/currency_picker.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _seedDefaults(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(categoryRepositoryProvider).ensureDefaults();
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('settings.standard_categories_ok')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('失敗しました: $error')),
      );
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref, {
    required bool currentMonthOnly,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final now = DateTime.now();
      final filter = currentMonthOnly
          ? ReceiptFilter(month: DateTime(now.year, now.month))
          : const ReceiptFilter();
      final receipts = await ref.read(receiptRepositoryProvider).fetch(filter);
      if (receipts.isEmpty) {
        messenger
            .showSnackBar(const SnackBar(content: AppText('settings.no_receipts_for_export')));
        return;
      }

      final filename = currentMonthOnly
          ? ExportService.filenameForMonth(now)
          : ExportService.allFilename();
      final result = await ExportService.export(receipts, filename: filename);
      messenger.showSnackBar(
        SnackBar(content: AppText('CSVを書き出しました: $result')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: AppText('書き出しに失敗しました: $error')),
      );
    }
  }

  Future<void> _exportFullCsv(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final wallets = await ref.read(walletsProvider.future);
      final receipts = await ref.read(walletReceiptsProvider.future);
      final sources = await ref.read(incomeSourcesProvider.future);
      final entries = await ref.read(incomeEntriesProvider.future);
      final transfers = await ref.read(walletTransfersProvider.future);
      final adjustments = await ref.read(walletAdjustmentsProvider.future);
      final debts = await ref.read(debtsProvider.future);
      final recurring = await ref.read(recurringTransactionsProvider.future);
      final categories = await ref.read(categoriesProvider.future);
      final csv = FullExportService.buildCsv(
        wallets: wallets,
        receipts: receipts,
        incomeSources: sources,
        incomeEntries: entries,
        transfers: transfers,
        adjustments: adjustments,
        debts: debts,
        recurring: recurring,
        categories: categories,
      );
      final result = await FullExportService.exportCsv(
        csv,
        filename: FullExportService.filename(),
      );
      messenger.showSnackBar(
        SnackBar(content: AppText('CSVを書き出しました: $result')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: AppText('書き出しに失敗しました: $error')),
      );
    }
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('sign_out_2'),
        content: const AppText(
          'your_data_is_stored_in_firebase_and_will_be',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('sign_out'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final language = ref.watch(languageProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('settings'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          context.pagePadding,
          8,
          context.pagePadding,
          40,
        ),
        children: <Widget>[
          _Card(
            title: 'account',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.14),
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: AppText(user?.email ?? 'settings.not_signed_in'),
                subtitle: AppText(
                  'firebase_account_receipts_items_and_budgets',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: IconButton(
                  tooltip: context.tr('copy_user_id'),
                  onPressed: user == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: user.id),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: AppText('settings.user_id_copied')),
                          );
                        },
                  icon: const Icon(Icons.copy_all_outlined, size: 18),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _signOut(context, ref),
                  icon: const Icon(Icons.logout),
                  label: const AppText('sign_out'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _AiKeyCard(),
          const SizedBox(height: 14),
          const _IncomeSourcesCard(),
          const SizedBox(height: 14),
          const _CurrencyCard(),
          const SizedBox(height: 14),
          const _WalletsCard(),
          const SizedBox(height: 14),
          const _DebtsCard(),
          const SizedBox(height: 14),
          const _RecurringCard(),
          const SizedBox(height: 14),
          const _ExchangeRatesCard(),
          const SizedBox(height: 14),
          _Card(
            title: 'appearance',
            children: <Widget>[
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ThemeMode>(
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: AppText('auto'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: AppText('light'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: AppText('dark'),
                      icon: Icon(Icons.dark_mode_outlined, size: 18),
                    ),
                  ],
                  selected: <ThemeMode>{themeMode},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => ref
                      .read(themeModeProvider.notifier)
                      .setMode(selection.first),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            title: context.tr('language'),
            children: <Widget>[
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<AppLanguage>(
                  segments: <ButtonSegment<AppLanguage>>[
                    for (final option in AppLanguage.values)
                      ButtonSegment<AppLanguage>(
                        value: option,
                        label: AppText(
                          option.nativeLabel,
                          translate: false,
                          textDirection: option.isRtl
                              ? TextDirection.rtl
                              : TextDirection.ltr,
                        ),
                      ),
                  ],
                  selected: <AppLanguage>{language},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => ref
                      .read(languageProvider.notifier)
                      .setLanguage(selection.first),
                ),
              ),
              const SizedBox(height: 8),
              AppText(
                'settings.language_help',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'data',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const AppText('recreate_default_categories'),
                subtitle: const AppText('food_dining_daily_goods_utilities_transport'),
                onTap: () => _seedDefaults(context, ref),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.file_download_outlined),
                title: const AppText('settings.export_month_csv'),
                subtitle: const AppText('utf_8_csv_for_excel_numbers'),
                onTap: () => _exportCsv(context, ref, currentMonthOnly: true),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_view_outlined),
                title: const AppText('settings.export_all_csv'),
                subtitle: const AppText('combine_all_receipts_into_one_file'),
                onTap: () => _exportCsv(context, ref, currentMonthOnly: false),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.dataset_outlined),
                title: const AppText('settings.export_full_csv'),
                subtitle: const AppText('settings.export_full_csv_help'),
                onTap: () => _exportFullCsv(context, ref),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _Card(
            title: 'about_this_app',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.document_scanner_outlined),
                title: AppText('scanning_engine'),
                subtitle: AppText(
                  'settings.scan_engine_value',
                ),
              ),
              Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: AppText('version'),
                subtitle: AppText('1.0.0 (Flutter / Riverpod / Firebase)'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Recurring income sources. Exactly one source anchors the budget period.
class _IncomeSourcesCard extends ConsumerWidget {
  const _IncomeSourcesCard();

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref, {
    IncomeSource? source,
    required List<IncomeSource> all,
  }) async {
    final currency = ref.read(defaultCurrencyProvider);
    final wallets =
        ref.read(walletsProvider).valueOrNull ?? const <Wallet>[];
    final result = await showDialog<IncomeSource>(
      context: context,
      builder: (context) => _IncomeSourceEditor(
        source: source,
        currencyCode: currency.code,
        currencySymbol: currency.symbol,
        wallets: wallets,
      ),
    );
    if (result == null) return;
    final toSave = all.isEmpty
        ? result.copyWith(definesBudgetPeriod: true)
        : result;
    try {
      await ref.read(incomeSourcesProvider.notifier).save(toSave);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('income_source_saved')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('could_not_save: $error')),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    IncomeSource source,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('delete_income_source'),
        content: const AppText('delete_income_source_confirm'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(incomeSourcesProvider.notifier).delete(source.id);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('income_source_deleted')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('could_not_save: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final sourcesAsync = ref.watch(incomeSourcesProvider);
    final controller = ref.read(incomeSourcesProvider.notifier);
    final now = DateTime.now();
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return _Card(
      title: 'income_sources',
      children: <Widget>[
        AppText('income_sources_help', style: labelStyle),
        const SizedBox(height: 8),
        sourcesAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (error, _) => AppText(
            'could_not_load_data: $error',
            style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
          ),
          data: (sources) {
            final monthly = sources
                .where((source) => source.active)
                .fold<double>(0, (sum, source) {
              return sum + source.monthlyEquivalent(now).toDouble();
            });
            final defining = budgetDefiningSource(sources);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                AppText(
                  'income.monthly_equivalent_total',
                  params: <String, Object?>{
                    'amount': formatMoney(
                      monthly,
                      currency: defining?.currency ??
                          ref.read(defaultCurrencyProvider).code,
                    ),
                  },
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (sources.isEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  AppText('no_income_sources', style: labelStyle),
                ],
                const SizedBox(height: 8),
                for (final source in sources)
                  _IncomeSourceTile(
                    source: source,
                    onDefine: () => controller.setDefinesBudgetPeriod(source.id),
                    onActive: (active) =>
                        controller.setActive(source.id, active),
                    onEdit: () => _edit(
                      context,
                      ref,
                      source: source,
                      all: sources,
                    ),
                    onDelete: () => _delete(context, ref, source),
                  ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  onPressed: () => _edit(context, ref, all: sources),
                  icon: const Icon(Icons.add, size: 18),
                  label: const AppText('add_income_source'),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _IncomeSourceTile extends StatelessWidget {
  const _IncomeSourceTile({
    required this.source,
    required this.onDefine,
    required this.onActive,
    required this.onEdit,
    required this.onDelete,
  });

  final IncomeSource source;
  final VoidCallback onDefine;
  final ValueChanged<bool> onActive;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  String _paydayLabel(BuildContext context) => switch (source.cycle) {
        PayCycle.daily => context.tr('income.every_day'),
        PayCycle.weekly => context.tr(
            'income.every_week_on',
            params: <String, Object?>{
              'weekday': formatWeekdayJa(source.weeklyStartWeekday),
            },
          ),
        PayCycle.monthly => source.monthlyPayDay >=
                PayCycleConfig.endOfMonthPayDay
            ? context.tr('income.every_month_end')
            : context.tr(
                'income.every_month_on',
                params: <String, Object?>{'day': source.monthlyPayDay},
              ),
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionColor = theme.colorScheme.onSurfaceVariant;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.38),
        borderRadius: BorderRadius.circular(12),
        border: source.definesBudgetPeriod
            ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.6))
            : null,
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: context.tr('defines_budget_period'),
            icon: Icon(
              source.definesBudgetPeriod ? Icons.star : Icons.star_border,
              color: source.definesBudgetPeriod
                  ? theme.colorScheme.primary
                  : actionColor,
              size: 20,
            ),
            onPressed: onDefine,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  source.name,
                  translate: false,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                AppText(
                  'income.source_summary',
                  params: <String, Object?>{
                    'amount': formatMoney(
                      source.amountPerCycle,
                      currency: source.currency,
                    ),
                    'payday': _paydayLabel(context),
                  },
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (!source.active)
                  AppText(
                    'inactive',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          Switch(
            value: source.active,
            onChanged: onActive,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'edit',
                child: AppText('edit'),
              ),
              const PopupMenuItem<String>(
                value: 'delete',
                child: AppText('delete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IncomeSourceEditor extends StatefulWidget {
  const _IncomeSourceEditor({
    this.source,
    required this.currencyCode,
    required this.currencySymbol,
    required this.wallets,
  });

  final IncomeSource? source;
  final String currencyCode;
  final String currencySymbol;
  final List<Wallet> wallets;

  @override
  State<_IncomeSourceEditor> createState() => _IncomeSourceEditorState();
}

class _IncomeSourceEditorState extends State<_IncomeSourceEditor> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _amount;
  late PayCycle _cycle;
  late int _weekday;
  late int _monthlyDay;
  late bool _active;
  late bool _defines;
  String? _walletId;

  @override
  void initState() {
    super.initState();
    final source = widget.source;
    _name = TextEditingController(text: source?.name ?? '');
    _amount = TextEditingController(
      text: source == null
          ? ''
          : formatAmountDigits(source.amountPerCycle),
    );
    _cycle = source?.cycle ?? PayCycle.monthly;
    _weekday = source?.weeklyStartWeekday ?? DateTime.monday;
    _monthlyDay = source?.monthlyPayDay ?? 1;
    _active = source?.active ?? true;
    _defines = source?.definesBudgetPeriod ?? false;
    _walletId = source?.walletId;
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final now = DateTime.now();
    final existing = widget.source;
    Navigator.pop(
      context,
      IncomeSource(
        id: existing?.id ?? now.microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        cycle: _cycle,
        weeklyStartWeekday: _weekday,
        monthlyPayDay: _monthlyDay,
        amountPerCycle: parseAmountInput(_amount.text) ?? 0,
        currency: existing?.currency ?? widget.currencyCode,
        walletId: _walletId,
        active: _active,
        definesBudgetPeriod: _defines,
        createdAt: existing?.createdAt ?? now,
        updatedAt: now,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: AppText(
        widget.source == null ? 'add_income_source' : 'edit_income_source',
      ),
      content: SizedBox(
        width: 380,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TextFormField(
                  controller: _name,
                  autofocus: widget.source == null,
                  decoration: InputDecoration(
                    labelText: context.tr('income_source_name'),
                    hintText: context.tr('income_source_name_hint'),
                    prefixIcon: const Icon(Icons.label_outline),
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
                    labelText: context.tr('amount_per_cycle'),
                    prefixText: '${widget.currencySymbol} ',
                    prefixIcon: const Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    if ((value ?? '').trim().isEmpty) return null;
                    if (parseAmountInput(value!) == null) {
                      return context.tr('please_enter_a_number');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                WalletSelector(
                  wallets: widget.wallets,
                  selectedId: _walletId,
                  currency: widget.source?.currency ?? widget.currencyCode,
                  excludeCredit: true,
                  label: 'wallet_destination_optional',
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
                      if (value != null) {
                        setState(() => _monthlyDay = value);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const AppText('active'),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _defines,
                  onChanged: (value) =>
                      setState(() => _defines = value ?? false),
                  title: const AppText('defines_budget_period'),
                  subtitle: AppText(
                    'defines_budget_period_help',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
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
          onPressed: _submit,
          child: const AppText('save'),
        ),
      ],
    );
  }
}

/// Default currency for new receipts and budget amounts.
class _CurrencyCard extends ConsumerWidget {
  const _CurrencyCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currency = ref.watch(defaultCurrencyProvider);
    final language = context.l10n.language;

    return _Card(
      title: 'currency.title',
      children: <Widget>[
        AppText(
          'currency.help',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
            child: Text(
              currency.symbol,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          title: Text(currency.name(language)),
          subtitle: Text(
            '${currency.code} · ${currency.symbol}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () async {
            final picked = await showCurrencyPicker(
              context,
              selected: currency,
            );
            if (picked == null) return;
            await ref
                .read(defaultCurrencyProvider.notifier)
                .setCurrency(picked);
          },
        ),
      ],
    );
  }
}

/// Wallet list entry point.
class _WalletsCard extends ConsumerWidget {
  const _WalletsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final wallets = ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];
    final active = wallets.where((wallet) => !wallet.archived).length;
    return _Card(
      title: 'wallets',
      children: <Widget>[
        AppText(
          'wallet.help',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_balance_wallet_outlined),
          title: AppText(
            'wallet.active_count',
            params: <String, Object?>{'count': active},
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/wallets'),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/wallets'),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const AppText('manage_wallets'),
          ),
        ),
      ],
    );
  }
}

/// Debt totals + entry point.
class _DebtsCard extends ConsumerWidget {
  const _DebtsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final totals = ref.watch(debtTotalsProvider).valueOrNull;
    final base = ref.watch(defaultCurrencyProvider);
    return _Card(
      title: 'debts',
      children: <Widget>[
        AppText(
          'debt.help',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.call_received_outlined),
          title: const AppText('owed_to_me'),
          trailing: AppText(
            formatMoney(totals?.owedToMe ?? 0, currency: base.code),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.call_made_outlined),
          title: const AppText('i_owe'),
          trailing: AppText(
            formatMoney(totals?.iOwe ?? 0, currency: base.code),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/debts'),
            icon: const Icon(Icons.handshake_outlined, size: 18),
            label: const AppText('manage_debts'),
          ),
        ),
      ],
    );
  }
}

/// Recurring transaction entry point.
class _RecurringCard extends ConsumerWidget {
  const _RecurringCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final items =
        ref.watch(recurringTransactionsProvider).valueOrNull ?? const [];
    final active = items.where((item) => item.active).length;
    return _Card(
      title: 'recurring',
      children: <Widget>[
        AppText(
          'recurring.help',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.repeat),
          title: AppText(
            'recurring.active_count',
            params: <String, Object?>{'count': active},
          ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/recurring'),
        ),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => context.push('/recurring'),
            icon: const Icon(Icons.repeat, size: 18),
            label: const AppText('manage_recurring'),
          ),
        ),
      ],
    );
  }
}

/// FX rate status + manual override entry point.
class _ExchangeRatesCard extends ConsumerWidget {
  const _ExchangeRatesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncState = ref.watch(exchangeRatesProvider);
    final base = ref.watch(defaultCurrencyProvider);
    final state = asyncState.valueOrNull;
    final snapshot = state?.snapshot;
    final source = snapshot == null
        ? null
        : switch (snapshot.source) {
            FxSource.frankfurter => 'fx.source_frankfurter',
            FxSource.erApi => 'fx.source_er_api',
            FxSource.none => 'fx.source_none',
          };

    return _Card(
      title: 'exchange_rates',
      children: <Widget>[
        AppText(
          'fx.help',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.currency_exchange_outlined),
          title: AppText(
            'fx.base_currency',
            params: <String, Object?>{'code': base.code},
          ),
          subtitle: snapshot == null
              ? null
              : AppText(
                  'fx.rates_as_of',
                  params: <String, Object?>{
                    'date': formatDateJa(snapshot.fetchedAt),
                  },
                ),
        ),
        if (source != null) AppText(source),
        if (snapshot != null && snapshot.stale)
          AppText(
            'fx.stale_rates',
            style: TextStyle(fontSize: 11, color: theme.colorScheme.error),
          ),
        if (snapshot != null && state!.overrides.isNotEmpty)
          AppText(
            'fx.manual_overrides_count',
            params: <String, Object?>{'count': state.overrides.length},
            style: theme.textTheme.labelSmall,
          ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => context.push('/rates'),
                icon: const Icon(Icons.tune_outlined, size: 18),
                label: const AppText('fx.manage_rates'),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.tr('fx.refresh'),
              onPressed: () =>
                  ref.read(exchangeRatesProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ],
    );
  }
}

/// Bring-your-own Gemini key. Stored only in this browser's localStorage.
class _AiKeyCard extends StatefulWidget {
  const _AiKeyCard();

  @override
  State<_AiKeyCard> createState() => _AiKeyCardState();
}

class _AiKeyCardState extends State<_AiKeyCard> {
  final TextEditingController _controller = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  bool _saved = false;
  bool _statusOk = false;
  String? _status;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await AiKeyStore.read();
    if (!mounted) return;
    setState(() {
      _saved = saved != null;
      if (saved != null) _controller.text = saved;
    });
  }

  Future<void> _save() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() {
        _status = 'settings.ai_key_enter';
        _statusOk = false;
      });
      return;
    }
    setState(() => _busy = true);
    await AiKeyStore.save(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = true;
      _status = 'settings.ai_key_saved';
      _statusOk = true;
    });
  }

  Future<void> _clear() async {
    setState(() => _busy = true);
    await AiKeyStore.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _saved = false;
      _controller.clear();
      _status = 'settings.ai_key_cleared';
      _statusOk = true;
    });
  }

  Future<void> _test() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() {
        _status = 'settings.ai_key_test_enter';
        _statusOk = false;
      });
      return;
    }
    setState(() => _busy = true);
    final result = await AiReceiptOcrService().testKey(key);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _statusOk = result.ok;
      _status =
          result.ok ? 'settings.ai_key_valid' : _testFailureLabel(result.kind);
    });
  }

  String _testFailureLabel(AiReceiptFailureKind? kind) {
    return switch (kind) {
      AiReceiptFailureKind.configuration => 'settings.ai_status_invalid',
      AiReceiptFailureKind.quota => 'settings.ai_status_quota',
      AiReceiptFailureKind.dailyLimit => 'settings.ai_status_daily',
      AiReceiptFailureKind.unavailable => 'settings.ai_status_network',
      AiReceiptFailureKind.missingKey => 'settings.ai_status_missing',
      _ => 'settings.ai_status_unknown',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _saved ? 'settings.ai_source_saved' : 'settings.ai_source_unset';

    return _Card(
      title: 'settings.ai_key_optional_title',
      children: <Widget>[
        AppText(
          '任意です。未設定の場合はアプリの共有バックエンド経由で AI 抽出を利用します'
          '（1日あたりの回数制限あり）。自分のキーを保存すると、このブラウザから '
          'Google の Gemini API へ直接リクエストします。キーはこのブラウザの '
          'localStorage にのみ保存され、Google 以外には送信されません。'
          '現在: $source',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _controller,
          obscureText: _obscure,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: 'settings.ai_key_label',
            hintText: 'settings.ai_key_hint',
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'appearance' : 'settings.hide',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            FilledButton.icon(
              onPressed: _busy ? null : _save,
              icon: const Icon(Icons.save_outlined, size: 18),
              label: const AppText('save'),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _test,
              icon: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.network_check, size: 18),
              label: const AppText('settings.test_key'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const AppText('clear'),
            ),
          ],
        ),
        if (_status != null) ...<Widget>[
          const SizedBox(height: 8),
          AppText(
            _status!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: _statusOk
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          AppText(
            title,
            style: theme.textTheme.labelLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}
