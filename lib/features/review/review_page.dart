import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/language_switcher.dart';
import '../../core/widgets/press_scale.dart';
import '../../core/utils/responsive.dart';
import '../../data/providers.dart';
import '../../data/repositories/receipt_repository.dart';
import '../../data/services/image_input.dart';
import '../../domain/models/category.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_item.dart';
import '../../domain/parser/category_guesser.dart';
import '../../domain/parser/receipt_parser.dart';
import 'widgets/item_editor_section.dart';
import '../dashboard/analytics_provider.dart';
import '../../core/localization/localization.dart';

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
  final List<ReceiptItemEditor> _items = <ReceiptItemEditor>[];
  bool _autoTagged = false;

  late final ReceiptDraft? _initial;
  late final TextEditingController _merchant;
  late final TextEditingController _currency;
  late final TextEditingController _total;
  late final TextEditingController _subtotal;
  late final TextEditingController _tax8;
  late final TextEditingController _tax10;
  late final TextEditingController _barcode;
  late final TextEditingController _note;
  late final TextEditingController _pointBrand;
  late final TextEditingController _pointAmount;

  late DateTime _purchasedAt;
  String? _categoryId;
  String? _suggestedCategory;

  /// Coupon printed on the receipt; saved alongside a new receipt.
  ParsedCoupon? _coupon;
  double? _tax8Base;
  double? _tax10Base;
  double? _tax8ItemsTotal;
  double? _tax10ItemsTotal;
  DateTime? _dueDate;

  /// In-memory only. Never written to Firestore or local storage.
  Uint8List? _imageBytes;
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
    _currency = TextEditingController(
      text: (draft?.currency ?? 'JPY').toUpperCase(),
    );
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
    _pointBrand = TextEditingController(text: draft?.pointBrand ?? '');
    _pointAmount = TextEditingController(
      text: draft?.pointAmount == null
          ? ''
          : formatAmountDigits(draft!.pointAmount!),
    );

    _purchasedAt = draft?.purchasedAt ?? DateTime.now();
    _categoryId = draft?.categoryId;
    _suggestedCategory = widget.args.parsed?.suggestedCategory;
    _coupon = widget.args.parsed?.coupon;
    _tax8Base = draft?.tax8Base;
    _tax10Base = draft?.tax10Base;
    _tax8ItemsTotal = draft?.tax8ItemsTotal;
    _tax10ItemsTotal = draft?.tax10ItemsTotal;
    _dueDate = draft?.dueDate;
    _imageBytes = widget.args.imageBytes;
    _rawOcrText = draft?.rawOcrText;
    _source = draft?.source ?? ReceiptSource.manual;
    _warnings = widget.args.parsed?.warnings ?? const <String>[];
    for (final item in draft?.items ?? const <ReceiptItem>[]) {
      _items.add(ReceiptItemEditor(item: item));
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _checkDuplicate());
  }

  @override
  void dispose() {
    _merchant.dispose();
    _currency.dispose();
    _total.dispose();
    _subtotal.dispose();
    _tax8.dispose();
    _tax10.dispose();
    _barcode.dispose();
    _note.dispose();
    _pointBrand.dispose();
    _pointAmount.dispose();
    for (final item in _items) {
      item.dispose();
    }
    // Drop the captured photo when the review screen is closed.
    _imageBytes = null;
    super.dispose();
  }

  void _addItem() {
    setState(() => _items.add(ReceiptItemEditor()));
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  void _matchTotalToItems() {
    final itemsTotal = _items.fold<double>(
      0,
      (sum, item) => sum + item.totalValue,
    );
    if (itemsTotal > 0) {
      _total.text = formatAmountDigits(itemsTotal);
    }
  }

  /// Suggests categories from item names / merchant when none is chosen.
  void _autoTagItems(List<ExpenseCategory> categories) {
    if (categories.isEmpty) return;
    String? idFor(String? name) {
      if (name == null) return null;
      for (final category in categories) {
        if (category.name == name) return category.id;
      }
      return null;
    }

    var changed = false;
    final suggested = idFor(_suggestedCategory);
    if (_categoryId == null && suggested != null) {
      _categoryId = suggested;
      changed = true;
    } else {
      final guessed = CategoryGuesser.guessFromMany(<String>[
        _merchant.text,
        for (final item in _items) item.name.text,
      ]);
      final receiptCategory = idFor(guessed);
      if (_categoryId == null && receiptCategory != null) {
        _categoryId = receiptCategory;
        changed = true;
      }
    }

    for (final item in _items) {
      if (item.categoryId != null) continue;
      final itemCategory = idFor(CategoryGuesser.guess(item.name.text));
      if (itemCategory != null) {
        item.categoryId = itemCategory;
        changed = true;
      }
    }

    if (changed && mounted) setState(() {});
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
        _duplicateId =
            existingId == null || existingId == _existingId ? null : existingId;
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
      final barcode =
          _barcode.text.trim().isEmpty ? null : _barcode.text.trim();
      final result = await ref
          .read(receiptOcrPipelineProvider)
          .recognize(bytes, barcodeId: barcode);
      final parsed = result.parsed;

      if (!mounted) return;
      final oldItems = List<ReceiptItemEditor>.of(_items);
      final extractedItems = <ReceiptItemEditor>[
        for (final item in parsed.items)
          ReceiptItemEditor(
            item: ReceiptItem(
              name: item.name,
              quantity: item.quantity,
              unitPrice: item.unitPrice,
              totalPrice: item.totalPrice,
              taxRate: item.taxRate,
            ),
          ),
      ];
      setState(() {
        _imageBytes = bytes;
        _rawOcrText = parsed.rawText;
        _warnings = parsed.warnings;
        _suggestedCategory = parsed.suggestedCategory;
        _coupon = parsed.coupon;
        if (parsed.suggestedCategory != null) _categoryId = null;
        _source = barcode == null ? ReceiptSource.ocr : ReceiptSource.barcode;

        if ((parsed.merchant ?? '').isNotEmpty) {
          _merchant.text = parsed.merchant!;
        }
        if ((parsed.currency ?? '').trim().isNotEmpty) {
          _currency.text = parsed.currency!.trim().toUpperCase();
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
        _tax8ItemsTotal = parsed.tax8ItemsTotal;
        _tax10ItemsTotal = parsed.tax10ItemsTotal;
        if (parsed.barcodeId != null && _barcode.text.trim().isEmpty) {
          _barcode.text = parsed.barcodeId!;
        }
        _items
          ..clear()
          ..addAll(extractedItems);
      });
      for (final item in oldItems) {
        item.dispose();
      }
      final categories =
          ref.read(categoriesProvider).valueOrNull ?? const <ExpenseCategory>[];
      if (mounted && categories.isNotEmpty) _autoTagItems(categories);
      if (result.usedFallback) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: result.aiKeyMissing
                ? const AppText('AI key missing — using on-device OCR.')
                : result.aiServiceUnavailable
                    ? const AppText(
                        'AIサービスを準備しています。しばらくしてからお試しください。',
                      )
                    : const AppText(
                        'AIを利用できないため、端末内OCRで読み取りました。',
                      ),
          ),
        );
      }
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

    final items = <ReceiptItem>[
      for (var i = 0; i < _items.length; i++)
        if (_items[i].name.text.trim().isNotEmpty) _items[i].toItem(i),
    ];
    final itemsTax8 = items
        .where((item) => item.taxRate == 8)
        .fold<double>(0, (sum, item) => sum + item.totalPrice);
    final itemsTax10 = items
        .where((item) => item.taxRate == 10)
        .fold<double>(0, (sum, item) => sum + item.totalPrice);

    final draft = ReceiptDraft(
      merchant: _merchant.text,
      currency: _currency.text.trim().isEmpty
          ? 'JPY'
          : _currency.text.trim().toUpperCase(),
      purchasedAt: _purchasedAt,
      totalAmount: parseAmountInput(_total.text) ?? 0,
      subtotalAmount: parseAmountInput(_subtotal.text),
      tax8Amount: parseAmountInput(_tax8.text),
      tax10Amount: parseAmountInput(_tax10.text),
      tax8Base: _tax8Base,
      tax10Base: _tax10Base,
      tax8ItemsTotal: items.isEmpty ? _tax8ItemsTotal : itemsTax8,
      tax10ItemsTotal: items.isEmpty ? _tax10ItemsTotal : itemsTax10,
      dueDate: _dueDate,
      reminderAt: _dueDate?.subtract(const Duration(days: 3)),
      pointBrand: _pointBrand.text.trim().isEmpty ? null : _pointBrand.text,
      pointAmount: parseYenInput(_pointAmount.text),
      barcodeId: _barcode.text,
      categoryId: _categoryId,
      note: _note.text,
      rawOcrText: _rawOcrText,
      items: items,
      source: _source,
    );

    try {
      final Receipt saved;
      if (_existingId != null) {
        saved = await repository.update(
          _existingId!,
          <String, dynamic>{
            ...draft.toRow(includeItems: true),
          },
          items: items,
        );
      } else {
        saved = await repository.create(draft);
      }

      // A coupon printed on a newly scanned receipt becomes a tracked coupon.
      if (_existingId == null && _coupon != null) {
        try {
          await ref.read(couponRepositoryProvider).createFromParsed(
                _coupon!,
                receiptId: saved.id,
                merchant: saved.merchant,
              );
          ref.invalidate(couponsProvider);
          await ref.read(couponReminderServiceProvider).sync();
        } catch (error) {
          debugPrint('[ReviewPage] coupon save failed: $error');
        }
      }

      if (!mounted) return;
      ref.invalidate(receiptsProvider);
      ref.invalidate(analyticsProvider);
      ref.invalidate(receiptByIdProvider(saved.id));
      ref.invalidate(upcomingDueProvider);
      ref.invalidate(
        budgetSummaryProvider(
          DateTime(saved.purchasedAt.year, saved.purchasedAt.month),
        ),
      );
      setState(() {
        _saving = false;
        _imageBytes = null;
      });
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
        appBar: AppBar(
          title: const AppText('内容の確認'),
          actions: headerActions(
            context,
            showLanguageLabel: context.isExpanded,
          ),
        ),
        body: const Center(child: AppText('読み取りデータがありません。')),
      );
    }

    final expanded = context.isExpanded;

    return Scaffold(
      appBar: AppBar(
        title: AppText(_existingId == null ? '内容の確認' : 'レシートを編集'),
        actions: headerActions(
          context,
          showLanguageLabel: expanded,
          actions: <Widget>[
            if (_imageBytes != null)
              IconButton(
                tooltip: context.tr('画像を撮り直す'),
                onPressed: _recognizing ? null : _recognizeAgain,
                icon: const Icon(Icons.document_scanner_outlined),
              ),
          ],
        ),
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
          child: PressScale(
            child: FilledButton.icon(
              onPressed: _saving || _duplicateId != null ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppPalette.emerald,
                foregroundColor: AppPalette.backgroundDeep,
                minimumSize: const Size(0, 52),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: AppText(
                _duplicateId != null
                    ? '重複のため保存できません'
                    : (_existingId == null ? '保存する' : '変更を保存'),
              ),
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

    if (!_autoTagged && categories.isNotEmpty) {
      _autoTagged = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _autoTagItems(categories);
      });
    }

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
        ItemEditorSection(
          items: _items,
          categories: categories,
          totalAmount: parseAmountInput(_total.text) ?? 0,
          taxTotal: (parseAmountInput(_tax8.text) ?? 0) +
              (parseAmountInput(_tax10.text) ?? 0),
          currency: _currency.text.trim().isEmpty
              ? 'JPY'
              : _currency.text.trim().toUpperCase(),
          onAdd: _addItem,
          onRemove: _removeItem,
          onChanged: () => setState(() {}),
          onMatchTotal: _matchTotalToItems,
        ),
        const SizedBox(height: 14),
        _Section(
          title: '基本情報',
          children: <Widget>[
            TextFormField(
              controller: _merchant,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: context.tr('店舗名・取引先'),
                prefixIcon: const Icon(Icons.storefront_outlined),
              ),
              validator: (value) => (value ?? '').trim().isEmpty
                  ? context.tr('店舗名を入力してください')
                  : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: AppText(
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
                  label: AppText(formatTimeJa(_purchasedAt)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _barcode,
              textInputAction: TextInputAction.next,
              onChanged: (_) => _checkDuplicate(),
              decoration: InputDecoration(
                labelText: context.tr('バーコード / 請求番号'),
                prefixIcon: const Icon(Icons.qr_code_2),
                suffixIcon: _barcode.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: context.tr('クリア'),
                        onPressed: () {
                          _barcode.clear();
                          _checkDuplicate();
                        },
                        icon: const Icon(Icons.close, size: 18),
                      ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDueDate,
                    icon: const Icon(Icons.event_available_outlined, size: 18),
                    label: AppText(
                      _dueDate == null
                          ? '支払期限を設定（振込用紙）'
                          : '支払期限 ${formatDateShortJa(_dueDate!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (_dueDate != null)
                  IconButton(
                    tooltip: context.tr('支払期限をクリア'),
                    onPressed: () => setState(() => _dueDate = null),
                    icon: const Icon(Icons.close, size: 18),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    controller: _pointBrand,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: context.tr('ポイント種別'),
                      hintText: context.tr('dポイント / Ponta など'),
                      prefixIcon: const Icon(Icons.stars_outlined),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 130,
                  child: TextFormField(
                    controller: _pointAmount,
                    keyboardType: TextInputType.number,
                    inputFormatters: <TextInputFormatter>[
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9,]')),
                    ],
                    decoration: InputDecoration(
                      labelText: context.tr('ポイント数'),
                      suffixText: 'pt',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: AppText(
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
                  label: const AppText('未分類'),
                  selected: _categoryId == null,
                  onSelected: (_) => setState(() => _categoryId = null),
                ),
                for (final category in categories)
                  Builder(
                    builder: (context) {
                      final accent = AppPalette.categoryAccent(
                        category.name,
                        fallback: category.colorValue,
                      );
                      return ChoiceChip(
                        avatar: Icon(
                          category.iconData,
                          size: 16,
                          color: _categoryId == category.id
                              ? Colors.white
                              : accent,
                        ),
                        label: AppText(category.name),
                        selected: _categoryId == category.id,
                        selectedColor: accent,
                        labelStyle: TextStyle(
                          color: _categoryId == category.id
                              ? Colors.white
                              : theme.colorScheme.onSurface,
                          fontSize: 12.5,
                        ),
                        onSelected: (_) =>
                            setState(() => _categoryId = category.id),
                      );
                    },
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _Section(
          title: '金額（税込）',
          children: <Widget>[
            TextFormField(
              controller: _currency,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z]')),
                LengthLimitingTextInputFormatter(3),
              ],
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: context.tr('通貨（ISOコード）'),
                hintText: 'JPY / USD / SAR / EUR',
                prefixIcon: const Icon(Icons.currency_exchange_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _total,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              style: theme.textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                labelText: context.tr('合計金額'),
                prefixText:
                    '${currencySymbol(_currency.text.trim().isEmpty ? 'JPY' : _currency.text)} ',
                prefixIcon: const Icon(Icons.payments_outlined),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) {
                  return context.tr('合計金額を入力してください');
                }
                if (parseAmountInput(value!) == null) {
                  return context.tr('数字で入力してください');
                }
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
                    currency: _currency.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AmountField(
                    controller: _tax8,
                    label: '消費税 8%（任意）',
                    currency: _currency.text,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _AmountField(
                    controller: _tax10,
                    label: '消費税 10%（任意）',
                    currency: _currency.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _TaxSummary(
              tax8: parseAmountInput(_tax8.text),
              tax10: parseAmountInput(_tax10.text),
              subtotal: parseAmountInput(_subtotal.text),
              total: parseAmountInput(_total.text),
              currency: _currency.text.trim().isEmpty
                  ? 'JPY'
                  : _currency.text.trim().toUpperCase(),
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
              decoration: InputDecoration(
                hintText: context.tr('用途や補足（例: 友人との昼食、備品購入）'),
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
                title: AppText(
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

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now().add(const Duration(days: 14)),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
      helpText: context.tr('支払期限を選択'),
      locale: Localizations.localeOf(context),
    );
    if (picked == null) return;
    setState(() => _dueDate = picked);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchasedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: context.tr('日付を選択'),
      locale: Localizations.localeOf(context),
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
      helpText: context.tr('時刻を選択'),
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
          AppText(
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
  const _AmountField({
    required this.controller,
    required this.label,
    this.currency = 'JPY',
  });

  final TextEditingController controller;
  final String label;
  final String currency;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: <TextInputFormatter>[
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        prefixText:
            '${currencySymbol(currency.trim().isEmpty ? 'JPY' : currency)} ',
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
    this.currency = 'JPY',
  });

  final double? tax8;
  final double? tax10;
  final double? subtotal;
  final double? total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final taxTotal = (tax8 ?? 0) + (tax10 ?? 0);
    final messages = <String>[];

    if (total != null && subtotal != null && taxTotal > 0) {
      final expected = subtotal! + taxTotal;
      if ((expected - total!).abs() > 0.011) {
        messages.add(
          '小計 + 消費税 = ${formatMoney(expected, currency: currency)} と合計 ${formatMoney(total!, currency: currency)} が一致しません。',
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
          child: AppText(
            messages.isEmpty
                ? '税額合計 ${formatMoney(taxTotal, currency: currency)}'
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
              AppText(
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
              child: AppText(
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
      child: AppText(
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
            child: AppText(
              'このバーコードは登録済みです（二重登録を防止しています）。',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(onPressed: onOpen, child: const AppText('開く')),
        ],
      ),
    );
  }
}

class _ImagePanel extends ConsumerWidget {
  const _ImagePanel({
    required this.bytes,
    required this.busy,
    required this.onCapture,
  });

  final Uint8List? bytes;
  final bool busy;
  final VoidCallback onCapture;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    Widget content;
    if (bytes != null) {
      content = Image.memory(bytes!, fit: BoxFit.cover);
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
            AppText(
              'プレビューするレシート画像はありません',
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
          label: AppText(
            busy ? '読み取り中…' : (bytes == null ? 'レシートを撮影して自動入力' : '撮り直して再読み取り'),
          ),
        ),
      ],
    );
  }
}
