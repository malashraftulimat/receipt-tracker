import '../parser/receipt_parser.dart';

/// Lifecycle of a coupon saved from a scanned receipt.
enum CouponStatus {
  active('active'),
  used('used'),
  expired('expired');

  const CouponStatus(this.value);

  final String value;

  static CouponStatus fromValue(Object? value) => switch (value) {
        'used' => CouponStatus.used,
        'expired' => CouponStatus.expired,
        _ => CouponStatus.active,
      };
}

/// Coupon / voucher printed on a receipt, tracked locally and in Firestore.
///
/// Date fields are calendar days (no time component): a coupon stays usable for
/// the whole `validUntil` day.
class Coupon {
  const Coupon({
    required this.id,
    required this.name,
    this.merchant,
    this.receiptId,
    this.validFrom,
    this.validUntil,
    this.discountAmountOrPercent,
    this.status = CouponStatus.active,
    this.createdAt,
  });

  /// Firestore document id.
  final String id;

  /// Coupon title exactly as printed.
  final String name;

  /// Store that issued the coupon (receipt merchant).
  final String? merchant;

  /// Receipt the coupon was scanned from, when known.
  final String? receiptId;

  /// First usable day; null means immediately valid.
  final DateTime? validFrom;

  /// Last usable day (inclusive); null means no printed expiry.
  final DateTime? validUntil;

  /// Printed value such as `10%` or `500`.
  final String? discountAmountOrPercent;

  final CouponStatus status;
  final DateTime? createdAt;

  /// Builds a coupon from the OCR output of one receipt.
  factory Coupon.fromParsed(
    String id,
    ParsedCoupon parsed, {
    String? merchant,
    String? receiptId,
    DateTime? createdAt,
  }) =>
      Coupon(
        id: id,
        name: parsed.name,
        merchant: merchant,
        receiptId: receiptId,
        validFrom:
            parsed.validFrom == null ? null : _dateOnly(parsed.validFrom!),
        validUntil:
            parsed.validUntil == null ? null : _dateOnly(parsed.validUntil!),
        discountAmountOrPercent: parsed.discountAmountOrPercent,
        createdAt: createdAt,
      );

  factory Coupon.fromJson(Map<String, dynamic> json, {required String id}) {
    return Coupon(
      id: id,
      name: (json['name'] as String?)?.trim() ?? '',
      merchant: _string(json['merchant']),
      receiptId: _string(json['receipt_id']),
      validFrom: _parseDate(json['valid_from']),
      validUntil: _parseDate(json['valid_until']),
      discountAmountOrPercent:
          _string(json['discount_amount_or_percent']),
      status: CouponStatus.fromValue(json['status']),
      createdAt: _parseDate(json['created_at']),
    );
  }

  /// True once the printed `validUntil` day is over.
  bool isExpiredAt(DateTime now) {
    final until = validUntil;
    if (until == null) return false;
    return _dateOnly(now).isAfter(_dateOnly(until));
  }

  /// True when the coupon is active, already started and not expired.
  bool isUsableAt(DateTime now) {
    if (status != CouponStatus.active || isExpiredAt(now)) return false;
    final from = validFrom;
    if (from == null) return true;
    return !_dateOnly(now).isBefore(_dateOnly(from));
  }

  /// Whole days left until [validUntil] (0 = last day, null = no expiry).
  int? daysUntilExpiry(DateTime now) {
    final until = validUntil;
    if (until == null) return null;
    return _dateOnly(until).difference(_dateOnly(now)).inDays;
  }

  /// Status that [expireOverdue] should persist at [now].
  CouponStatus statusAt(DateTime now) {
    if (status == CouponStatus.used) return CouponStatus.used;
    if (isExpiredAt(now)) return CouponStatus.expired;
    return status;
  }

  Coupon withStatus(CouponStatus next) => Coupon(
        id: id,
        name: name,
        merchant: merchant,
        receiptId: receiptId,
        validFrom: validFrom,
        validUntil: validUntil,
        discountAmountOrPercent: discountAmountOrPercent,
        status: next,
        createdAt: createdAt,
      );

  /// Firestore payload; the document id is stored separately.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        if (merchant != null) 'merchant': merchant,
        if (receiptId != null) 'receipt_id': receiptId,
        'valid_from': _formatDate(validFrom),
        'valid_until': _formatDate(validUntil),
        'discount_amount_or_percent': discountAmountOrPercent,
        'status': status.value,
        'created_at': (createdAt ?? DateTime.now()).toUtc().toIso8601String(),
      };

  static String? _string(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static DateTime? _parseDate(Object? value) {
    if (value == null) return null;
    if (value is DateTime) return _dateOnly(value);
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final parsed = DateTime.tryParse(text);
    return parsed == null ? null : _dateOnly(parsed);
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String? _formatDate(DateTime? value) {
    if (value == null) return null;
    final date = _dateOnly(value);
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year.toString().padLeft(4, '0')}-$month-$day';
  }
}
