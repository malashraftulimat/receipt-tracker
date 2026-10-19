import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/providers.dart';
import '../../../domain/models/category.dart';
import '../../../domain/models/receipt_filter.dart';

/// Search field, quick month/category chips and view toggle.
class FilterBar extends ConsumerStatefulWidget {
  const FilterBar({super.key});

  @override
  ConsumerState<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends ConsumerState<FilterBar> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: ref.read(receiptFilterProvider).search);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final filter = ref.read(receiptFilterProvider);
    final initialRange = (filter.from != null && filter.to != null)
        ? DateTimeRange(
            start: filter.from!,
            end: filter.to!.subtract(const Duration(days: 1)),
          )
        : null;

    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: now,
      initialDateRange: initialRange,
      helpText: '期間を選択',
      saveText: '決定',
      cancelText: 'キャンセル',
      fieldStartLabelText: '開始日',
      fieldEndLabelText: '終了日',
      locale: const Locale('ja'),
    );

    if (range != null) {
      ref
          .read(receiptFilterProvider.notifier)
          .setRange(range.start, range.end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(receiptFilterProvider);
    final notifier = ref.read(receiptFilterProvider.notifier);
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];

    final now = DateTime.now();
    final thisMonth = DateTime(now.year, now.month);
    final lastMonth = DateTime(now.year, now.month - 1);

    return Padding(
      padding: EdgeInsets.fromLTRB(context.pagePadding, 4, context.pagePadding, 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _searchController,
                  textInputAction: TextInputAction.search,
                  onChanged: notifier.setSearch,
                  decoration: InputDecoration(
                    hintText: '店舗名・メモ・バーコードで検索',
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: filter.searchTerm.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'クリア',
                            onPressed: () {
                              _searchController.clear();
                              notifier.setSearch('');
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _ViewToggleButton(
                view: filter.view,
                onPressed: () => notifier.setView(
                  filter.view == ReceiptViewMode.list
                      ? ReceiptViewMode.grid
                      : ReceiptViewMode.list,
                ),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: '期間指定',
                onPressed: _pickRange,
                icon: const Icon(Icons.date_range_outlined),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 36,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                _FilterChip(
                  label: 'すべて',
                  selected: filter.categoryId == null &&
                      filter.month == null &&
                      filter.from == null,
                  onTap: notifier.reset,
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '今月',
                  selected: filter.month != null && _sameMonth(filter.month!, thisMonth),
                  onTap: () => notifier.setMonth(thisMonth),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: '先月',
                  selected: filter.month != null && _sameMonth(filter.month!, lastMonth),
                  onTap: () => notifier.setMonth(lastMonth),
                ),
                if (filter.from != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: _FilterChip(
                      label: formatRangeJa(
                        filter.from!,
                        (filter.to ?? filter.from!).subtract(const Duration(days: 1)),
                      ),
                      selected: true,
                      onTap: notifier.clearRange,
                    ),
                  ),
                for (final category in categories) ...<Widget>[
                  const SizedBox(width: 6),
                  _FilterChip(
                    label: category.name,
                    accent: category.colorValue,
                    selected: filter.categoryId == category.id,
                    onTap: () => notifier.toggleCategory(category.id),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool _sameMonth(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month;
}

class _ViewToggleButton extends StatelessWidget {
  const _ViewToggleButton({required this.view, required this.onPressed});

  final ReceiptViewMode view;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton.filledTonal(
      tooltip: view == ReceiptViewMode.list ? 'グリッド表示' : 'リスト表示',
      onPressed: onPressed,
      icon: Icon(
        view == ReceiptViewMode.list ? Icons.grid_view : Icons.view_list,
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = accent ?? theme.colorScheme.primary;

    return Material(
      color: selected ? color.withValues(alpha: 0.14) : theme.colorScheme.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected
              ? color.withValues(alpha: 0.6)
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? color : theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
