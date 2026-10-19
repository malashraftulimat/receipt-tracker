import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/formatters.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/services/image_input.dart';
import '../../domain/models/category.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/parser/receipt_parser.dart';
import '../dashboard/analytics_provider.dart';

/// Arguments passed through `context.push('/review', extra: ...)`.
class ReviewArgs {
  const ReviewArgs({
    this.draft,
    this.existing,
    this.imageBytes,
    this.parsed,
  });

  /// Draft produced by the scanner (new receipt).
  final ReceiptDraft? draft;

  /// When editing an existing receipt.
  final Receipt? existing;

  /// Captured photo (not yet uploaded).
  final Uint8List? imageBytes;

  /// Raw parser output, used to display warnings / confidence.
  final ParsedReceipt? parsed;
}

class ReviewPage extends ConsumerStatefulWidget {
  const ReviewPage({super.key, required this.args});

  final ReviewArgs args;

  @override
  ConsumerState<ReviewPage> createState() => _ReviewPageState();
}

class _ReviewPageState extends ConsumerState<ReviewPage> {
  final _formKey = GlobalKey<FormState>();

  late final ReceiptDraft? _initial;
  late final TextEditingController _merchant;
  late final TextEditingController _total;
  late final TextEditingController _subtotal;
  late final TextEditingController _tax8;
  late final TextEditingController _tax10;
  late final TextEditingController _barcode;
  late final TextEditingController _note;

  late DateTime _purchasedAt;
  String? _categoryId;
  int? _tax8Base;
  int? _tax10Base;
  Uint8List? _imageBytes;
  String? _imagePath;
  String? _rawOcrText;
  ReceiptSource _source = ReceiptSource.manual;
  List<String> _warnings = const <String>[];

  bool _saving = false;
  bool _recognizing = false;
  String? _error;
  String? _duplicateId;

  String? get _existingId => widget.args.existing?.id;

