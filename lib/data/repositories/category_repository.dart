import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/category.dart';

/// Firestore categories at `users/{userId}/categories/{categoryId}`.
class CategoryRepository {
  CategoryRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _categories =>
      _db.collection('users').doc(_userId).collection('categories');

  CollectionReference<Map<String, dynamic>> get _receipts =>
      _db.collection('users').doc(_userId).collection('receipts');

  Future<List<ExpenseCategory>> fetchAll() async {
    final snapshot = await _categories
        .orderBy('sort_order')
        .limit(200)
        .get();
    final categories = snapshot.docs
        .map((doc) => ExpenseCategory.fromJson(<String, dynamic>{
              ...doc.data(),
              'id': doc.id,
            }))
        .toList(growable: false);
    categories.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories;
  }

  /// Seeds the predefined categories once per account.
  Future<void> ensureDefaults() async {
    final existing = await _categories.limit(1).get();
    if (existing.docs.isNotEmpty) return;

    final batch = _db.batch();
    for (final template in ExpenseCategory.templates) {
      // Deterministic IDs make seeding idempotent across multiple devices.
      final doc = _categories.doc('default_${template.sortOrder}');
      batch.set(doc, <String, dynamic>{
        ...template.toRow(),
        'user_id': _userId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await batch.commit();
  }

  Future<ExpenseCategory> create({
    required String name,
    required String color,
    required String icon,
  }) async {
    final doc = _categories.doc();
    final data = <String, dynamic>{
      'user_id': _userId,
      'name': name.trim(),
      'color': color,
      'icon': icon,
      'is_default': false,
      'sort_order': 100,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    };
    await doc.set(data);
    return ExpenseCategory.fromJson(<String, dynamic>{
      ...data,
      'id': doc.id,
    });
  }

  Future<ExpenseCategory> update(ExpenseCategory category) async {
    await _categories.doc(category.id).update(category.toRow());
    return category;
  }

  Future<void> delete(String id) async {
    final batch = _db.batch();
    batch.delete(_categories.doc(id));

    // Keep receipts valid: they simply become uncategorised.
    final linked = await _receipts.where('category_id', isEqualTo: id).get();
    for (final doc in linked.docs) {
      batch.update(doc.reference, <String, dynamic>{
        'category_id': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
    }
    await batch.commit();
  }
}
