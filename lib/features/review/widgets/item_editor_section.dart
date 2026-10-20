import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/category.dart';
import '../../../domain/models/receipt_item.dart';
import '../../../core/localization/localization.dart';

/// Mutable per-row state for the item editor.
class ReceiptItemEditor {
  ReceiptItemEditor({ReceiptItem? item, this.categoryId})
      : name = TextEditingController(text: item?.name ?? ''),
        quantity =
            TextEditingController(text: (item?.quantity ?? 1).toString()),
        unitPrice = TextEditingController(
          text: item?.unitPrice == null
              ? ''
              : formatAmountDigits(item!.unitPrice!),
        ),
        totalPrice = TextEditingController(
          text: (item?.totalPrice ?? 0) == 0
              ? ''
              : formatAmountDigits(item!.totalPrice),
        ),
        taxRate = item?.taxRate {
    categoryId = categoryId ?? item?.categoryId;
  }

  final TextEditingController name;
  final TextEditingController quantity;
  final TextEditingController unitPrice;
  final TextEditingController totalPrice;
  int? taxRate;
  String? categoryId;

  int get quantityValue => int.tryParse(quantity.text.trim()) ?? 1;

  int get totalValue {
    final direct = parseYenInput(totalPrice.text);
    if (direct != null) return direct;
    final unit = parseYenInput(unitPrice.text);
    if (unit != null) return unit * quantityValue;
    return 0;
  }

  int? get unitValue {
    final unit = parseYenInput(unitPrice.text);
    if (unit != null) return unit;
    final total = totalValue;
    if (total == 0) return null;
    final qty = quantityValue <= 0 ? 1 : quantityValue;
    return (total / qty).round();
  }

  ReceiptItem toItem(int index) => ReceiptItem(
        id: null,
        name: name.text.trim(),
        quantity: quantityValue <= 0 ? 1 : quantityValue,
        unitPrice: unitValue,
        totalPrice: totalValue,
        taxRate: taxRate,
        categoryId: categoryId,
        sortOrder: index,
      );

  void dispose() {
    name.dispose();
    quantity.dispose();
    unitPrice.dispose();
    totalPrice.dispose();
  }
}

/// Editable item list + sum/tax cross-check against the receipt total.
class ItemEditorSection extends StatelessWidget {
  const ItemEditorSection({
    super.key,
    required this.items,
    required this.categories,
    required this.totalAmount,
    required this.taxTotal,
    required this.onAdd,
    required this.onRemove,
    required this.onChanged,
    required this.onMatchTotal,
  });

  final List<ReceiptItemEditor> items;
  final List<ExpenseCategory> categories;
  final int totalAmount;
  final int taxTotal;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;
  final VoidCallback onChanged;
  final VoidCallback onMatchTotal;

