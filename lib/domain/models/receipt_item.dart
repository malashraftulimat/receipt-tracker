/// One line item on a receipt (商品明細).
class ReceiptItem {
  const ReceiptItem({
    this.id,
    this.receiptId,
    required this.name,
    this.quantity = 1,
    this.unitPrice,
    this.totalPrice = 0,
    this.taxRate,
    this.categoryId,
    this.sortOrder = 0,
  });

  final String? id;
  final String? receiptId;
  final String name;
  final int quantity;
  final int? unitPrice;
  final int totalPrice;

  /// 8 = reduced rate (軽減税率), 10 = standard rate, null = unknown.
  final int? taxRate;

  final String? categoryId;
  final int sortOrder;

  int get effectiveUnitPrice {
    if (unitPrice != null) return unitPrice!;
    if (quantity > 0) return (totalPrice / quantity).round();
    return totalPrice;
  }

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      id: json['id'] as String?,
      receiptId: json['receipt_id'] as String?,
      name: (json['name'] as String?)?.trim() ?? '',
      quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toInt(),
      totalPrice: (json['total_price'] as num?)?.toInt() ?? 0,
      taxRate: (json['tax_rate'] as num?)?.toInt(),
      categoryId: json['category_id'] as String?,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null) 'id': id,
        if (receiptId != null) 'receipt_id': receiptId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'tax_rate': taxRate,
        'category_id': categoryId,
        'sort_order': sortOrder,
      };

  Map<String, dynamic> toRow({required String receiptId}) => <String, dynamic>{
        'receipt_id': receiptId,
        'name': name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'total_price': totalPrice,
        'tax_rate': taxRate,
        'category_id': categoryId,
        'sort_order': sortOrder,
      };

  ReceiptItem copyWith({
    String? id,
    String? name,
    int? quantity,
    int? unitPrice,
    int? totalPrice,
    int? taxRate,
    String? categoryId,
    int? sortOrder,
  }) {
    return ReceiptItem(
      id: id ?? this.id,
      receiptId: receiptId,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      totalPrice: totalPrice ?? this.totalPrice,
      taxRate: taxRate ?? this.taxRate,
      categoryId: categoryId ?? this.categoryId,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }
}
