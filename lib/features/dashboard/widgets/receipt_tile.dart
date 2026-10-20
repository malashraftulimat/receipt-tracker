import 'package:flutter/material.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../domain/models/receipt.dart';
import '../../../core/localization/localization.dart';

/// Small colour-coded category pill.
class CategoryPill extends StatelessWidget {
  const CategoryPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: AppPalette.tintedPill(color, radius: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Dense list row.
class ReceiptTile extends StatelessWidget {
  const ReceiptTile({super.key, required this.receipt, this.onTap});

  final Receipt receipt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = receipt.category;
    final accent = AppPalette.categoryAccent(
      category?.name,
      fallback: category?.colorValue ?? theme.colorScheme.outline,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: AppPalette.card(context, accent: accent),
            child: Row(
              children: <Widget>[
                CircleAvatar(
                  radius: 18,
                  backgroundColor: accent.withValues(alpha: 0.14),
                  child: Icon(
                    category?.iconData ?? Icons.receipt_outlined,
                    size: 18,
                    color: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AppText(
                        receipt.displayMerchant,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: <Widget>[
                          AppText(
                            formatTimeJa(receipt.purchasedAt),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: CategoryPill(
                              label: receipt.displayCategory,
                              color: accent,
                            ),
                          ),
                          if (receipt.barcodeId != null) ...<Widget>[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.qr_code_2,
                              size: 13,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AppText(
                  formatYen(receipt.totalAmount),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.emerald,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Card used by the grid view.
class ReceiptGridCard extends StatelessWidget {
  const ReceiptGridCard({super.key, required this.receipt, this.onTap});

  final Receipt receipt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final category = receipt.category;
    final accent = category?.colorValue ?? theme.colorScheme.outline;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: AppPalette.card(context, accent: accent),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  CircleAvatar(
                    radius: 15,
                    backgroundColor: accent.withValues(alpha: 0.14),
                    child: Icon(
                      category?.iconData ?? Icons.receipt_outlined,
                      size: 15,
                      color: accent,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: CategoryPill(
                        label: receipt.displayCategory, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              AppText(
                receipt.displayMerchant,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600, height: 1.25),
              ),
              const Spacer(),
              AppText(
                formatYen(receipt.totalAmount),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              AppText(
                '${formatDateShortJa(receipt.purchasedAt)} ${formatTimeJa(receipt.purchasedAt)}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
