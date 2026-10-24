import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/income_entry.dart';
import '../../domain/models/income_source.dart';
import '../../domain/models/monthly_budget.dart';
import '../../domain/models/pay_cycle.dart';

/// Firestore income sources at `users/{uid}/income_sources/{sourceId}`.
class IncomeSourceRepository {
  IncomeSourceRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _sources =>
      _db.collection('users').doc(_userId).collection('income_sources');

  DocumentReference<Map<String, dynamic>> get _meta =>
      _db.collection('users').doc(_userId).collection('income_meta').doc('state');

  Future<List<IncomeSource>> fetchAll() async {
    final snapshot = await _sources.get();
    final sources = <IncomeSource>[
      for (final doc in snapshot.docs)
        IncomeSource.fromJson(
          <String, dynamic>{...doc.data(), 'id': doc.id},
          id: doc.id,
        ),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return normalizeBudgetPeriodFlag(sources);
  }

  Future<IncomeSource> save(IncomeSource source) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _sources.doc(source.id).set(<String, dynamic>{
      ...source.toRow(),
      'user_id': _userId,
      'created_at': source.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    }, SetOptions(merge: true));
    return IncomeSource.fromJson(
      <String, dynamic>{
        ...source.toRow(),
        'id': source.id,
        'created_at': source.createdAt.toUtc().toIso8601String(),
        'updated_at': now,
      },
      id: source.id,
    );
  }

  Future<void> saveAll(Iterable<IncomeSource> sources) async {
    final batch = _db.batch();
    final now = DateTime.now().toUtc().toIso8601String();
    for (final source in sources) {
      batch.set(_sources.doc(source.id), <String, dynamic>{
        ...source.toRow(),
        'user_id': _userId,
        'created_at': source.createdAt.toUtc().toIso8601String(),
        'updated_at': now,
      }, SetOptions(merge: true));
    }
    await batch.commit();
  }

  Future<void> delete(String id) => _sources.doc(id).delete();

  /// Creates the first source from the pre-Phase-1 single pay cycle.
  ///
  /// Runs only once per user: a marker document in `income_meta/state` keeps
  /// an intentionally emptied list from being re-seeded.
  Future<List<IncomeSource>> ensureSeeded({
    required PayCycleConfig legacyConfig,
    required MonthlyBudget? latestBudget,
    required String currency,
  }) async {
    final existing = await fetchAll();
    if (existing.isNotEmpty) return existing;

    final meta = await _meta.get();
    if (meta.data()?['income_sources_migrated'] == true) {
      return const <IncomeSource>[];
    }

    final now = DateTime.now();
    // A brand-new account has no legacy cycle/plan to migrate. Start with an
    // empty list so the user adds their real sources (and mark the migration
    // as done so a later budget save does not create a surprise "Main").
    final hasLegacyCycle = latestBudget != null ||
        legacyConfig.cycle != PayCycle.monthly ||
        legacyConfig.monthlyPayDay != 1 ||
        legacyConfig.weeklyStartWeekday != DateTime.monday;
    if (!hasLegacyCycle) {
      await _meta.set(<String, dynamic>{
        'income_sources_migrated': true,
        'updated_at': now.toUtc().toIso8601String(),
      }, SetOptions(merge: true));
      return const <IncomeSource>[];
    }

    final source = legacyIncomeSource(
      legacyConfig: legacyConfig,
      latestBudget: latestBudget,
      currency: currency,
      createdAt: now,
    );

    final batch = _db.batch();
    final nowIso = now.toUtc().toIso8601String();
    batch.set(_sources.doc(source.id), <String, dynamic>{
      ...source.toRow(),
      'user_id': _userId,
      'created_at': nowIso,
      'updated_at': nowIso,
    });
    batch.set(_meta, <String, dynamic>{
      'income_sources_migrated': true,
      'updated_at': nowIso,
    }, SetOptions(merge: true));
    await batch.commit();
    return <IncomeSource>[source];
  }
}

/// Firestore one-off income at `users/{uid}/income_entries/{entryId}`.
class IncomeEntryRepository {
  IncomeEntryRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _entries =>
      _db.collection('users').doc(_userId).collection('income_entries');

  Future<List<IncomeEntry>> fetchAll({int limit = 5000}) async {
    final snapshot = await _entries
        .orderBy('received_at', descending: true)
        .limit(limit)
        .get();
    return <IncomeEntry>[
      for (final doc in snapshot.docs)
        IncomeEntry.fromJson(
          <String, dynamic>{...doc.data(), 'id': doc.id},
          id: doc.id,
        ),
    ];
  }

  Future<IncomeEntry> create(IncomeEntry entry) async {
    final doc = _entries.doc();
    final now = DateTime.now().toUtc().toIso8601String();
    await doc.set(<String, dynamic>{
      ...entry.toRow(),
      'user_id': _userId,
      'created_at': now,
      'updated_at': now,
    });
    return IncomeEntry.fromJson(
      <String, dynamic>{
        ...entry.toRow(),
        'id': doc.id,
        'user_id': _userId,
        'created_at': now,
        'updated_at': now,
      },
      id: doc.id,
    );
  }

  Future<void> delete(String id) => _entries.doc(id).delete();
}
