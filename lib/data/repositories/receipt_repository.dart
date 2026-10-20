import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/category.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_filter.dart';
import '../../domain/models/receipt_item.dart';

/// Thrown when a receipt with the same barcode already exists.
class DuplicateReceiptException implements Exception {
  DuplicateReceiptException(this.barcode, {this.existingId});

  final String barcode;
  final String? existingId;

  @override
  String toString() => 'DuplicateReceiptException($barcode)';
}

/// Firestore receipts at `users/{userId}/receipts/{receiptId}`.
///
/// Line items are embedded in the receipt document as an `items` array so a
/// receipt and its items are written atomically without a second collection.
class ReceiptRepository {
  ReceiptRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _receipts =>
      _db.collection('users').doc(_userId).collection('receipts');

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('users').doc(_userId).collection('categories');

  Future<List<Receipt>> fetch(ReceiptFilter filter) async {
    Query<Map<String, dynamic>> query = _receipts;

    final start = filter.rangeStart;
    final end = filter.rangeEnd;
    if (start != null) {
      query = query.where(
        'purchased_at',
        isGreaterThanOrEqualTo: start.toUtc().toIso8601String(),
      );
    }
    if (end != null) {
      query = query.where(
        'purchased_at',
        isLessThan: end.toUtc().toIso8601String(),
      );
    }

    final snapshot = await query
        .orderBy('purchased_at', descending: true)
        .limit(1000)
        .get();

    final categories = await _categoryMap();
    var receipts = snapshot.docs
        .map((doc) => _fromDoc(doc, categories))
        .toList(growable: false);

    if (filter.categoryId != null) {
      receipts = receipts
          .where((receipt) => receipt.categoryId == filter.categoryId)
          .toList(growable: false);
    }

    final term = filter.searchTerm.toLowerCase();
    if (term.isNotEmpty) {
      receipts = receipts.where((receipt) {
        return (receipt.merchant ?? '').toLowerCase().contains(term) ||
            (receipt.note ?? '').toLowerCase().contains(term) ||
            (receipt.barcodeId ?? '').toLowerCase().contains(term);
      }).toList(growable: false);
    }

    return receipts;
  }

  Future<Receipt> getById(String id) async {
    final doc = await _receipts.doc(id).get();
    if (!doc.exists) throw StateError('レシートが見つかりません');
    return _fromDoc(doc, await _categoryMap());
  }

  Future<String?> findIdByBarcode(String barcode) async {
    final snapshot = await _receipts
        .where('barcode_id', isEqualTo: barcode)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return snapshot.docs.first.id;
  }

  Future<Receipt> create(ReceiptDraft draft, {String? imageBase64}) async {
    final barcode = draft.barcodeId?.trim();
    if (barcode != null && barcode.isNotEmpty) {
      final existingId = await findIdByBarcode(barcode);
      if (existingId != null) {
        throw DuplicateReceiptException(barcode, existingId: existingId);
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final doc = _receipts.doc();
    await doc.set(<String, dynamic>{
      ...draft.toRow(includeItems: true),
      'user_id': _userId,
      'image_base64': imageBase64 ?? draft.imageBase64,
      'created_at': now,
      'updated_at': now,
    });

    return getById(doc.id);
  }

  Future<Receipt> update(
    String id,
    Map<String, dynamic> patch, {
    List<ReceiptItem>? items,
  }) async {
    final data = <String, dynamic>{
      ...patch,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
      if (items != null)
        'items': <Map<String, dynamic>>[
          for (var i = 0; i < items.length; i++)
            <String, dynamic>{
              ...items[i].toJson(),
              'sort_order': i,
            },
        ],
    };

    await _receipts.doc(id).update(data);
    return getById(id);
  }

  Future<void> delete(String id) => _receipts.doc(id).delete();

  Receipt _fromDoc(
    DocumentSnapshot<Map<String, dynamic>> doc,
    Map<String, ExpenseCategory> categories,
  ) {
    final data = <String, dynamic>{
      ...(doc.data() ?? const <String, dynamic>{}),
      'id': doc.id,
      'user_id': _userId,
    };
    final categoryId = data['category_id'] as String?;
    final category = categoryId == null ? null : categories[categoryId];
    if (category != null) {
      data['category'] = category.toJson();
    }
    return Receipt.fromJson(data);
  }

  Future<Map<String, ExpenseCategory>> _categoryMap() async {
    final snapshot = await _categories.get();
    return <String, ExpenseCategory>{
      for (final doc in snapshot.docs)
        doc.id: ExpenseCategory.fromJson(<String, dynamic>{
          ...doc.data(),
          'id': doc.id,
        }),
    };
  }
}
