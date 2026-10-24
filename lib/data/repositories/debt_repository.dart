import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/debt.dart';

/// Firestore debts at `users/{uid}/debts/{debtId}`.
///
/// Repayments are embedded in the debt document so partial repayments and the
/// derived open/partial/settled status stay consistent.
class DebtRepository {
  DebtRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _debts =>
      _db.collection('users').doc(_userId).collection('debts');

  Future<List<Debt>> fetchAll() async {
    final snapshot =
        await _debts.orderBy('date', descending: true).limit(1000).get();
    return snapshot.docs
        .map((doc) => Debt.fromJson(
              <String, dynamic>{...doc.data(), 'user_id': _userId},
              id: doc.id,
            ))
        .toList(growable: false);
  }

  Future<Debt> save(Debt debt) async {
    final now = DateTime.now().toUtc().toIso8601String();
    final doc = _debts.doc(debt.id.isEmpty ? null : debt.id);
    await doc.set(<String, dynamic>{
      ...debt.toRow(),
      'user_id': _userId,
      'created_at': debt.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    }, SetOptions(merge: true));
    return Debt.fromJson(
      <String, dynamic>{
        ...debt.toRow(),
        'user_id': _userId,
        'created_at': debt.createdAt.toUtc().toIso8601String(),
        'updated_at': now,
      },
      id: doc.id,
    );
  }

  Future<void> delete(String id) => _debts.doc(id).delete();
}
