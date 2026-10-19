import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/config/app_config.dart';
import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/services/export_service.dart';
import '../../domain/models/receipt_filter.dart';
import '../../data/services/local_auth.dart';
import '../../data/services/local_store.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  Future<void> _seedDefaults(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(categoryRepositoryProvider).ensureDefaults();
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('標準カテゴリを確認しました')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('失敗しました: $error')),
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
        messenger.showSnackBar(const SnackBar(content: Text('対象のレシートがありません')));
        return;
      }

      final filename = currentMonthOnly
          ? ExportService.filenameForMonth(now)
          : ExportService.allFilename();
      final result = await ExportService.export(receipts, filename: filename);
      messenger.showSnackBar(
        SnackBar(content: Text('CSVを書き出しました: $result')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('書き出しに失敗しました: $error')),
      );
    }
  }
  Future<void> _switchToLocal(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ローカルモードに切り替えますか？'),
        content: const Text(
          'レシートとカテゴリはこの端末（ブラウザ）にのみ保存されます。'
          'サーバー上のデータはそのまま残り、いつでも戻せます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('切り替える'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(appModeProvider.notifier).switchToLocal();
  }

  Future<void> _switchToSupabase(BuildContext context, WidgetRef ref) async {
    await ref.read(appModeProvider.notifier).switchToSupabase();
  }

  Future<void> _clearLocalData(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ローカルデータを削除しますか？'),
        content: const Text('この端末に保存したレシート・画像・カテゴリをすべて削除します。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final account = AppConfig.localUser;
    await LocalStore.instance.clearAll();
    if (account != null) await LocalAuth.instance.deleteAccount(account.id);
    await LocalAuth.instance.signOut();
    ref.read(localSessionProvider.notifier).setUser(null);
    if (!context.mounted) return;
    context.go('/auth');
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: Text(
          AppConfig.isLocal
              ? 'ローカルアカウントからログアウトします。データはこの端末に残ります。'
              : 'データはサーバーに保存されています。次回ログインで復元されます。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (AppConfig.isLocal) {
      await LocalAuth.instance.signOut();
      ref.read(localSessionProvider.notifier).setUser(null);
      if (!context.mounted) return;
      context.go('/auth');
      return;
    }

    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isLocal = AppConfig.isLocal;

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
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
                  backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.14),
                  child: Icon(
                    Icons.person_outline,
                    color: theme.colorScheme.primary,
                  ),
                ),
                title: Text(user?.email ?? '未ログイン'),
                subtitle: Text(
                  isLocal
                      ? 'ローカルアカウント（この端末のみ・他の端末とは同期しません）'
                      : 'すべての端末でレシート・画像・カテゴリが同期されます',
                  style: theme.textTheme.labelSmall,
                ),
                trailing: IconButton(
                  tooltip: 'ユーザーIDをコピー',
                  onPressed: user == null
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: user.id),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('ユーザーIDをコピーしました')),
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
                  label: const Text('ログアウト'),
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
                      label: Text('自動'),
                      icon: Icon(Icons.brightness_auto_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.light,
                      label: Text('ライト'),
                      icon: Icon(Icons.light_mode_outlined, size: 18),
                    ),
                    ButtonSegment<ThemeMode>(
                      value: ThemeMode.dark,
                      label: Text('ダーク'),
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
            title: 'データ',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const Text('標準カテゴリを再作成'),
                subtitle: const Text('食費・外食・日用品・光熱費・交通費・娯楽など'),
                onTap: () => _seedDefaults(context, ref),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.file_download_outlined),
                title: const Text('CSVエクスポート（今月）'),
                subtitle: const Text('Excel / Numbers で開ける UTF-8 CSV'),
                onTap: () =>
                    _exportCsv(context, ref, currentMonthOnly: true),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.table_view_outlined),
                title: const Text('CSVエクスポート（全期間）'),
                subtitle: const Text('すべてのレシートを1ファイルにまとめます'),
                onTap: () =>
                    _exportCsv(context, ref, currentMonthOnly: false),
              ),
              const Divider(height: 1),              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isLocal ? Icons.phone_android : Icons.cloud_sync_outlined,
                ),
                title: Text(
                  isLocal ? 'ローカル保存（この端末のみ）' : 'Supabase と同期中',
                ),
                subtitle: Text(
                  isLocal
                      ? 'レシートはブラウザの localStorage に保存されます。'
                          '他の端末とは共有されません。'
                      : 'Postgres / Storage に保存され、すべての端末で共有されます。',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  isLocal ? Icons.cloud_outlined : Icons.storage_outlined,
                ),
                title: Text(
                  isLocal ? 'Supabase に接続する' : 'ローカルモードに切り替える',
                ),
                subtitle: Text(
                  isLocal
                      ? 'アカウントを作成して複数端末で同期できます'
                      : 'サーバーを使わず、この端末だけに保存します',
                ),
                onTap: () =>
                    isLocal
                        ? _switchToSupabase(context, ref)
                        : _switchToLocal(context, ref),
              ),
              if (isLocal) ...<Widget>[
                const Divider(height: 1),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('ローカルデータを削除'),
                  subtitle: const Text('この端末のレシート・画像・カテゴリを消去します'),
                  onTap: () => _clearLocalData(context, ref),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          const _Card(
            title: 'このアプリについて',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.document_scanner_outlined),
                title: Text('スキャンエンジン'),
                subtitle: Text(
                  '1Dバーコード: JAN-13 / EAN-8 / Code 128 / Code 39 / ITF\n'
                  'OCR: ML Kit（iOS・Android オンデバイス）/ Cloud Vision（Web・デスクトップ）',
                ),
              ),
              Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.info_outline),
                title: Text('バージョン'),
                subtitle: Text('1.0.0 (Flutter / Riverpod / Supabase)'),
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
          Text(
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
