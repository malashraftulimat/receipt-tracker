/// Amount consistency checks shared by the fallback parser, the Gemini result
/// mapper and the review screen.
///
/// Receipts often print a **tax-excluded subtotal** (`小計 税抜`) while line
/// prices may be tax-excluded too. Comparing the item sum directly with the
/// tax-included grand total therefore produces false warnings. A receipt is
/// consistent when any of these holds:
///
/// * `sum(items) == subtotal` (tax-excluded line prices)
/// * `sum(items) + tax == total` (tax-excluded lines plus printed tax)
/// * `sum(items) == total` (tax-included line prices)
bool itemsTotalMatchesReceipt({
  required double itemsTotal,
  double? subtotalAmount,
  double? taxTotal,
  double? totalAmount,
  double tolerance = 0.011,
}) {
  if (subtotalAmount != null &&
      (itemsTotal - subtotalAmount).abs() <= tolerance) {
    return true;
  }
  if (totalAmount != null) {
    if ((itemsTotal - totalAmount).abs() <= tolerance) return true;
    if ((taxTotal ?? 0) > 0 &&
        (itemsTotal + taxTotal! - totalAmount).abs() <= tolerance) {
      return true;
    }
  }
  return false;
}
