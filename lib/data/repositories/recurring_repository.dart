import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/recurring_transaction.dart';

/// Firestore recurring transactions at
/// `users/{uid}/recurring_transactions/{recurringId}`.
class RecurringTransactionRepository {
  RecurringTransactionRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _items =>
      _db.collection('users').doc(_userId).collection('recurring_transactions');

  Future<List<RecurringTransaction>> fetchAll() async {
    final snapshot = await _items.orderBy('created_at').limit(500).get();
    return snapshot.docs
        .map((doc) => RecurringTransaction.fromJson(
              <String, dynamic>{...doc.data(), 'user_id': _userId},
              id: doc.id,
            ))
        .toList(growable: false);
  }

  Future<RecurringTransaction> save(RecurringTransaction item) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final doc = _items.doc(item.id.isEmpty ? null : item.id);
    final row = <String, dynamic>{
      ...item.toRow(),
      'user_id': _userId,
      'created_at': item.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    };
    await doc.set(row, SetOptions(merge: true));
    return RecurringTransaction.fromJson(
      <String, dynamic>{...row, 'id': doc.id},
      id: doc.id,
    );
  }

  Future<void> delete(String id) => _items.doc(id).delete();
}
