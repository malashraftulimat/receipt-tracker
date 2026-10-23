import 'category.dart';
import 'payment_method.dart';
import 'pay_cycle.dart';
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
      return 'barcode';
    case ReceiptSource.ocr:
      return 'OCR';
    case ReceiptSource.manual:
      return 'manual_entry';
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
    this.currency = 'JPY',
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
    this.paymentMethod,
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

  /// ISO-4217 currency code (e.g. JPY, USD, SAR).
  final String currency;
  final DateTime purchasedAt;

  /// Amounts in [currency]; decimal values are supported.
  final double totalAmount;
  final double? subtotalAmount;
  final double? tax8Amount;
  final double? tax10Amount;
  final double? tax8Base;
  final double? tax10Base;

  /// Sum of item lines detected as 8% (reduced rate) / 10% (standard rate).
  /// Only populated when a Japanese consumption tax rate is printed.
  final double? tax8ItemsTotal;
  final double? tax10ItemsTotal;

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

  /// How the payment was made. Null for documents saved before this field
  /// existed (and for receipts where the user left it unset).
  final PaymentMethod? paymentMethod;

  final ReceiptSource source;
  final String? rawOcrText;

  /// Item rows (商品明細), embedded in the Firestore receipt document.
  final List<ReceiptItem> items;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// Joined from `categories(*)`.
  final ExpenseCategory? category;

  double get taxTotal => (tax8Amount ?? 0) + (tax10Amount ?? 0);

  double get itemsTotal =>
      items.fold<double>(0, (sum, item) => sum + item.totalPrice);

  double get itemsTax8Total => items
      .where((item) => item.taxRate == 8)
      .fold<double>(0, (sum, item) => sum + item.totalPrice);

  double get itemsTax10Total => items
      .where((item) => item.taxRate == 10)
      .fold<double>(0, (sum, item) => sum + item.totalPrice);

  bool get hasTaxBreakdown => tax8Amount != null || tax10Amount != null;

  String get displayMerchant => (merchant == null || merchant!.trim().isEmpty)
      ? 'no_store_name'
      : merchant!.trim();

  /// Merchant for receipts, otherwise the note (used by quick payments that
  /// have no merchant), otherwise a placeholder.
  String get displayTitle {
    final name = (merchant ?? '').trim();
    if (name.isNotEmpty) return name;
    final memo = (note ?? '').trim();
    if (memo.isNotEmpty) return memo;
    return 'no_store_name';
  }

  String get displayCategory => category?.name ?? 'uncategorised';

  String get displayPaymentMethod => PaymentMethod.labelOf(paymentMethod);

  DateTime get monthStart => DateTime(purchasedAt.year, purchasedAt.month);

  factory Receipt.fromJson(Map<String, dynamic> json) {
    ExpenseCategory? category;
    final rawCategory = json['category'];
    if (rawCategory is Map) {
      category =
          ExpenseCategory.fromJson(Map<String, dynamic>.from(rawCategory));
    }
    return Receipt(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      merchant: json['merchant'] as String?,
      currency: (json['currency'] as String?)?.trim().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : 'JPY',
      purchasedAt: _parseDate(json['purchased_at']) ?? DateTime.now(),
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      subtotalAmount: (json['subtotal_amount'] as num?)?.toDouble(),
      tax8Amount: (json['tax_8_amount'] as num?)?.toDouble(),
      tax10Amount: (json['tax_10_amount'] as num?)?.toDouble(),
      tax8Base: (json['tax_8_base'] as num?)?.toDouble(),
      tax10Base: (json['tax_10_base'] as num?)?.toDouble(),
      tax8ItemsTotal: (json['tax_8_items_total'] as num?)?.toDouble(),
      tax10ItemsTotal: (json['tax_10_items_total'] as num?)?.toDouble(),
      dueDate: _parseDate(json['due_date']),
      reminderAt: _parseDate(json['reminder_at']),
      pointBrand: json['point_brand'] as String?,
      pointAmount: (json['point_amount'] as num?)?.toInt(),
      barcodeId: json['barcode_id'] as String?,
      categoryId: json['category_id'] as String?,
      note: json['note'] as String?,
      paymentMethod: PaymentMethod.tryParse(json['payment_method']),
      // Legacy image_base64 documents are tolerated but the photo is ignored.
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
    String? currency,
    DateTime? dueDate,
    DateTime? reminderAt,
    String? pointBrand,
    int? pointAmount,
    DateTime? purchasedAt,
    double? totalAmount,
    double? subtotalAmount,
    double? tax8Amount,
    double? tax10Amount,
    String? barcodeId,
    String? categoryId,
    String? note,
    PaymentMethod? paymentMethod,
    ReceiptSource? source,
    String? rawOcrText,
    List<ReceiptItem>? items,
    ExpenseCategory? category,
  }) {
    return Receipt(
      id: id,
      userId: userId,
      merchant: merchant ?? this.merchant,
      currency: currency ?? this.currency,
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
      paymentMethod: paymentMethod ?? this.paymentMethod,
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

/// Pay-period helpers shared by the budget summary and the tests.
extension ReceiptPeriodSpending on Iterable<Receipt> {
  /// Sum of the receipts purchased inside [period] (`[start, end)`).
  double totalInPeriod(PayPeriod period) {
    var total = 0.0;
    for (final receipt in this) {
      if (period.contains(receipt.purchasedAt)) total += receipt.totalAmount;
    }
    return total;
  }

  /// Receipts purchased inside [period], newest first.
  List<Receipt> withinPeriod(PayPeriod period) {
    final rows = where((receipt) => period.contains(receipt.purchasedAt))
        .toList(growable: false);
    return rows..sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
  }
}
