import '../parser/receipt_parser.dart';
import 'receipt.dart';
import 'receipt_item.dart';

/// Editable receipt payload that is produced by the scanner / parser and
/// committed from the review screen.
class ReceiptDraft {
  ReceiptDraft({
    this.id,
    this.merchant,
    DateTime? purchasedAt,
    this.totalAmount = 0,
    this.subtotalAmount,
    this.tax8Amount,
    this.tax10Amount,
    this.tax8Base,
    this.tax10Base,
    this.tax8ItemsTotal,
    this.tax10ItemsTotal,
    this.dueDate,
    this.reminderAt,
    this.pointBrand,
    this.pointAmount,
    this.barcodeId,
    this.categoryId,
    this.note,
    this.imageBase64,
    this.rawOcrText,
    this.items = const <ReceiptItem>[],
    this.source = ReceiptSource.manual,
  }) : purchasedAt = purchasedAt ?? DateTime.now();

  final String? id;
  final String? merchant;
  final DateTime purchasedAt;
  final int totalAmount;
  final int? subtotalAmount;
  final int? tax8Amount;
  final int? tax10Amount;
  final int? tax8Base;
  final int? tax10Base;
  final int? tax8ItemsTotal;
  final int? tax10ItemsTotal;
  final DateTime? dueDate;
  final DateTime? reminderAt;
  final String? pointBrand;
  final int? pointAmount;
  final String? barcodeId;
  final String? categoryId;
  final String? note;
  final String? imageBase64;
  final String? rawOcrText;
  final List<ReceiptItem> items;
  final ReceiptSource source;

  /// Builds a draft from OCR output. [barcodeId] wins over the parsed value.
  factory ReceiptDraft.fromParsed(
    ParsedReceipt parsed, {
    String? barcodeId,
    ReceiptSource source = ReceiptSource.ocr,
  }) {
    final resolvedBarcode = (barcodeId != null && barcodeId.trim().isNotEmpty)
        ? barcodeId.trim()
        : parsed.barcodeId;
    return ReceiptDraft(
      merchant: parsed.merchant,
      purchasedAt: parsed.purchasedAt,
      totalAmount: parsed.totalAmount ?? 0,
      subtotalAmount: parsed.subtotalAmount,
      tax8Amount: parsed.tax8Amount,
      tax10Amount: parsed.tax10Amount,
      tax8Base: parsed.tax8Base,
      tax10Base: parsed.tax10Base,
      tax8ItemsTotal: parsed.tax8ItemsTotal,
      tax10ItemsTotal: parsed.tax10ItemsTotal,
      dueDate: parsed.dueDate,
      reminderAt: parsed.dueDate?.subtract(const Duration(days: 3)),
      pointBrand: parsed.pointBrand,
      pointAmount: parsed.pointAmount,
      barcodeId: resolvedBarcode,
      rawOcrText: parsed.rawText,
      items: <ReceiptItem>[
        for (var i = 0; i < parsed.items.length; i++)
          ReceiptItem(
            name: parsed.items[i].name,
            quantity: parsed.items[i].quantity,
            unitPrice: parsed.items[i].unitPrice,
            totalPrice: parsed.items[i].totalPrice,
            taxRate: parsed.items[i].taxRate,
            sortOrder: i,
          ),
      ],
      source: source,
    );
  }

  factory ReceiptDraft.fromReceipt(Receipt receipt) {
    return ReceiptDraft(
      id: receipt.id,
      merchant: receipt.merchant,
      purchasedAt: receipt.purchasedAt,
      totalAmount: receipt.totalAmount,
      subtotalAmount: receipt.subtotalAmount,
      tax8Amount: receipt.tax8Amount,
      tax10Amount: receipt.tax10Amount,
      tax8Base: receipt.tax8Base,
      tax10Base: receipt.tax10Base,
      tax8ItemsTotal: receipt.tax8ItemsTotal,
      tax10ItemsTotal: receipt.tax10ItemsTotal,
      dueDate: receipt.dueDate,
      reminderAt: receipt.reminderAt,
      pointBrand: receipt.pointBrand,
      pointAmount: receipt.pointAmount,
      barcodeId: receipt.barcodeId,
      categoryId: receipt.categoryId,
      note: receipt.note,
      imageBase64: receipt.imageBase64,
      rawOcrText: receipt.rawOcrText,
      items: receipt.items,
      source: receipt.source,
    );
  }

  int get taxTotal => (tax8Amount ?? 0) + (tax10Amount ?? 0);

  int get itemsTotal =>
      items.fold<int>(0, (sum, item) => sum + item.totalPrice);

  /// Receipt fields for Firestore. Items are embedded in the same document.
  Map<String, dynamic> toRow({bool includeItems = false}) =>
      <String, dynamic>{
        'merchant': (merchant ?? '').trim().isEmpty ? null : merchant!.trim(),
        'purchased_at': purchasedAt.toUtc().toIso8601String(),
        'total_amount': totalAmount,
        'subtotal_amount': subtotalAmount,
        'tax_8_amount': tax8Amount,
        'tax_10_amount': tax10Amount,
        'tax_8_base': tax8Base,
        'tax_10_base': tax10Base,
        'tax_8_items_total': tax8ItemsTotal,
        'tax_10_items_total': tax10ItemsTotal,
        'due_date': dueDate?.toUtc().toIso8601String(),
        'reminder_at': reminderAt?.toUtc().toIso8601String(),
        'point_brand': pointBrand,
        'point_amount': pointAmount,
        'barcode_id': (barcodeId ?? '').trim().isEmpty ? null : barcodeId!.trim(),
        'category_id': categoryId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'source': source.name,
        'raw_ocr_text': rawOcrText,
        'image_base64': imageBase64,
        if (includeItems)
          'items': <Map<String, dynamic>>[
            for (var i = 0; i < items.length; i++)
              <String, dynamic>{
                ...items[i].toJson(),
                'sort_order': i,
              },
          ],
      };
}
