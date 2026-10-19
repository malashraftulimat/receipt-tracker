enum ReceiptViewMode { list, grid }

const Object _unset = Object();

/// Query state for the dashboard list (search / category / month / range / view).
class ReceiptFilter {
  const ReceiptFilter({
    this.search = '',
    this.categoryId,
    this.month,
    this.from,
    this.to,
    this.view = ReceiptViewMode.list,
  });

  final String search;
  final String? categoryId;

  /// First day of the selected month (mutually exclusive with [from]/[to]).
  final DateTime? month;

  /// Inclusive start of a custom range.
  final DateTime? from;

  /// Exclusive end of a custom range.
  final DateTime? to;

  final ReceiptViewMode view;

  DateTime? get rangeStart => month ?? from;

  DateTime? get rangeEnd =>
      month != null ? DateTime(month!.year, month!.month + 1, 1) : to;

  bool get hasFilters =>
      search.trim().isNotEmpty ||
      categoryId != null ||
      month != null ||
      from != null;

  String get searchTerm => search.trim();

  ReceiptFilter copyWith({
    String? search,
    Object? categoryId = _unset,
    Object? month = _unset,
    Object? from = _unset,
    Object? to = _unset,
    ReceiptViewMode? view,
  }) {
    return ReceiptFilter(
      search: search ?? this.search,
      categoryId: identical(categoryId, _unset)
          ? this.categoryId
          : categoryId as String?,
      month: identical(month, _unset) ? this.month : month as DateTime?,
      from: identical(from, _unset) ? this.from : from as DateTime?,
      to: identical(to, _unset) ? this.to : to as DateTime?,
      view: view ?? this.view,
    );
  }
}
