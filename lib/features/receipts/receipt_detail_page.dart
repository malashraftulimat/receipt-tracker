import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/barcode_utils.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../domain/models/receipt.dart';
import '../dashboard/analytics_provider.dart';
import '../dashboard/widgets/receipt_tile.dart';
import '../review/review_page.dart';
import 'widgets/receipt_item_row.dart';
import '../shared/stored_image.dart';

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
        title: const Text('このレシートを削除しますか？'),
        content: Text(
          '${receipt.displayMerchant}（${formatYen(receipt.totalAmount)}）を削除します。'
          'この操作は取り消せません。',
        ),
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

    try {
      await ref.read(receiptRepositoryProvider).delete(receipt.id);
      // Best-effort image cleanup; a leftover object must not block deletion.
      if (receipt.imagePath != null) {
        try {
          await ref
              .read(storageRepositoryProvider)
              .deleteImage(receipt.imagePath!);
        } catch (_) {}
      }
      if (!context.mounted) return;
      ref.invalidate(receiptsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(receiptByIdProvider(receipt.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('削除しました')),
      );
      if (context.canPop()) context.pop();
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncReceipt = ref.watch(receiptByIdProvider(receiptId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('レシート詳細'),
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
                    title: Text('編集'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
                PopupMenuItem<String>(
                  value: 'delete',
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('削除'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
            orElse: () => const SizedBox.shrink(),
          ),
          const SizedBox(width: 4),
        ],
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
                Text('読み込めませんでした\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(receiptByIdProvider(receiptId)),
                  child: const Text('再試行'),
                ),
              ],
            ),
          ),
        ),
        data: (receipt) => _DetailBody(receipt: receipt),
      ),
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.receipt});

  final Receipt receipt;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = context.pagePadding;
    final category = receipt.category;
    final accent = category?.colorValue ?? theme.colorScheme.outline;

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(padding, 8, padding, 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (receipt.imagePath != null) ...<Widget>[
                _ReceiptImage(path: receipt.imagePath!),
                const SizedBox(height: 16),
              ],
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(alpha: 0.7),
                  ),
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
                              Text(
                                receipt.displayMerchant,
                                style: theme.textTheme.titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 2),
                              Text(
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
                    Text(
                      formatYen(receipt.totalAmount),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: theme.colorScheme.primary,
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
                        Chip(
                          visualDensity: VisualDensity.compact,
                          label: Text(
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
                title: '金額の内訳',
                children: <Widget>[
                  _InfoRow(
                    label: '合計（税込）',
                    value: formatYen(receipt.totalAmount),
                    emphasized: true,
                  ),
                  if (receipt.subtotalAmount != null)
                    _InfoRow(
                      label: '小計（税抜）',
                      value: formatYen(receipt.subtotalAmount!),
                    ),
                  if (receipt.tax8Amount != null)
                    _InfoRow(
                      label: '消費税 8%${receipt.tax8Base != null ? '（対象 ${formatYen(receipt.tax8Base!)}）' : ''}',
                      value: formatYen(receipt.tax8Amount!),
                    ),
                  if (receipt.tax10Amount != null)
                    _InfoRow(
                      label: '消費税 10%${receipt.tax10Base != null ? '（対象 ${formatYen(receipt.tax10Base!)}）' : ''}',
                      value: formatYen(receipt.tax10Amount!),
                    ),
                  if (receipt.hasTaxBreakdown)
                    _InfoRow(
                      label: '消費税合計',
                      value: formatYen(receipt.taxTotal),
                    ),
                  if (receipt.tax8ItemsTotal != null)
                    _InfoRow(
                      label: '8%対象商品の合計（推定）',
                      value: formatYen(receipt.tax8ItemsTotal!),
                    ),
                  if (receipt.tax10ItemsTotal != null)
                    _InfoRow(
                      label: '10%対象商品の合計（推定）',
                      value: formatYen(receipt.tax10ItemsTotal!),
                    ),
                ],
              ),
              if (receipt.items.isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: '明細（商品）',
                  children: <Widget>[
                    for (final item in receipt.items)
                      ReceiptItemRow(item: item),
                  ],
                ),
              ],
              if (receipt.dueDate != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: '支払期限',
                  children: <Widget>[
                    _DueDateRow(dueDate: receipt.dueDate!),
                    if (receipt.reminderAt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
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
                  title: 'ポイント',
                  children: <Widget>[
                    _InfoRow(
                      label: receipt.pointBrand ?? 'ポイント',
                      value: '${receipt.pointAmount} pt',
                      emphasized: true,
                    ),
                  ],
                ),
              ],
              if (receipt.barcodeId != null) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'バーコード / 請求番号',
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
                          tooltip: 'コピー',
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(text: receipt.barcodeId!),
                            );
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('コピーしました')),
                            );
                          },
                          icon: const Icon(Icons.copy_all_outlined, size: 18),
                        ),
                      ],
                    ),
                    if (BarcodeUtils.looksLikeJan(receipt.barcodeId!) &&
                        !BarcodeUtils.isValidEan13(receipt.barcodeId!))
                      Text(
                        'JAN-13 のチェックディジットが一致しません。読み取り値を確認してください。',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                  ],
                ),
              ],
              if ((receipt.note ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'メモ',
                  children: <Widget>[
                    Text(
                      receipt.note!.trim(),
                      style: theme.textTheme.bodyMedium?.copyWith(height: 1.5),
                    ),
                  ],
                ),
              ],
              if ((receipt.rawOcrText ?? '').trim().isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                _InfoCard(
                  title: 'OCRテキスト',
                  children: <Widget>[
                    ExpansionTile(
                      tilePadding: EdgeInsets.zero,
                      childrenPadding: EdgeInsets.zero,
                      title: Text(
                        '原本を表示',
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
              Text(
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

class _ReceiptImage extends ConsumerWidget {
  const _ReceiptImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final url = ref.watch(signedImageUrlProvider(path));

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 280,
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: url.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: Text('画像を読み込めませんでした', style: theme.textTheme.bodySmall),
          ),
          data: (value) => InkWell(
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => Dialog(
                insetPadding: const EdgeInsets.all(16),
                child: InteractiveViewer(
                  maxScale: 4,
                  child: StoredImage(url: value, fit: BoxFit.contain),
                ),
              ),
            ),
            child: StoredImage(
              url: value,
              fit: BoxFit.cover,
              width: double.infinity,
            ),
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
      color = theme.colorScheme.error;
      label = '\${-days} 日過ぎています';
    } else if (days == 0) {
      color = theme.colorScheme.error;
      label = '今日が期限です';
    } else if (days <= 3) {
      color = const Color(0xFFEF6C00);
      label = 'あと \$days 日';
    } else {
      color = theme.colorScheme.primary;
      label = 'あと \$days 日';
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
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
          child: Text(
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
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: emphasized
                ? theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
