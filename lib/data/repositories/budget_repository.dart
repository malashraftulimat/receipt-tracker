import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/monthly_budget.dart';

/// Firestore budgets at `users/{userId}/budgets/{yyyy-MM}`.
class BudgetRepository {
  BudgetRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _budgets =>
      _db.collection('users').doc(_userId).collection('budgets');

  String _key(DateTime month) =>
      '${month.year.toString().padLeft(4, '0')}-'
      '${month.month.toString().padLeft(2, '0')}';

  Future<MonthlyBudget?> fetchMonth(DateTime month) async {
    final doc = await _budgets.doc(_key(month)).get();
    if (!doc.exists) return null;
    return MonthlyBudget.fromJson(<String, dynamic>{
      ...?doc.data(),
      'id': doc.id,
    });
  }

  Future<MonthlyBudget> save(MonthlyBudget budget) async {
    final first = DateTime(budget.month.year, budget.month.month, 1);
    final doc = _budgets.doc(_key(first));
    await doc.set(<String, dynamic>{
      ...budget.toRow(),
      'user_id': _userId,
      'month': first.toUtc().toIso8601String(),
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, SetOptions(merge: true));
    return MonthlyBudget.fromJson(<String, dynamic>{
      ...budget.toRow(),
      'id': doc.id,
    });
  }
}
