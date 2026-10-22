import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/category.dart';
import '../dashboard/analytics_provider.dart';
import '../../core/localization/localization.dart';

class CategoriesPage extends ConsumerWidget {
  const CategoriesPage({super.key});

  Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    ExpenseCategory? category,
  }) async {
    final result = await showDialog<_CategoryFormResult>(
      context: context,
      builder: (context) => _CategoryDialog(category: category),
    );
    if (result == null) return;

    final repository = ref.read(categoryRepositoryProvider);
    try {
      if (category == null) {
        await repository.create(
          name: result.name,
          color: result.color,
          icon: result.icon,
        );
      } else {
        await repository.update(
          category.copyWith(
            name: result.name,
            color: result.color,
            icon: result.icon,
          ),
        );
      }
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('保存に失敗しました: $error')),
      );
    }
  }

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    ExpenseCategory category,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('カテゴリを削除しますか？'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AppText('「${category.name}」を削除します。'),
            const SizedBox(height: 6),
            const AppText('このカテゴリに紐づくレシートは「未分類」になります。'),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(categoryRepositoryProvider).delete(category.id);
      if (!context.mounted) return;
      ref.invalidate(categoriesProvider);
      ref.invalidate(receiptsProvider);
      ref.invalidate(analyticsProvider);
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('削除に失敗しました: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCategories = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const AppText('カテゴリ'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            IconButton(
              tooltip: context.tr('カテゴリを追加'),
              onPressed: () => _openEditor(context, ref),
              icon: const Icon(Icons.add),
            ),
          ],
        ),
      ),
      body: asyncCategories.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AppText('カテゴリを読み込めませんでした\n$error'),
          ),
        ),
        data: (categories) {
          if (categories.isEmpty) {
            return const Center(child: AppText('カテゴリがありません'));
          }
          return ListView.separated(
            padding: EdgeInsets.fromLTRB(
              context.pagePadding,
              8,
              context.pagePadding,
              32,
            ),
            itemCount: categories.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final category = categories[index];
              final accent = AppPalette.categoryAccent(
                category.name,
                fallback: category.colorValue,
              );
              return Container(
                decoration: AppPalette.card(
                  context,
                  accent: accent,
                  radius: 18,
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.18),
                    child: Icon(
                      category.iconData,
                      color: accent,
                      size: 20,
                    ),
                  ),
                  title: Row(
                    children: <Widget>[
                      Flexible(
                        child: AppText(
                          category.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                      if (category.isDefault) ...<Widget>[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: AppText(
                            '標準',
                            style: TextStyle(
                              fontSize: 10,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'edit') {
                        _openEditor(context, ref, category: category);
                      } else if (value == 'delete') {
                        _delete(context, ref, category);
                      }
                    },
                    itemBuilder: (context) => const <PopupMenuEntry<String>>[
                      PopupMenuItem<String>(
                        value: 'edit',
                        child: AppText('編集'),
                      ),
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: AppText('削除'),
                      ),
                    ],
                  ),
                  onTap: () => _openEditor(context, ref, category: category),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _CategoryFormResult {
  const _CategoryFormResult({
    required this.name,
    required this.color,
    required this.icon,
  });

  final String name;
  final String color;
  final String icon;
}

class _CategoryDialog extends StatefulWidget {
  const _CategoryDialog({this.category});

  final ExpenseCategory? category;

  @override
  State<_CategoryDialog> createState() => _CategoryDialogState();
}

class _CategoryDialogState extends State<_CategoryDialog> {
  late final TextEditingController _name;
  late String _color;
  late String _icon;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.category?.name ?? '');
    _color = widget.category?.color ?? kCategoryColors.first;
    _icon = widget.category?.icon ?? 'category';
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) return;
    Navigator.of(context).pop(
      _CategoryFormResult(name: name, color: _color, icon: _icon),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: AppText(widget.category == null ? 'カテゴリを追加' : 'カテゴリを編集'),
      content: SizedBox(
        width: 400,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: context.tr('カテゴリ名'),
                  hintText: context.tr('例: 交際費、サブスク'),
                ),
              ),
              const SizedBox(height: 18),
              AppText('色', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: <Widget>[
                  for (final color in kCategoryColors)
                    _ColorDot(
                      hex: color,
                      selected: _color == color,
                      onTap: () => setState(() => _color = color),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              AppText('アイコン', style: theme.textTheme.labelMedium),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  for (final key in kCategoryIconKeys)
                    InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => setState(() => _icon = key),
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _icon == key
                              ? _parseColor(_color).withValues(alpha: 0.18)
                              : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _icon == key
                                ? _parseColor(_color)
                                : Colors.transparent,
                          ),
                        ),
                        child: Icon(
                          categoryIcon(key),
                          size: 20,
                          color: _icon == key
                              ? _parseColor(_color)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const AppText('キャンセル'),
        ),
        FilledButton(onPressed: _submit, child: const AppText('保存')),
      ],
    );
  }

  Color _parseColor(String hex) => Color(
      0xFF000000 | (int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0));
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.hex,
    required this.selected,
    required this.onTap,
  });

  final String hex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(
      0xFF000000 | (int.tryParse(hex.replaceFirst('#', ''), radix: 16) ?? 0),
    );
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: selected
            ? const Icon(Icons.check, size: 16, color: Colors.white)
            : null,
      ),
    );
  }
}
