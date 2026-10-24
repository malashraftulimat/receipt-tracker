import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/barcode_utils.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../core/widgets/language_switcher.dart';
import '../../data/providers.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/wallet.dart';
import '../dashboard/analytics_provider.dart';
import '../dashboard/widgets/receipt_tile.dart';
import '../review/review_page.dart';
import 'widgets/receipt_item_row.dart';
import '../../core/localization/localization.dart';

class ReceiptDetailPage extends ConsumerWidget {
  const ReceiptDetailPage({super.key, required this.receiptId});

  final String receiptId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Receipt receipt,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const AppText('delete_this_receipt'),
        content: AppText(
          '${receipt.displayMerchant}（${formatMoney(receipt.totalAmount, currency: receipt.currency)}）を削除します。'
          'この操作は取り消せません。',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const AppText('cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const AppText('a11y.delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(receiptRepositoryProvider).delete(receipt.id);
      if (!context.mounted) return;
      ref.invalidate(receiptsProvider);
      ref.invalidate(walletReceiptsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(receiptByIdProvider(receipt.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: AppText('deleted')),
      );
      if (context.canPop()) context.pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: AppText('削除に失敗しました: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipt = ref.watch(receiptByIdProvider(receiptId));
    final wallets =
        ref.watch(walletsProvider).valueOrNull ?? const <Wallet>[];

    return Scaffold(
      appBar: AppBar(
        title: const AppText('receipt_details'),
        actions: headerActions(
          context,
          showLanguageLabel: context.isExpanded,
          actions: <Widget>[
            asyncReceipt.maybeWhen(
              data: (receipt) => PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') {
                    context.push(
                      '/review',
                      extra: ReviewArgs(existing: receipt),
                    );
                  } else if (value == 'delete') {
                    _delete(context, ref, receipt);
                  }
                },
                itemBuilder: (context) => const <PopupMenuEntry<String>>[
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: ListTile(
                      leading: Icon(Icons.edit_outlined),
                      title: AppText('edit'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: ListTile(
                      leading: Icon(Icons.delete_outline),
                      title: AppText('a11y.delete'),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              orElse: () => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
      body: asyncReceipt.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.cloud_off, size: 40),
                const SizedBox(height: 12),
                AppText('読み込めませんでした\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(receiptByIdProvider(receiptId)),
                  child: const AppText('retry'),
                ),
              ],
            ),
          ),
        ),
        data: (receipt) => _DetailBody(
          receipt: receipt,
          wallet: _walletFor(wallets, receipt.walletId),
        ),
      ),
    );
  }
}

Wallet? _walletFor(List<Wallet> wallets, String? id) {
  if (id == null) return null;
  for (final wallet in wallets) {
    if (wallet.id == id) return wallet;
  }
  return null;
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.receipt, this.wallet});

  final Receipt receipt;
  final Wallet? wallet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = context.pagePadding;
    String money(num value) => formatMoney(value, currency: receipt.currency);
    final category = receipt.category;
    final accent = AppPalette.categoryAccent(
      category?.name,
      fallback: category?.colorValue ?? theme.colorScheme.outline,
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: AppPalette.card(
                  context,
                  accent: accent,
                  glow: true,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: accent.withValues(alpha: 0.14),
                          child: Icon(
                            category?.iconData ?? Icons.receipt_outlined,
                            color: accent,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              AppText(
                                receipt.displayTitle,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              AppText(
                                formatDateTimeJa(receipt.purchasedAt),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    AppText(
                      money(receipt.totalAmount),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppPalette.emerald,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        CategoryPill(
                          label: receipt.displayCategory,
                          color: accent,
                          icon: category?.iconData,
                        ),
                        if (receipt.paymentMethod != null)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              receipt.displayPaymentMethod,
                              style: const TextStyle(fontSize: 11),
                            ),
                            avatar: Icon(
                              receipt.paymentMethod!.icon,
                              size: 14,
                            ),
                          ),
                        if (wallet != null)
                          Chip(
                            visualDensity: VisualDensity.compact,
                            label: AppText(
                              wallet!.name,
                              translate: false,
                              style: const TextStyle(fontSize: 11),
                            ),
                            avatar: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: Color(wallet!.colorValue),
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: AppText(
                            receiptSourceLabel(receipt.source),
                            style: const TextStyle(fontSize: 11),
                          ),
                          avatar: Icon(
                            receipt.source == ReceiptSource.barcode
                                ? Icons.qr_code_2
                                : receipt.source == ReceiptSource.ocr
                                    ? Icons.document_scanner_outlined
                                    : Icons.edit_outlined,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              _InfoCard(
                title: 'amount_breakdown',
                children: <Widget>[
                  _InfoRow(
                    label: 'csv.currency',
                    value: receipt.currency,
                  ),
                  _InfoRow(
                    label: 'total_tax_included',
                    value: money(receipt.totalAmount),
                    emphasized: true,
                  ),
                  if (receipt.subtotalAmount != null)
                    _InfoRow(
                      label: 'subtotal_tax_excluded',
                      value: money(receipt.subtotalAmount!),
                    ),
                  if (receipt.tax8Amount != null)
                    _InfoRow(
                      label:
                          '消費税 8%${receipt.tax8Base != null ? '（対象 ${money(receipt.tax8Base!)}）' : ''}',
                      value: money(receipt.tax8Amount!),
                    ),
                  if (receipt.tax10Amount != null)
                    _InfoRow(
                      label:
                          '消費税 10%${receipt.tax10Base != null ? '（対象 ${money(receipt.tax10Base!)}）' : ''}',
                      value: money(receipt.tax10Amount!),
                    ),
                  if (receipt.hasTaxBreakdown)
                    _InfoRow(
                      label: 'total_consumption_tax',
                      value: money(receipt.taxTotal),
                    ),
                  if (receipt.tax8ItemsTotal != null)
                    _InfoRow(
                      label: '8_taxable_subtotal_estimated',
                      value: money(receipt.tax8ItemsTotal!),
                    ),
                  if (receipt.tax10ItemsTotal != null)
                    _InfoRow(
                      label: '10_taxable_subtotal_estimated',
                      value: money(receipt.tax10ItemsTotal!),
                    ),
                ],
              ),
              if (receipt.items.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'items',
                  children: <Widget>[
                    for (final item in receipt.items)
                      ReceiptItemRow(
                        item: item,
                        currency: receipt.currency,
                      ),
                  ],
                ),
              ],
              if (receipt.dueDate != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'due_date',
                  children: <Widget>[
                    _DueDateRow(dueDate: receipt.dueDate!),
                    if (receipt.reminderAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: AppText(
                          'リマインダー: ${formatDateJa(receipt.reminderAt!)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              if (receipt.pointAmount != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'points_2',
                  children: <Widget>[
                    _InfoRow(
                      label: receipt.pointBrand ?? 'points_2',
                      value: '${receipt.pointAmount} pt',
                      emphasized: true,
                    ),
                  ],
                ),
              ],
              if (receipt.barcodeId != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'receipt_number',
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SelectableText(
                            BarcodeUtils.format(receipt.barcodeId!),
                            style: const TextStyle(
                              fontSize: 15,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('copy'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: receipt.barcodeId!),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: AppText('copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                        ),
                      ],
                    ),
                    if (BarcodeUtils.looksLikeJan(receipt.barcodeId!) &&
                        !BarcodeUtils.isValidEan13(receipt.barcodeId!))
                      AppText(
                        'jan_13_check_digit_does_not_match_please_ver',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ],
              if (receipt.invoiceRegistrationNumber != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'invoice_registration_number',
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: SelectableText(
                            receipt.invoiceRegistrationNumber!,
                            style: const TextStyle(
                              fontSize: 15,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: context.tr('copy'),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: receipt.invoiceRegistrationNumber!,
                              ),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: AppText('copied')),
                            );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              if ((receipt.note ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'note',
                  children: <Widget>[
                    AppText(
                      receipt.note!.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ],
              if ((receipt.rawOcrText ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'ocr_text',
                  children: <Widget>[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: AppText(
                        'show_original',
                        style: theme.textTheme.bodySmall,
                      ),
                      children: <Widget>[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: SelectableText(
                            receipt.rawOcrText!,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              height: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              AppText(
                '登録: ${formatDateTimeJa(receipt.createdAt)}  /  '
                '更新: ${formatDateTimeJa(receipt.updatedAt)}',
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

class _DueDateRow extends StatelessWidget {
  const _DueDateRow({required this.dueDate});

  final DateTime dueDate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    final days = target.difference(today).inDays;

    final Color color;
    final String label;
    if (days < 0) {
      color = AppPalette.danger;
      label = '${-days} 日過ぎています';
    } else if (days == 0) {
      color = AppPalette.danger;
      label = 'due_today';
    } else if (days <= 3) {
      color = AppPalette.amber;
      label = 'あと$days日';
    } else {
      color = AppPalette.emerald;
      label = 'あと$days日';
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: AppText(
            formatDateJa(dueDate),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8),
          ),
          child: AppText(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: AppPalette.card(
        context,
        accent: AppPalette.violet,
        radius: 18,
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

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: AppText(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          AppText(
            value,
            style: emphasized
                ? theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppPalette.emerald,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
