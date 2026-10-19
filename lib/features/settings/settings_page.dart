import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_mode_provider.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';

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

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        content: const Text('データはサーバーに保存されています。次回ログインで復元されます。'),
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
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final user = ref.watch(currentUserProvider);
    final themeMode = ref.watch(themeModeProvider);

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
                  'すべての端末でレシート・画像・カテゴリが同期されます',
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
                leading: const Icon(Icons.cloud_sync_outlined),
                title: const Text('同期について'),
                subtitle: const Text(
                  'Supabase の Postgres / Storage に保存され、'
                  'サインインしたすべての端末へリアルタイムに反映されます。',
                ),
                onTap: null,
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Card(
            title: 'このアプリについて',
            children: <Widget>[
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('スキャンエンジン'),
                subtitle: const Text(
                  '1Dバーコード: JAN-13 / EAN-8 / Code 128 / Code 39 / ITF\n'
                  'OCR: ML Kit（iOS・Android オンデバイス）/ Cloud Vision（Web・デスクトップ）',
                ),
              ),
              const Divider(height: 1),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.info_outline),
                title: const Text('バージョン'),
                subtitle: const Text('1.0.0 (Flutter / Riverpod / Supabase)'),
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
