import '../parser/receipt_parser.dart';
import 'receipt.dart';

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
    this.barcodeId,
    this.categoryId,
    this.note,
    this.imagePath,
    this.rawOcrText,
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
  final String? barcodeId;
  final String? categoryId;
  final String? note;
  final String? imagePath;
  final String? rawOcrText;
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
      barcodeId: resolvedBarcode,
      rawOcrText: parsed.rawText,
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
      barcodeId: receipt.barcodeId,
      categoryId: receipt.categoryId,
      note: receipt.note,
      imagePath: receipt.imagePath,
      rawOcrText: receipt.rawOcrText,
      source: receipt.source,
    );
  }

  int get taxTotal => (tax8Amount ?? 0) + (tax10Amount ?? 0);

  Map<String, dynamic> toRow() => <String, dynamic>{
        'merchant': (merchant ?? '').trim().isEmpty ? null : merchant!.trim(),
        'purchased_at': purchasedAt.toUtc().toIso8601String(),
        'total_amount': totalAmount,
        'subtotal_amount': subtotalAmount,
        'tax_8_amount': tax8Amount,
        'tax_10_amount': tax10Amount,
        'tax_8_base': tax8Base,
        'tax_10_base': tax10Base,
        'barcode_id': (barcodeId ?? '').trim().isEmpty ? null : barcodeId!.trim(),
        'category_id': categoryId,
        'note': (note ?? '').trim().isEmpty ? null : note!.trim(),
        'source': source.name,
        'raw_ocr_text': rawOcrText,
      };
}
