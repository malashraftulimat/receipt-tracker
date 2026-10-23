import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
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

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _seedDefaults(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(categoryRepositoryProvider).ensureDefaults();
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('標準カテゴリを確認しました')),
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
            .showSnackBar(const SnackBar(content: AppText('対象のレシートがありません')));
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
        title: const AppText('ログアウトしますか？'),
        content: const AppText(
          'データは Firebase に保存されています。次回ログインで復元されます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('ログアウト'),
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
        title: const AppText('設定'),
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
            title: 'アカウント',
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
                title: AppText(user?.email ?? '未ログイン'),
                subtitle: AppText(
                  'Firebase アカウント（レシート・明細・予算はすべての端末で同期されます）',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: IconButton(
                  tooltip: context.tr('ユーザーIDをコピー'),
                  onPressed: user == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: user.id),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: AppText('ユーザーIDをコピーしました')),
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
                  label: const AppText('ログアウト'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _AiKeyCard(),
          const SizedBox(height: 14),
          const _PayCycleCard(),
          const SizedBox(height: 14),
          _Card(
            title: '表示',
            children: <Widget>[
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SegmentedButton<ThemeMode>(
                  segments: const <ButtonSegment<ThemeMode>>[
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.system,
                      label: AppText('自動'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: AppText('ライト'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: AppText('ダーク'),
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
            title: context.tr('言語 / Language'),
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
                'ブラウザや端末の言語を自動で判定します。'
                'ここで選んだ言語は保存され、次回以降も優先されます。',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'データ',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const AppText('標準カテゴリを再作成'),
                subtitle: const AppText('食費・外食・日用品・光熱費・交通費・娯楽など'),
                onTap: () => _seedDefaults(context, ref),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.file_download_outlined),
                title: const AppText('CSVエクスポート（今月）'),
                subtitle: const AppText('Excel / Numbers で開ける UTF-8 CSV'),
                onTap: () => _exportCsv(context, ref, currentMonthOnly: true),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_view_outlined),
                title: const AppText('CSVエクスポート（全期間）'),
                subtitle: const AppText('すべてのレシートを1ファイルにまとめます'),
                onTap: () => _exportCsv(context, ref, currentMonthOnly: false),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const _Card(
            title: 'このアプリについて',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.document_scanner_outlined),
                title: AppText('スキャンエンジン'),
                subtitle: AppText(
                  '1Dバーコード: JAN-13 / EAN-8 / Code 128 / Code 39 / ITF\n'
                  'AI抽出: Gemini Flash（共有バックエンド / 自分のキーでも利用可）\n'
                  'フォールバックOCR: ML Kit（iOS・Android）/ Tesseract.js（Web）',
                ),
              ),
              Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: AppText('バージョン'),
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
      title: '給与の受け取り方',
      children: <Widget>[
        AppText(
          '給与が入るタイミングを選ぶと、ダッシュボードと予算ページが'
          '「次の支給日まであといくら使えるか」で表示されます。',
          style: labelStyle,
        ),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<PayCycle>(
            segments: const <ButtonSegment<PayCycle>>[
              ButtonSegment<PayCycle>(
                value: PayCycle.daily,
                label: AppText('日払い'),
                icon: Icon(Icons.today_outlined, size: 18),
              ),
              ButtonSegment<PayCycle>(
                value: PayCycle.weekly,
                label: AppText('週払い'),
                icon: Icon(Icons.view_week_outlined, size: 18),
              ),
              ButtonSegment<PayCycle>(
                value: PayCycle.monthly,
                label: AppText('月払い'),
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
              labelText: context.tr('支給曜日'),
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
              labelText: context.tr('支給日'),
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
                child: AppText('月末'),
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
          '貯蓄目標と固定費は月額のまま保存されます。'
          '日払い・週払いでも金額の入力を月に換算する必要はありません。',
          style: labelStyle,
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
        _status = 'キーを入力してください';
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
      _status = 'AIキーを保存しました（このブラウザのみ）';
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
      _status = '保存キーを削除しました。共有バックエンドを使用します。';
      _statusOk = true;
    });
  }

  Future<void> _test() async {
    final key = _controller.text.trim();
    if (key.isEmpty) {
      setState(() {
        _status = 'テストするキーを入力してください';
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
          result.ok ? 'キーは有効です。AI抽出を利用できます。' : _testFailureLabel(result.kind);
    });
  }

  String _testFailureLabel(AiReceiptFailureKind? kind) {
    return switch (kind) {
      AiReceiptFailureKind.configuration => '無効なキー、または権限がありません',
      AiReceiptFailureKind.quota => '利用上限に達しています',
      AiReceiptFailureKind.dailyLimit => '本日の利用上限に達しています',
      AiReceiptFailureKind.unavailable => 'ネットワーク / サービスに接続できません',
      AiReceiptFailureKind.missingKey => 'キーが入力されていません',
      _ => 'キーを確認できませんでした',
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = _saved ? '保存済み（localStorage）' : '未設定（共有バックエンドを使用）';

    return _Card(
      title: 'AIキー（Gemini・任意）',
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
            labelText: 'Gemini API キー（任意）',
            hintText: 'Google AI Studio で作成したキー（未入力でも利用可）',
            prefixIcon: const Icon(Icons.key_outlined),
            suffixIcon: IconButton(
              tooltip: _obscure ? '表示' : '隠す',
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
              label: const AppText('保存'),
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
              label: const AppText('キーをテスト'),
            ),
            TextButton.icon(
              onPressed: _busy ? null : _clear,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const AppText('クリア'),
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