  int get itemsTotal =>
      items.fold<int>(0, (sum, item) => sum + item.totalValue);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final itemsTotalValue = itemsTotal;
    final withTax = itemsTotalValue + taxTotal;
    final directMatch = (itemsTotalValue - totalAmount).abs() <= 1;
    final taxMatch = (withTax - totalAmount).abs() <= 1;
    final hasItems = items.isNotEmpty;
    final ok = hasItems && totalAmount > 0 && (directMatch || taxMatch);

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
          Row(
            children: <Widget>[
              AppText(
                '明細（商品）',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              AppText(
                '${items.length} 行',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ItemCard(
                editor: items[i],
                categories: categories,
                onChanged: onChanged,
                onRemove: () => onRemove(i),
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const AppText('明細を追加'),
            ),
          ),
          const Divider(height: 18),
          _ValidationRow(
            ok: ok,
            hasItems: hasItems,
            itemsTotal: itemsTotalValue,
            withTax: withTax,
            totalAmount: totalAmount,
            taxTotal: taxTotal,
            directMatch: directMatch,
            taxMatch: taxMatch,
            onMatchTotal: onMatchTotal,
          ),
        ],
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({
    required this.editor,
    required this.categories,
    required this.onChanged,
    required this.onRemove,
  });

  final ReceiptItemEditor editor;
  final List<ExpenseCategory> categories;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: editor.name,
                  onChanged: (_) => onChanged(),
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.tr('商品名'),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              IconButton(
                tooltip: context.tr('削除'),
                onPressed: onRemove,
                icon: Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 64,
                child: _NumberField(
                  controller: editor.quantity,
                  label: '数量',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _NumberField(
                  controller: editor.unitPrice,
                  label: '単価',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _NumberField(
                  controller: editor.totalPrice,
                  label: '金額',
                  onChanged: onChanged,
                ),
              ),
              const SizedBox(width: 6),
              _TaxSelector(
                rate: editor.taxRate,
                onChanged: (rate) {
                  editor.taxRate = rate;
                  onChanged();
                },
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Icon(
                Icons.sell_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: editor.categoryId,
                  isDense: true,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  hint: const AppText('カテゴリ自動', style: TextStyle(fontSize: 11)),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: AppText('未分類', style: TextStyle(fontSize: 11)),
                    ),
                    for (final category in categories)
                      DropdownMenuItem<String?>(
                        value: category.id,
                        child: AppText(
                          category.name,
                          style: const TextStyle(fontSize: 11),
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    editor.categoryId = value;
                    onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    required this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
      ],
      onChanged: (_) => onChanged(),
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      ),
    );
  }
}

class _TaxSelector extends StatelessWidget {
  const _TaxSelector({required this.rate, required this.onChanged});

  final int? rate;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = rate == 8 ? '8%' : (rate == 10 ? '10%' : '税率');

    return PopupMenuButton<int?>(
      tooltip: context.tr('税率'),
      onSelected: onChanged,
      itemBuilder: (context) => const <PopupMenuEntry<int?>>[
        PopupMenuItem<int?>(value: 8, child: AppText('8%（軽減）')),
        PopupMenuItem<int?>(value: 10, child: AppText('10%（標準）')),
        PopupMenuItem<int?>(value: null, child: AppText('指定なし')),
      ],
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: <Widget>[
            AppText(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: rate == 8
                    ? AppPalette.emerald
                    : rate == 10
                        ? AppPalette.violet
                        : theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}

class _ValidationRow extends StatelessWidget {
  const _ValidationRow({
    required this.ok,
    required this.hasItems,
    required this.itemsTotal,
    required this.withTax,
    required this.totalAmount,
    required this.taxTotal,
    required this.directMatch,
    required this.taxMatch,
    required this.onMatchTotal,
  });

  final bool ok;
  final bool hasItems;
  final int itemsTotal;
  final int withTax;
  final int totalAmount;
  final int taxTotal;
  final bool directMatch;
  final bool taxMatch;
  final VoidCallback onMatchTotal;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!hasItems) {
      return Row(
        children: <Widget>[
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: AppText(
              '明細が未入力です。必要な場合は「明細を追加」から入力できます。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      );
    }

    final color = ok ? AppPalette.emerald : AppPalette.amber;
    final difference = totalAmount - (taxMatch ? withTax : itemsTotal);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(
              ok ? Icons.check_circle : Icons.warning_amber_rounded,
              size: 18,
              color: color,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: AppText(
                ok
                    ? '明細合計 ${formatYen(itemsTotal)} は合計と一致しています'
                    : '明細合計と合計が一致しません（差額 ${formatYen(difference.abs())}）',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AppText(
          '明細 ${formatYen(itemsTotal)}'
          '${taxTotal > 0 ? ' + 税 ${formatYen(taxTotal)} = ${formatYen(withTax)}' : ''}'
          ' / レシート合計 ${formatYen(totalAmount)}',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (!ok)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onMatchTotal,
              child: const AppText('合計金額に合わせる'),
            ),
          ),
      ],
    );
  }
}
