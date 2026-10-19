import 'category.dart';

enum ReceiptSource { barcode, ocr, manual }

ReceiptSource receiptSourceFromString(String? value) {
  switch (value) {
    case 'barcode':
      return ReceiptSource.barcode;
    case 'ocr':
      return ReceiptSource.ocr;
    default:
      return ReceiptSource.manual;
  }
}

String receiptSourceLabel(ReceiptSource source) {
  switch (source) {
    case ReceiptSource.barcode:
      return 'バーコード';
    case ReceiptSource.ocr:
      return 'OCR';
    case ReceiptSource.manual:
      return '手入力';
  }
}

/// A saved receipt / invoice row.
class Receipt {
  const Receipt({
    required this.id,
    required this.userId,
    required this.purchasedAt,
    required this.totalAmount,
    this.merchant,
    this.subtotalAmount,
    this.tax8Amount,
    this.tax10Amount,
    this.tax8Base,
    this.tax10Base,
    this.barcodeId,
    this.categoryId,
    this.note,
    this.imagePath,
    this.source = ReceiptSource.manual,
    this.rawOcrText,
    required this.createdAt,
    required this.updatedAt,
    this.category,
  });

  final String id;
  final String userId;
  final String? merchant;
  final DateTime purchasedAt;

  /// Stored in JPY (integer yen).
  final int totalAmount;
  final int? subtotalAmount;
  final int? tax8Amount;
  final int? tax10Amount;
  final int? tax8Base;
  final int? tax10Base;

  /// JAN-13 / Code 128 value or invoice reference number.
  final String? barcodeId;
  final String? categoryId;
  final String? note;
  final String? imagePath;
  final ReceiptSource source;
  final String? rawOcrText;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Joined from `categories(*)`.
  final ExpenseCategory? category;

  int get taxTotal => (tax8Amount ?? 0) + (tax10Amount ?? 0);

  bool get hasTaxBreakdown => tax8Amount != null || tax10Amount != null;

  String get displayMerchant =>
      (merchant == null || merchant!.trim().isEmpty) ? '店舗名なし' : merchant!.trim();

  String get displayCategory => category?.name ?? '未分類';

  DateTime get monthStart => DateTime(purchasedAt.year, purchasedAt.month);

  factory Receipt.fromJson(Map<String, dynamic> json) {
    ExpenseCategory? category;
    final rawCategory = json['category'];
    if (rawCategory is Map) {
      category = ExpenseCategory.fromJson(Map<String, dynamic>.from(rawCategory));
    }
    return Receipt(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      merchant: json['merchant'] as String?,
      purchasedAt: _parseDate(json['purchased_at']) ?? DateTime.now(),
      totalAmount: (json['total_amount'] as num?)?.toInt() ?? 0,
      subtotalAmount: (json['subtotal_amount'] as num?)?.toInt(),
      tax8Amount: (json['tax_8_amount'] as num?)?.toInt(),
      tax10Amount: (json['tax_10_amount'] as num?)?.toInt(),
      tax8Base: (json['tax_8_base'] as num?)?.toInt(),
      tax10Base: (json['tax_10_base'] as num?)?.toInt(),
      barcodeId: json['barcode_id'] as String?,
      categoryId: json['category_id'] as String?,
      note: json['note'] as String?,
      imagePath: json['image_path'] as String?,
      source: receiptSourceFromString(json['source'] as String?),
      rawOcrText: json['raw_ocr_text'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      category: category,
    );
  }

  Receipt copyWith({
    String? merchant,
    DateTime? purchasedAt,
    int? totalAmount,
    int? subtotalAmount,
    int? tax8Amount,
    int? tax10Amount,
    String? barcodeId,
    String? categoryId,
    String? note,
    String? imagePath,
    ReceiptSource? source,
    String? rawOcrText,
    ExpenseCategory? category,
  }) {
    return Receipt(
      id: id,
      userId: userId,
      merchant: merchant ?? this.merchant,
      purchasedAt: purchasedAt ?? this.purchasedAt,
      totalAmount: totalAmount ?? this.totalAmount,
      subtotalAmount: subtotalAmount ?? this.subtotalAmount,
      tax8Amount: tax8Amount ?? this.tax8Amount,
      tax10Amount: tax10Amount ?? this.tax10Amount,
      tax8Base: tax8Base,
      tax10Base: tax10Base,
      barcodeId: barcodeId ?? this.barcodeId,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      imagePath: imagePath ?? this.imagePath,
      source: source ?? this.source,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      category: category ?? this.category,
    );
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return value.toLocal();
    return DateTime.tryParse(value.toString())?.toLocal();
  }
}