  @override
  void initState() {
    super.initState();
    final existing = widget.args.existing;
    _initial = widget.args.draft ??
        (existing != null ? ReceiptDraft.fromReceipt(existing) : null);
    final draft = _initial;

    _merchant = TextEditingController(text: draft?.merchant ?? '');
    _total = TextEditingController(
      text: (draft?.totalAmount ?? 0) > 0
          ? formatAmountDigits(draft!.totalAmount)
          : '',
    );
    _subtotal = TextEditingController(
      text: draft?.subtotalAmount == null
          ? ''
          : formatAmountDigits(draft!.subtotalAmount!),
    );
    _tax8 = TextEditingController(
      text: draft?.tax8Amount == null
          ? ''
          : formatAmountDigits(draft!.tax8Amount!),
    );
    _tax10 = TextEditingController(
      text: draft?.tax10Amount == null
          ? ''
          : formatAmountDigits(draft!.tax10Amount!),
    );
    _barcode = TextEditingController(text: draft?.barcodeId ?? '');
    _note = TextEditingController(text: draft?.note ?? '');

    _purchasedAt = draft?.purchasedAt ?? DateTime.now();
    _categoryId = draft?.categoryId;
    _tax8Base = draft?.tax8Base;
    _tax10Base = draft?.tax10Base;
    _imageBytes = widget.args.imageBytes;
    _imagePath = draft?.imagePath;
    _rawOcrText = draft?.rawOcrText;
    _source = draft?.source ?? ReceiptSource.manual;
    _warnings = widget.args.parsed?.warnings ?? const <String>[];

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDuplicate());
  }

  @override
  void dispose() {
    _merchant.dispose();
    _total.dispose();
    _subtotal.dispose();
    _tax8.dispose();
    _tax10.dispose();
    _barcode.dispose();
    _note.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Duplicate guard
  // -------------------------------------------------------------------------

  Future<void> _checkDuplicate() async {
    final barcode = _barcode.text.trim();
    if (barcode.isEmpty) {
      if (mounted) setState(() => _duplicateId = null);
      return;
    }
    try {
      final existingId =
          await ref.read(receiptRepositoryProvider).findIdByBarcode(barcode);
      if (!mounted) return;
      setState(() {
        _duplicateId = existingId == null || existingId == _existingId
            ? null
            : existingId;
      });
    } catch (_) {
      // Offline / permission errors are surfaced on save instead.
    }
  }

  // -------------------------------------------------------------------------
  // Re-run OCR
  // -------------------------------------------------------------------------

  Future<void> _recognizeAgain() async {
    if (_recognizing) return;
    setState(() {
      _recognizing = true;
      _error = null;
    });

    try {
      final file = await ImageInput.pickReceiptImage();
      if (file == null) return;

      final bytes = await file.readAsBytes();
      final barcode = _barcode.text.trim().isEmpty ? null : _barcode.text.trim();
      final result = await ref.read(ocrServiceProvider).recognize(bytes);
      final parsed = const ReceiptParser().parse(
        result.text,
        scannedBarcode: barcode,
      );

      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _rawOcrText = result.text;
        _warnings = parsed.warnings;
        _source = barcode == null ? ReceiptSource.ocr : ReceiptSource.barcode;

        if ((parsed.merchant ?? '').isNotEmpty) {
          _merchant.text = parsed.merchant!;
        }
        if (parsed.purchasedAt != null) _purchasedAt = parsed.purchasedAt!;
        if (parsed.totalAmount != null) {
          _total.text = formatAmountDigits(parsed.totalAmount!);
        }
        if (parsed.subtotalAmount != null) {
          _subtotal.text = formatAmountDigits(parsed.subtotalAmount!);
        }
        if (parsed.tax8Amount != null) {
          _tax8.text = formatAmountDigits(parsed.tax8Amount!);
        }
        if (parsed.tax10Amount != null) {
          _tax10.text = formatAmountDigits(parsed.tax10Amount!);
        }
        _tax8Base = parsed.tax8Base ?? _tax8Base;
        _tax10Base = parsed.tax10Base ?? _tax10Base;
        if (parsed.barcodeId != null && _barcode.text.trim().isEmpty) {
          _barcode.text = parsed.barcodeId!;
        }
      });
      await _checkDuplicate();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _recognizing = false);
    }
  }

  // -------------------------------------------------------------------------
  // Save
  // -------------------------------------------------------------------------

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_duplicateId != null) return;

    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    setState(() {
      _saving = true;
      _error = null;
    });

    final repository = ref.read(receiptRepositoryProvider);
    final storage = ref.read(storageRepositoryProvider);

    final draft = ReceiptDraft(
      merchant: _merchant.text,
      purchasedAt: _purchasedAt,
      totalAmount: parseYenInput(_total.text) ?? 0,
      subtotalAmount: parseYenInput(_subtotal.text),
      tax8Amount: parseYenInput(_tax8.text),
      tax10Amount: parseYenInput(_tax10.text),
      tax8Base: _tax8Base,
      tax10Base: _tax10Base,
      barcodeId: _barcode.text,
      categoryId: _categoryId,
      note: _note.text,
      imagePath: _imagePath,
      rawOcrText: _rawOcrText,
      source: _source,
    );

    try {
      String? imagePath = _imagePath;
      if (_imageBytes != null) {
        imagePath = await storage.uploadReceiptImage(userId, _imageBytes!);
      }

      final Receipt saved;
      if (_existingId != null) {
        saved = await repository.update(
          _existingId!,
          <String, dynamic>{
            ...draft.toRow(),
            'image_path': imagePath,
          },
        );
      } else {
        saved = await repository.create(draft, imagePath: imagePath);
      }

      if (!mounted) return;
      ref.invalidate(receiptsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(receiptByIdProvider(saved.id));
      setState(() => _saving = false);
      context.pop(saved);
    } on DuplicateReceiptException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _duplicateId = error.existingId;
        _error = '同じバーコードのレシートが既に登録されています。';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '保存に失敗しました: $error';
      });
    }
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (_initial == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('内容の確認')),
        body: const Center(child: Text('読み取りデータがありません。')),
      );
    }

    final expanded = context.isExpanded;

    return Scaffold(
      appBar: AppBar(
        title: Text(_existingId == null ? '内容の確認' : 'レシートを編集'),
        actions: <Widget>[
          if (_imageBytes != null || _imagePath != null)
            IconButton(
              tooltip: '画像を撮り直す',
              onPressed: _recognizing ? null : _recognizeAgain,
              icon: const Icon(Icons.document_scanner_outlined),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: expanded
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 400,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(24, 8, 12, 24),
                        child: _ImagePanel(
                          bytes: _imageBytes,
                          path: _imagePath,
                          busy: _recognizing,
                          onCapture: _recognizeAgain,
                        ),
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 24, 120),
                        child: _buildForm(context),
                      ),
                    ),
                  ],
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      _ImagePanel(
                        bytes: _imageBytes,
                        path: _imagePath,
                        busy: _recognizing,
                        onCapture: _recognizeAgain,
                      ),
                      const SizedBox(height: 14),
                      _buildForm(context),
                    ],
                  ),
                ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            context.pagePadding,
            8,
            context.pagePadding,
            12,
          ),
          child: FilledButton.icon(
            onPressed: _saving || _duplicateId != null ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(
              _duplicateId != null
                  ? '重複のため保存できません'
                  : (_existingId == null ? '保存する' : '変更を保存'),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(BuildContext context) {
    final theme = Theme.of(context);
    final categories =
        ref.watch(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (_warnings.isNotEmpty) ...<Widget>[
          _WarningCard(warnings: _warnings),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...<Widget>[
          _ErrorCard(message: _error!),
          const SizedBox(height: 12),
        ],
        if (_duplicateId != null) ...<Widget>[
          _DuplicateCard(
            onOpen: () => context.push('/receipt/$_duplicateId'),
          ),
          const SizedBox(height: 12),
        ],
        _Section(
          title: '基本情報',
          children: <Widget>[
            TextFormField(
              controller: _merchant,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: '店舗名・取引先',
                prefixIcon: Icon(Icons.storefront_outlined),
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? '店舗名を入力してください' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      formatDateJa(_purchasedAt),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.schedule, size: 18),
                  label: Text(formatTimeJa(_purchasedAt)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _checkDuplicate(),
              decoration: InputDecoration(
                labelText: 'バーコード / 請求番号',
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: _barcode.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'クリア',
                        onPressed: () {
                          _barcode.clear();
                          _checkDuplicate();
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'カテゴリ',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                ChoiceChip(
                  label: const Text('未分類'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                for (final category in categories)
                  ChoiceChip(
                    avatar: Icon(
                      category.iconData,
                      size: 16,
                      color: _categoryId == category.id
                          ? Colors.white
                          : category.colorValue,
                    ),
                    label: Text(category.name),
                    selected: _categoryId == category.id,
                    selectedColor: category.colorValue,
                    labelStyle: TextStyle(
                      color: _categoryId == category.id
                          ? Colors.white
                          : theme.colorScheme.onSurface,
                      fontSize: 12.5,
                    ),
                    onSelected: (_) =>
                        setState(() => _categoryId = category.id),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: '金額（税込・円）',
          children: <Widget>[
            TextFormField(
              controller: _total,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
              ],
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: const InputDecoration(
                labelText: '合計金額',
                prefixText: '¥ ',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return '合計金額を入力してください';
                if (parseYenInput(value!) == null) return '数字で入力してください';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: _AmountField(
                    controller: _subtotal,
                    label: '小計（税抜）',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AmountField(controller: _tax8, label: '消費税 8%'),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AmountField(controller: _tax10, label: '消費税 10%'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _TaxSummary(
              tax8: parseYenInput(_tax8.text),
              tax10: parseYenInput(_tax10.text),
              subtotal: parseYenInput(_subtotal.text),
              total: parseYenInput(_total.text),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: 'メモ',
          children: <Widget>[
            TextFormField(
              controller: _note,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(
                hintText: '用途や補足（例: 友人との昼食、備品購入）',
              ),
            ),
          ],
        ),
        if (_rawOcrText != null && _rawOcrText!.trim().isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          _Section(
            title: 'OCRテキスト（原本）',
            children: <Widget>[
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: EdgeInsets.zero,
                title: Text(
                  '${_rawOcrText!.split('\n').length} 行を表示',
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
                      _rawOcrText!,
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
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchasedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '日付を選択',
      locale: const Locale('ja'),
    );
    if (picked == null) return;
    setState(() {
      _purchasedAt = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _purchasedAt.hour,
        _purchasedAt.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_purchasedAt),
      helpText: '時刻を選択',
    );
    if (picked == null) return;
    setState(() {
      _purchasedAt = DateTime(
        _purchasedAt.year,
        _purchasedAt.month,
        _purchasedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }
}

// ---------------------------------------------------------------------------
// Small widgets
// ---------------------------------------------------------------------------

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

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
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _AmountField extends StatelessWidget {
  const _AmountField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixText: '¥ ',
      ),
    );
  }
}

class _TaxSummary extends StatelessWidget {
  const _TaxSummary({
    required this.tax8,
    required this.tax10,
    required this.subtotal,
    required this.total,
  });

  final int? tax8;
  final int? tax10;
  final int? subtotal;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taxTotal = (tax8 ?? 0) + (tax10 ?? 0);
    final messages = <String>[];

    if (total != null && subtotal != null && taxTotal > 0) {
      final expected = subtotal! + taxTotal;
      if ((expected - total!).abs() > 1) {
        messages.add(
          '小計 + 消費税 = ${formatYen(expected)} と合計 ${formatYen(total!)} が一致しません。',
        );
      }
    }
    if (total != null && taxTotal > total!) {
      messages.add('消費税が合計金額を超えています。');
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          messages.isEmpty ? Icons.check_circle_outline : Icons.info_outline,
          size: 16,
          color: messages.isEmpty
              ? theme.colorScheme.primary
              : theme.colorScheme.error,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            messages.isEmpty
                ? '税額合計 ${formatYen(taxTotal)}'
                : messages.join(' / '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: messages.isEmpty
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.error,
            ),
          ),
        ),
      ],
    );
  }
}

class _WarningCard extends StatelessWidget {
  const _WarningCard({required this.warnings});

  final List<String> warnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.warning_amber_rounded, size: 18),
              const SizedBox(width: 6),
              Text(
                '読み取り結果を確認してください',
                style: theme.textTheme.labelLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          for (final warning in warnings)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                '・$warning',
                style: theme.textTheme.bodySmall,
              ),
            ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(
          fontSize: 12.5,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
    );
  }
}

class _DuplicateCard extends StatelessWidget {
  const _DuplicateCard({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: <Widget>[
          Icon(
            Icons.content_copy,
            size: 18,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'このバーコードは登録済みです（二重登録を防止しています）。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onOpen, child: const Text('開く')),
        ],
      ),
    );
  }
}

class _ImagePanel extends ConsumerWidget {
  const _ImagePanel({
    required this.bytes,
    required this.path,
    required this.busy,
    required this.onCapture,
  });

  final Uint8List? bytes;
  final String? path;
  final bool busy;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget content;
    if (bytes != null) {
      content = Image.memory(bytes!, fit: BoxFit.cover);
    } else if (path != null) {
      final url = ref.watch(signedImageUrlProvider(path!));
      content = url.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            '画像を読み込めませんでした',
            style: theme.textTheme.bodySmall,
          ),
        ),
        data: (value) => Image.network(value, fit: BoxFit.cover),
      );
    } else {
      content = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.image_outlined,
              size: 36,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(height: 8),
            Text(
              'レシート画像は未添付です',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: Container(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              child: content,
            ),
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: busy ? null : onCapture,
          icon: busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.document_scanner_outlined, size: 18),
          label: Text(
            busy
                ? '読み取り中…'
                : (bytes == null && path == null
                    ? 'レシートを撮影して自動入力'
                    : '撮り直して再読み取り'),
          ),
        ),
      ],
    );
  }
}
