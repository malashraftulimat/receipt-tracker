/// 1D barcode helpers: JAN/EAN-13 check digit validation and pretty printing.
class BarcodeUtils {
  const BarcodeUtils._();

  /// EAN-13 (JAN-13) / UPC-A check digit validation.
  static bool isValidEan13(String code) {
    if (code.length != 13 || !RegExp(r'^\d{13}$').hasMatch(code)) return false;
    final digits = code.split('').map(int.parse).toList();
    final check = digits.removeLast();
    var sum = 0;
    for (var i = 0; i < digits.length; i++) {
      final weight = i.isEven ? 1 : 3;
      sum += digits[i] * weight;
    }
    return (10 - (sum % 10)) % 10 == check;
  }

  /// Japanese qualified-invoice registration number: `T` + 13 digits
  /// (full-width `Ｔ` accepted). Identifies the business, not the purchase.
  static bool looksLikeInvoiceRegistrationNumber(String? code) =>
      code != null && RegExp(r'^[TtＴ]\s*\d{13}$').hasMatch(code.trim());

  /// Code 128 / ITF / invoice references: digits and letters, 4..32 chars.
  static bool isReferenceLike(String code) {
    return RegExp(r'^[0-9A-Za-z\-]{4,32}$').hasMatch(code) &&
        code.contains(RegExp(r'\d'));
  }

  static bool looksLikeJan(String? code) =>
      code != null && RegExp(r'^\d{13}$').hasMatch(code);

  static bool looksLikeEan8(String? code) =>
      code != null && RegExp(r'^\d{8}$').hasMatch(code);

  /// `4901234567894` -> `490 1234567894`
  static String format(String code) {
    if (code.length == 13) {
      return '${code.substring(0, 3)} ${code.substring(3, 8)} ${code.substring(8)}';
    }
    return code;
  }
}
