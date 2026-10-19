import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/category.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_filter.dart';

/// On-device persistence used by "ローカルモード" (no Supabase, no account).
///
/// Data lives in SharedPreferences, which maps to `localStorage` on the web and
/// to a key-value file on mobile/desktop. Images are stored as data URIs when
/// small enough, otherwise they are kept in memory for the current session.
class LocalStore {
  LocalStore._();

  static final LocalStore instance = LocalStore._();

  static const String localUserId = 'local-user';

  static const String receiptsKey = 'local_receipts_v1';
  static const String categoriesKey = 'local_categories_v1';

  /// Local accounts keep separate data: keys are suffixed with the user id.
  String _userId = 'local-user';
  String get _receiptsKey => '${receiptsKey}_$_userId';
  String get _categoriesKey => '${categoriesKey}_$_userId';

  void useUser(String userId) => _userId = userId;

  static const String _imagePrefix = 'local_image_';

  /// ~1.2 MB of base64 text (~900 KB image) fits comfortably in localStorage.
  static const int _maxInlineImageChars = 1200000;

  final Map<String, String> _memoryImages = <String, String>{};
  SharedPreferences? _prefs;

  Future<SharedPreferences> get _p async =>
      _prefs ??= await SharedPreferences.getInstance();

  // -------------------------------------------------------------------------
  // Raw storage
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> _readList(String key) async {
    final prefs = await _p;
    final raw = prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList();
      }
    } catch (_) {
      // Corrupted payload — start fresh rather than crash.
    }
    return <Map<String, dynamic>>[];
  }

  Future<void> _writeList(String key, List<Map<String, dynamic>> rows) async {
    final prefs = await _p;
    await prefs.setString(key, jsonEncode(rows));
  }

  // -------------------------------------------------------------------------
  // Categories
  // -------------------------------------------------------------------------

  Future<List<Map<String, dynamic>>> categoryRows() => _readList(_categoriesKey);

  Future<List<ExpenseCategory>> fetchCategories() async {
    final rows = await _readList(_categoriesKey);
    final categories = rows.map(ExpenseCategory.fromJson).toList();
    categories.sort((a, b) {
      final byOrder = a.sortOrder.compareTo(b.sortOrder);
      return byOrder != 0 ? byOrder : a.name.compareTo(b.name);
    });
    return categories;
  }

  Future<void> seedDefaults() async {
    final rows = await _readList(_categoriesKey);
    if (rows.isNotEmpty) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await _writeList(_categoriesKey, <Map<String, dynamic>>[
      for (final template in ExpenseCategory.templates)
        <String, dynamic>{
          'id': 'default-${template.sortOrder}',
          'user_id': localUserId,
          'created_at': now,
          ...template.toRow(),
        },
    ]);
  }

  Future<ExpenseCategory> createCategory({
    required String name,
    required String color,
    required String icon,
  }) async {
    final rows = await _readList(_categoriesKey);
    final row = <String, dynamic>{
      'id': 'cat-${DateTime.now().microsecondsSinceEpoch}',
      'user_id': localUserId,
      'name': name.trim(),
      'color': color,
      'icon': icon,
      'is_default': false,
      'sort_order': 100,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    rows.add(row);
    await _writeList(_categoriesKey, rows);
    return ExpenseCategory.fromJson(row);
  }

  Future<ExpenseCategory> updateCategory(ExpenseCategory category) async {
    final rows = await _readList(_categoriesKey);
    var updated = <String, dynamic>{...category.toJson()};
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['id'] == category.id) {
        updated = <String, dynamic>{...rows[i], ...category.toRow()};
        rows[i] = updated;
        break;
      }
    }
    await _writeList(_categoriesKey, rows);
    return ExpenseCategory.fromJson(updated);
  }

  Future<void> deleteCategory(String id) async {
    final rows = await _readList(_categoriesKey);
    rows.removeWhere((row) => row['id'] == id);
    await _writeList(_categoriesKey, rows);

    // Detach receipts that pointed at the deleted category.
    final receipts = await _readList(_receiptsKey);
    var changed = false;
    for (final row in receipts) {
      if (row['category_id'] == id) {
        row['category_id'] = null;
        changed = true;
      }
    }
    if (changed) await _writeList(_receiptsKey, receipts);
  }

  // -------------------------------------------------------------------------
  // Receipts
  // -------------------------------------------------------------------------

  Future<List<Receipt>> fetchReceipts(ReceiptFilter filter) async {
    final categories = await _readList(_categoriesKey);
    final rows = await _readList(_receiptsKey);

    final start = filter.rangeStart;
    final end = filter.rangeEnd;
    final search = filter.searchTerm.toLowerCase();

    final receipts = <Receipt>[];
    for (final row in rows) {
      final receipt = _toReceipt(row, categories);
      if (filter.categoryId != null && receipt.categoryId != filter.categoryId) {
        continue;
      }
      if (start != null && receipt.purchasedAt.isBefore(start)) continue;
      if (end != null && !receipt.purchasedAt.isBefore(end)) continue;
      if (search.isNotEmpty) {
        final haystack = '${receipt.merchant ?? ''} '
                '${receipt.note ?? ''} '
                '${receipt.barcodeId ?? ''}'
            .toLowerCase();
        if (!haystack.contains(search)) continue;
      }
      receipts.add(receipt);
    }

    receipts.sort((a, b) => b.purchasedAt.compareTo(a.purchasedAt));
    return receipts;
  }

  Future<Receipt?> receiptById(String id) async {
    final rows = await _readList(_receiptsKey);
    for (final row in rows) {
      if (row['id'] == id) {
        return _toReceipt(row, await _readList(_categoriesKey));
      }
    }
    return null;
  }

  Future<String?> findIdByBarcode(String barcode) async {
    final rows = await _readList(_receiptsKey);
    for (final row in rows) {
      if (row['barcode_id'] == barcode) return row['id'] as String?;
    }
    return null;
  }

  Future<Receipt> createReceipt(ReceiptDraft draft, String? imagePath) async {
    final rows = await _readList(_receiptsKey);
    final now = DateTime.now().toUtc().toIso8601String();
    final row = <String, dynamic>{
      'id': 'r-${DateTime.now().microsecondsSinceEpoch}',
      'user_id': localUserId,
      ...draft.toRow(),
      'image_path': imagePath ?? draft.imagePath,
      'created_at': now,
      'updated_at': now,
    };
    rows.add(row);
    await _writeList(_receiptsKey, rows);
    return _toReceipt(row, await _readList(_categoriesKey));
  }

  Future<Receipt> updateReceipt(String id, Map<String, dynamic> patch) async {
    final rows = await _readList(_receiptsKey);
    Map<String, dynamic>? updated;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['id'] != id) continue;
      updated = <String, dynamic>{
        ...rows[i],
        ...patch,
        'id': id,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      rows[i] = updated;
      break;
    }
    await _writeList(_receiptsKey, rows);
    if (updated == null) {
      throw StateError('レシートが見つかりません');
    }
    return _toReceipt(updated, await _readList(_categoriesKey));
  }

  Future<void> deleteReceipt(String id) async {
    final rows = await _readList(_receiptsKey);
    String? imagePath;
    for (final row in rows) {
      if (row['id'] == id) imagePath = row['image_path'] as String?;
    }
    rows.removeWhere((row) => row['id'] == id);
    await _writeList(_receiptsKey, rows);
    if (imagePath != null) await deleteImage(imagePath);
  }

  Receipt _toReceipt(
    Map<String, dynamic> row,
    List<Map<String, dynamic>> categories,
  ) {
    Map<String, dynamic>? categoryRow;
    final categoryId = row['category_id'];
    if (categoryId != null) {
      for (final candidate in categories) {
        if (candidate['id'] == categoryId) {
          categoryRow = candidate;
          break;
        }
      }
    }
    return Receipt.fromJson(<String, dynamic>{
      ...row,
      'category': categoryRow,
    });
  }

  // -------------------------------------------------------------------------
  // Images
  // -------------------------------------------------------------------------

  Future<String> saveImage(Uint8List bytes) async {
    final data = 'data:image/jpeg;base64,${base64Encode(bytes)}';
    final id = 'img-${DateTime.now().microsecondsSinceEpoch}';

    if (data.length <= _maxInlineImageChars) {
      try {
        final prefs = await _p;
        await prefs.setString('$_imagePrefix$id', data);
        return 'local-image:$id';
      } catch (_) {
        // Quota exceeded — fall back to memory for this session.
      }
    }

    _memoryImages[id] = data;
    return 'local-image:$id';
  }

  Future<String?> resolveImage(String path) async {
    if (!path.startsWith('local-image:')) return null;
    final id = path.substring('local-image:'.length);
    final prefs = await _p;
    return prefs.getString('$_imagePrefix$id') ?? _memoryImages[id];
  }

  Future<void> deleteImage(String path) async {
    if (!path.startsWith('local-image:')) return;
    final id = path.substring('local-image:'.length);
    _memoryImages.remove(id);
    final prefs = await _p;
    await prefs.remove('$_imagePrefix$id');
  }

  /// Clears cached handles so tests can swap the underlying storage.
  void resetCacheForTests() {
    _prefs = null;
    _memoryImages.clear();
  }

  // -------------------------------------------------------------------------
  // Reset
  // -------------------------------------------------------------------------

  Future<void> clearAll() async {
    final prefs = await _p;
    _memoryImages.clear();
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(receiptsKey) ||
          key.startsWith(categoriesKey) ||
          key.startsWith(_imagePrefix)) {
        await prefs.remove(key);
      }
    }
  }
}