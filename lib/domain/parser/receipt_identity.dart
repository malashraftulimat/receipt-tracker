/// Receipt identity helpers shared by the parser, repository and review screen.
///
/// A Japanese qualified-invoice registration number (`登録番号`, `T` followed by
/// 13 digits) identifies the *business*, not the purchase, so it must never be
/// used as a duplicate key. The receipt's own number (`伝票番号` /
/// `レシート番号` / the receipt barcode) or a merchant + minute + total
/// fingerprint is used instead.
class ReceiptIdentity {
  const ReceiptIdentity._();

  static final RegExp _invoicePattern = RegExp(r'^[Tt]\s*(\d{13})$');

  /// True for `T` + 13 digits (full-width `Ｔ` accepted).
  static bool isInvoiceRegistrationNumber(String? value) =>
      _invoicePattern.hasMatch((value ?? '').trim().replaceAll('Ｔ', 'T'));

  /// Normalises a registration number to `T` + 13 digits, or returns the
  /// trimmed free text when it is not in that format.
  static String? normalizeInvoiceRegistrationNumber(String? value) {
    final text = (value ?? '').trim().replaceAll('Ｔ', 'T');
    if (text.isEmpty) return null;
    final match = _invoicePattern.firstMatch(text);
    if (match != null) return 'T${match.group(1)}';
    return text;
  }

  /// The receipt's own number. Registration numbers are rejected here so a
  /// mis-typed `T…` value can never become a duplicate key.
  static String? normalizeReceiptNumber(String? value) {
    final text = (value ?? '').trim().replaceAll('Ｔ', 'T');
    if (text.isEmpty) return null;
    if (isInvoiceRegistrationNumber(text)) return null;
    return text;
  }

  /// Minute precision used by the fallback duplicate fingerprint.
  static DateTime truncateToMinute(DateTime value) =>
      DateTime(value.year, value.month, value.day, value.hour, value.minute);

  /// True when [a] and [b] are the same merchant, ignoring case and spacing.
  static bool sameMerchant(String? a, String? b) =>
      _normalizeMerchant(a) == _normalizeMerchant(b);

  static String _normalizeMerchant(String? value) =>
      (value ?? '').trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Fallback duplicate match: merchant + purchased_at to the minute + total.
  static bool matchesFallback({
    required String? merchantA,
    required DateTime? purchasedAtA,
    required double? totalA,
    required String? merchantB,
    required DateTime? purchasedAtB,
    required double? totalB,
    double tolerance = 0.011,
  }) {
    if ((merchantA ?? '').trim().isEmpty ||
        (merchantB ?? '').trim().isEmpty) {
      return false;
    }
    if (purchasedAtA == null || purchasedAtB == null) return false;
    if (totalA == null || totalB == null) return false;
    if (!sameMerchant(merchantA, merchantB)) return false;
    if (truncateToMinute(purchasedAtA) !=
        truncateToMinute(purchasedAtB)) {
      return false;
    }
    return (totalA - totalB).abs() <= tolerance;
  }
}
