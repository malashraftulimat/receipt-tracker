import 'package:flutter/material.dart';

import '../../../core/localization/currencies.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/receipt_item.dart';
import '../../../core/localization/localization.dart';

/// Read-only item row used on the receipt detail screen.
class ReceiptItemRow extends StatelessWidget {
  const ReceiptItemRow({super.key, required this.item, this.currency = kFallbackCurrencyCode});

  final ReceiptItem item;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taxColor = item.taxRate == 8 ? AppPalette.emerald : AppPalette.violet;

    final subtitle = <String>[
      '${item.quantity} × ${formatMoney(item.effectiveUnitPrice, currency: currency)}',
      if (item.taxRate != null) '${item.taxRate}%',
    ].join('coupon.separator');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                AppText(
                  item.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                AppText(
                  subtitle,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (item.taxRate != null)
            Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: AppPalette.tintedPill(taxColor, radius: 7),
              child: AppText(
                '${item.taxRate}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: taxColor,
                ),
              ),
            ),
          AppText(
            formatMoney(item.totalPrice, currency: currency),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppPalette.text,
            ),
          ),
        ],
      ),
    );
  }
}
