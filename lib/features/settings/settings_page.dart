import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/localization/localization.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/services/export_service.dart';
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
      appBar: AppBar(title: const AppText('設定')),
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
                'アラビア語・英語・日本語を切り替えられます。'
                'アラビア語では画面が右から左に表示されます。',
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
                  'AI抽出: Gemini Flash（Google AI Studio）\n'
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
