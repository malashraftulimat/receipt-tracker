import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/settings/currency_provider.dart';
import '../../core/settings/pay_cycle_provider.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../data/services/ai_key_store.dart';
import '../../data/services/export_service.dart';
import '../../data/services/ocr/ai_receipt_ocr_service.dart';
import '../../domain/models/pay_cycle.dart';
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
          const _PayCycleCard(),
          const SizedBox(height: 14),
          const _CurrencyCard(),
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

/// Daily / weekly / monthly salary — paces the budget on the dashboard.
class _PayCycleCard extends ConsumerWidget {
  const _PayCycleCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final config = ref.watch(payCycleProvider);
    final controller = ref.read(payCycleProvider.notifier);
    final now = DateTime.now();
    final period = config.periodFor(now);
    final labelStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return _Card(
      title: 'how_you_get_paid',
      children: <Widget>[
        AppText(
          'settings.pay_cycle_help',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<PayCycle>(
            segments: const <ButtonSegment<PayCycle>>[
              ButtonSegment<PayCycle>(
                value: PayCycle.daily,
                label: AppText('daily'),
                icon: Icon(Icons.today_outlined, size: 18),
              ),
              ButtonSegment<PayCycle>(
                value: PayCycle.weekly,
                label: AppText('weekly'),
                icon: Icon(Icons.view_week_outlined, size: 18),
              ),
              ButtonSegment<PayCycle>(
                value: PayCycle.monthly,
                label: AppText('monthly'),
                icon: Icon(Icons.calendar_month_outlined, size: 18),
              ),
            ],
            selected: <PayCycle>{config.cycle},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                controller.setCycle(selection.first),
          ),
        ),
        if (config.cycle == PayCycle.weekly) ...<Widget>[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: config.weeklyStartWeekday,
            decoration: InputDecoration(
              labelText: context.tr('payday_weekday'),
              prefixIcon: const Icon(Icons.event_repeat_outlined),
            ),
            items: <DropdownMenuItem<int>>[
              for (var day = DateTime.monday; day <= DateTime.sunday; day++)
                DropdownMenuItem<int>(
                  value: day,
                  child: AppText(formatWeekdayJa(day)),
                ),
            ],
            onChanged: (value) {
              if (value != null) controller.setWeeklyStartWeekday(value);
            },
          ),
        ],
        if (config.cycle == PayCycle.monthly) ...<Widget>[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: config.monthlyPayDay,
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
              if (value != null) controller.setMonthlyPayDay(value);
            },
          ),
        ],
        const SizedBox(height: 10),
        AppText(
          '今回の対象期間: '
          '${formatRangeJa(period.start, period.endInclusive)}'
          '（あと${period.daysRemainingOn(now)}日）',
          style: labelStyle,
        ),
        if (config.cycle != PayCycle.daily) ...<Widget>[
          const SizedBox(height: 2),
          AppText(
            '次の支給日: ${formatDateShortJa(period.end)}',
            style: labelStyle,
          ),
        ],
        const SizedBox(height: 2),
        AppText(
          'settings.salary_monthly_help',
          style: labelStyle,
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
