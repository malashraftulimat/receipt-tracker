import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/category.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../../domain/models/receipt_filter.dart';
import '../../domain/models/receipt_item.dart';
import '../../domain/parser/receipt_identity.dart';

/// Thrown when the same receipt already exists.
class DuplicateReceiptException implements Exception {
  DuplicateReceiptException({this.receiptNumber, this.existing});

  final String? receiptNumber;
  final Receipt? existing;

  String? get existingId => existing?.id;

  @override
  String toString() =>
      'DuplicateReceiptException(${receiptNumber ?? existing?.receiptNumber})';
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

    final snapshot =
        await query.orderBy('purchased_at', descending: true).limit(1000).get();

    final categories = await _categoryMap();
    var receipts = snapshot.docs
        .map((doc) => _fromDoc(doc, categories))
        .toList(growable: false);

    if (filter.categoryId != null) {
      receipts = receipts
          .where((receipt) => receipt.categoryId == filter.categoryId)
          .toList(growable: false);
    }

    if (filter.paymentMethod != null) {
      receipts = receipts
          .where((receipt) => receipt.paymentMethod == filter.paymentMethod)
          .toList(growable: false);
    }

    final term = filter.searchTerm.toLowerCase();
    if (term.isNotEmpty) {
      receipts = receipts.where((receipt) {
        return (receipt.merchant ?? '').toLowerCase().contains(term) ||
            (receipt.note ?? '').toLowerCase().contains(term) ||
            (receipt.barcodeId ?? '').toLowerCase().contains(term) ||
            (receipt.invoiceRegistrationNumber ?? '')
                .toLowerCase()
                .contains(term);
      }).toList(growable: false);
    }

    return receipts;
  }

  Future<Receipt> getById(String id) async {
    final doc = await _receipts.doc(id).get();
    if (!doc.exists) throw StateError('error.receipt_not_found');
    return _fromDoc(doc, await _categoryMap());
  }

  Future<String?> findIdByBarcode(String barcode) async =>
      (await findDuplicate(receiptNumber: barcode))?.id;

  /// Finds an already-saved copy of the same purchase.
  ///
  /// The receipt's own number is the primary key. Legacy documents stored that
  /// value in `barcode_id`, so both fields are checked. Any stored value that
  /// looks like a 登録番号 (`T` + 13 digits) is ignored: it identifies the shop
  /// and repeats on every receipt from that shop.
  ///
  /// When no receipt number exists, the fallback fingerprint is
  /// merchant + purchased_at (to the minute) + total.
  Future<Receipt?> findDuplicate({
    String? receiptNumber,
    String? merchant,
    DateTime? purchasedAt,
    double? totalAmount,
    String? excludeId,
  }) async {
    final normalized = ReceiptIdentity.normalizeReceiptNumber(receiptNumber);
    if (normalized != null) {
      Map<String, ExpenseCategory>? categories;
      for (final field in const <String>['receipt_number', 'barcode_id']) {
        final snapshot = await _receipts
            .where(field, isEqualTo: normalized)
            .limit(5)
            .get();
        for (final doc in snapshot.docs) {
          if (doc.id == excludeId) continue;
          categories ??= await _categoryMap();
          final receipt = _fromDoc(doc, categories);
          // A legacy T-number stored in barcode_id is normalised into the
          // invoice field by Receipt.fromJson and will not match here.
          if (receipt.receiptNumber == normalized) return receipt;
        }
      }
      // The receipt has its own number, so only that number is authoritative.
      return null;
    }

    if ((merchant ?? '').trim().isEmpty ||
        purchasedAt == null ||
        totalAmount == null) {
      return null;
    }

    final start = ReceiptIdentity.truncateToMinute(purchasedAt);
    final end = start.add(const Duration(minutes: 1));
    final snapshot = await _receipts
        .where(
          'purchased_at',
          isGreaterThanOrEqualTo: start.toUtc().toIso8601String(),
        )
        .where(
          'purchased_at',
          isLessThan: end.toUtc().toIso8601String(),
        )
        .limit(20)
        .get();
    final categories = await _categoryMap();
    for (final doc in snapshot.docs) {
      if (doc.id == excludeId) continue;
      final receipt = _fromDoc(doc, categories);
      if (ReceiptIdentity.matchesFallback(
        merchantA: merchant,
        purchasedAtA: purchasedAt,
        totalA: totalAmount,
        merchantB: receipt.merchant,
        purchasedAtB: receipt.purchasedAt,
        totalB: receipt.totalAmount,
      )) {
        return receipt;
      }
    }
    return null;
  }

  /// One-time cleanup: move legacy `barcode_id` values that are actually
  /// 登録番号 (`T` + 13 digits) into `invoice_registration_number` so they can
  /// never trigger a false duplicate warning.
  static final Set<String> _invoiceMigrationUsers = <String>{};

  Future<void> migrateLegacyInvoiceNumbers() async {
    if (!_invoiceMigrationUsers.add(_userId)) return;
    try {
      // Keep the batch comfortably below Firestore's 500-write limit.
      final snapshot = await _receipts.limit(400).get();
      final batch = _db.batch();
      var changed = false;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final barcode = (data['barcode_id'] as String?)?.trim();
        if (!ReceiptIdentity.isInvoiceRegistrationNumber(barcode)) continue;
        if ((data['invoice_registration_number'] as String?)?.isNotEmpty ==
            true) {
          continue;
        }
        final normalized =
            ReceiptIdentity.normalizeInvoiceRegistrationNumber(barcode);
        if (normalized == null) continue;
        batch.update(doc.reference, <String, dynamic>{
          'invoice_registration_number': normalized,
          'barcode_id': null,
          'receipt_number': null,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        changed = true;
      }
      if (changed) await batch.commit();
    } catch (_) {
      // Offline / permission errors are harmless; the read path already
      // normalises legacy values.
    }
  }

  Future<Receipt> create(
    ReceiptDraft draft, {
    bool skipDuplicateCheck = false,
  }) async {
    if (!skipDuplicateCheck) {
      final existing = await findDuplicate(
        receiptNumber: draft.barcodeId,
        merchant: draft.merchant,
        purchasedAt: draft.purchasedAt,
        totalAmount: draft.totalAmount,
      );
      if (existing != null) {
        throw DuplicateReceiptException(
          receiptNumber: draft.barcodeId,
          existing: existing,
        );
      }
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final doc = _receipts.doc();
    await doc.set(<String, dynamic>{
      ...draft.toRow(includeItems: true),
      'user_id': _userId,
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
