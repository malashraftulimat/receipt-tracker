import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_palette.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/press_scale.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/providers.dart';
import '../../../domain/models/receipt.dart';
import '../../../domain/models/receipt_filter.dart';
import 'receipt_tile.dart';
import '../../../core/localization/localization.dart';

/// List (grouped by year / month / day) or grid of receipts.
class ReceiptCollection extends ConsumerWidget {
  const ReceiptCollection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipts = ref.watch(receiptsProvider);
    final filter = ref.watch(receiptFilterProvider);

    return asyncReceipts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorState(
        error: error,
        onRetry: () => ref.invalidate(receiptsProvider),
      ),
      data: (receipts) {
        if (receipts.isEmpty) return const _EmptyState();
        return Column(
          children: <Widget>[
            _SummaryStrip(
              receipts: receipts,
              onRefresh: () => ref.invalidate(receiptsProvider),
            ),
            Expanded(
              child: filter.view == ReceiptViewMode.grid
                  ? _ReceiptGrid(receipts: receipts)
                  : _GroupedReceiptList(receipts: receipts),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Summary
// ---------------------------------------------------------------------------

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.receipts, required this.onRefresh});

  final List<Receipt> receipts;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final total = receipts.fold<double>(0, (sum, r) => sum + r.totalAmount);
    final average = total / receipts.length;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppPalette.card(context, accent: AppPalette.cyan),
      child: Row(
        children: <Widget>[
          _SummaryValue(label: 'count', value: '${receipts.length}件'),
          const SizedBox(width: 20),
          _SummaryValue(
            label: 'total',
            value: formatYen(total),
            accent: AppPalette.emerald,
          ),
          const SizedBox(width: 20),
          _SummaryValue(label: 'average', value: formatYen(average)),
          const Spacer(),
          IconButton(
            tooltip: context.tr('refresh'),
            visualDensity: VisualDensity.compact,
            onPressed: onRefresh,
            icon: const Icon(
              Icons.refresh,
              size: 18,
              color: AppPalette.cyan,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    this.accent,
  });

  final String label;
  final String value;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        AppText(
          label,
          style: theme.textTheme.labelSmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        AppText(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: accent,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped list
// ---------------------------------------------------------------------------

sealed class _Entry {
  const _Entry();
}

class _GroupHeader extends _Entry {
  const _GroupHeader(this.label, this.level, {this.total});

  final String label;
  final int level;
  final double? total;
}

class _ReceiptEntry extends _Entry {
  const _ReceiptEntry(this.receipt);

  final Receipt receipt;
}

class _GroupedReceiptList extends StatelessWidget {
  const _GroupedReceiptList({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final entries = _buildEntries(receipts);
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        if (entry is _GroupHeader) return _HeaderTile(header: entry);
        final receipt = (entry as _ReceiptEntry).receipt;
        return ReceiptTile(
          receipt: receipt,
          onTap: () => context.push('/receipt/${receipt.id}'),
        );
      },
    );
  }

  List<_Entry> _buildEntries(List<Receipt> source) {
    final sorted = List<Receipt>.of(source)
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));

    final monthTotals = <String, double>{};
    for (final receipt in sorted) {
      final key = '${receipt.purchasedAt.year}-${receipt.purchasedAt.month}';
      monthTotals[key] = (monthTotals[key] ?? 0) + receipt.totalAmount;
    }

    final entries = <_Entry>[];
    int? year;
    int? month;
    int? day;

    for (final receipt in sorted) {
      final date = receipt.purchasedAt;
      if (year != date.year) {
        year = date.year;
        month = null;
        day = null;
        entries.add(_GroupHeader(formatYearJa(date), 0));
      }
      if (month != date.month) {
        month = date.month;
        day = null;
        entries.add(
          _GroupHeader(
            formatMonthShortJa(date),
            1,
            total: monthTotals['${date.year}-${date.month}'],
          ),
        );
      }
      if (day != date.day) {
        day = date.day;
        entries.add(_GroupHeader(formatDayJa(date), 2));
      }
      entries.add(_ReceiptEntry(receipt));
    }
    return entries;
  }
}

class _HeaderTile extends StatelessWidget {
  const _HeaderTile({required this.header});

  final _GroupHeader header;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base =
        EdgeInsets.fromLTRB(context.pagePadding, 0, context.pagePadding, 0);

    switch (header.level) {
      case 0:
        return Padding(
          padding: base.copyWith(top: 18, bottom: 4),
          child: AppText(
            header.label,
            style: theme.textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        );
      case 1:
        return Padding(
          padding: base.copyWith(top: 10, bottom: 2),
          child: Row(
            children: <Widget>[
              AppText(
                header.label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppPalette.violet,
                ),
              ),
              const Spacer(),
              if (header.total != null)
                AppText(
                  formatYen(header.total!),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: AppPalette.emerald,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
        );
      default:
        return Padding(
          padding: base.copyWith(top: 8, bottom: 4),
          child: AppText(
            header.label,
            style: theme.textTheme.labelMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Grid
// ---------------------------------------------------------------------------

class _ReceiptGrid extends StatelessWidget {
  const _ReceiptGrid({required this.receipts});

  final List<Receipt> receipts;

  @override
  Widget build(BuildContext context) {
    final sorted = List<Receipt>.of(receipts)
      ..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        context.pagePadding,
        4,
        context.pagePadding,
        96,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: context.receiptGridColumns,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        mainAxisExtent: 172,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final receipt = sorted[index];
        return ReceiptGridCard(
          receipt: receipt,
          onTap: () => context.push('/receipt/${receipt.id}'),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// States
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                gradient: AppPalette.accentGradient,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: AppPalette.violet.withValues(alpha: 0.3),
                    blurRadius: 28,
                  ),
                ],
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                size: 44,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            AppText(
              'no_receipts_yet',
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            AppText(
              'read_barcodes_and_receipt_text_with_the_came',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            PressScale(
              child: FilledButton.icon(
                onPressed: () => context.push('/scan'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppPalette.cyan,
                  foregroundColor: AppPalette.backgroundDeep,
                ),
                icon: const Icon(Icons.document_scanner_outlined),
                label: const AppText('scan_2'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.cloud_off, size: 44, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            AppText(
              'could_not_load_data',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            AppText(
              error.toString(),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const AppText('retry')),
          ],
        ),
      ),
    );
  }
}
