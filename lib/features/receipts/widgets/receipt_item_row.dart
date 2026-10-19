import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../../../domain/models/receipt_item.dart';

/// Read-only item row used on the receipt detail screen.
class ReceiptItemRow extends StatelessWidget {
  const ReceiptItemRow({super.key, required this.item});

  final ReceiptItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taxColor = item.taxRate == 8
        ? const Color(0xFF2E7D32)
        : theme.colorScheme.primary;

    final subtitle = <String>[
      '${item.quantity} × ${formatYen(item.effectiveUnitPrice)}',
      if (item.taxRate != null) '${item.taxRate}%',
    ].join(' ・ ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  item.name,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
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
              decoration: BoxDecoration(
                color: taxColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${item.taxRate}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: taxColor,
                ),
              ),
            ),
          Text(
            formatYen(item.totalPrice),
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}