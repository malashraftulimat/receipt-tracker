import 'category.dart';
import 'receipt_item.dart';

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
    this.source = ReceiptSource.manual,
    this.rawOcrText,
    this.items = const <ReceiptItem>[],
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

  /// Sum of item lines detected as 8% (reduced rate) / 10% (standard rate).
  final int? tax8ItemsTotal;
  final int? tax10ItemsTotal;

  /// 振込用紙 / utility bill deadline (支払期限).
  final DateTime? dueDate;
  final DateTime? reminderAt;

  /// Loyalty points printed on the receipt (dポイント, Ponta, Tポイント, ...).
  final String? pointBrand;
  final int? pointAmount;

  /// JAN-13 / Code 128 value or invoice reference number.
  final String? barcodeId;
  final String? categoryId;
  final String? note;
  final String? imageBase64;
  final ReceiptSource source;
  final String? rawOcrText;

  /// Item rows (商品明細), embedded in the Firestore receipt document.
  final List<ReceiptItem> items;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Joined from `categories(*)`.
  final ExpenseCategory? category;

  int get taxTotal => (tax8Amount ?? 0) + (tax10Amount ?? 0);

  int get itemsTotal =>
      items.fold<int>(0, (sum, item) => sum + item.totalPrice);

  int get itemsTax8Total => items
      .where((item) => item.taxRate == 8)
      .fold<int>(0, (sum, item) => sum + item.totalPrice);

  int get itemsTax10Total => items
      .where((item) => item.taxRate == 10)
      .fold<int>(0, (sum, item) => sum + item.totalPrice);

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
      tax8ItemsTotal: (json['tax_8_items_total'] as num?)?.toInt(),
      tax10ItemsTotal: (json['tax_10_items_total'] as num?)?.toInt(),
      dueDate: _parseDate(json['due_date']),
      reminderAt: _parseDate(json['reminder_at']),
      pointBrand: json['point_brand'] as String?,
      pointAmount: (json['point_amount'] as num?)?.toInt(),
      barcodeId: json['barcode_id'] as String?,
      categoryId: json['category_id'] as String?,
      note: json['note'] as String?,
      imageBase64: json['image_base64'] as String?,
      source: receiptSourceFromString(json['source'] as String?),
      rawOcrText: json['raw_ocr_text'] as String?,
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
      category: category,
      items: _parseItems(json),
    );
  }

  static List<ReceiptItem> _parseItems(Map<String, dynamic> json) {
    final raw = json['items'] ?? json['receipt_items'];
    if (raw is! List) return const <ReceiptItem>[];
    final items = raw
        .whereType<Map>()
        .map((row) => ReceiptItem.fromJson(Map<String, dynamic>.from(row)))
        .toList();
    items.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return items;
  }

  Receipt copyWith({
    String? merchant,
    DateTime? dueDate,
    DateTime? reminderAt,
    String? pointBrand,
    int? pointAmount,
    DateTime? purchasedAt,
    int? totalAmount,
    int? subtotalAmount,
    int? tax8Amount,
    int? tax10Amount,
    String? barcodeId,
    String? categoryId,
    String? note,
    String? imageBase64,
    ReceiptSource? source,
    String? rawOcrText,
    List<ReceiptItem>? items,
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
      tax8ItemsTotal: tax8ItemsTotal,
      tax10ItemsTotal: tax10ItemsTotal,
      dueDate: dueDate ?? this.dueDate,
      reminderAt: reminderAt ?? this.reminderAt,
      pointBrand: pointBrand ?? this.pointBrand,
      pointAmount: pointAmount ?? this.pointAmount,
      barcodeId: barcodeId ?? this.barcodeId,
      categoryId: categoryId ?? this.categoryId,
      note: note ?? this.note,
      imageBase64: imageBase64 ?? this.imageBase64,
      source: source ?? this.source,
      rawOcrText: rawOcrText ?? this.rawOcrText,
      items: items ?? this.items,
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
