import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_adjustment.dart';
import '../../domain/models/wallet_transfer.dart';

/// Firestore wallets at `users/{uid}/wallets/{walletId}`.
class WalletRepository {
  WalletRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _wallets =>
      _db.collection('users').doc(_userId).collection('wallets');

  Future<List<Wallet>> fetchAll() async {
    final snapshot = await _wallets.get();
    final wallets = <Wallet>[
      for (final doc in snapshot.docs)
        Wallet.fromJson(<String, dynamic>{...doc.data(), 'id': doc.id},
            id: doc.id),
    ]..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return wallets;
  }

  Future<Wallet> save(Wallet wallet) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _wallets.doc(wallet.id).set(<String, dynamic>{
      ...wallet.toRow(),
      'user_id': _userId,
      'created_at': wallet.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    }, SetOptions(merge: true));
    return Wallet.fromJson(<String, dynamic>{
      ...wallet.toRow(),
      'id': wallet.id,
      'created_at': wallet.createdAt.toUtc().toIso8601String(),
      'updated_at': now,
    }, id: wallet.id);
  }

  Future<void> delete(String id) => _wallets.doc(id).delete();
}

/// Firestore transfers at `users/{uid}/wallet_transfers/{transferId}`.
class WalletTransferRepository {
  WalletTransferRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _transfers =>
      _db.collection('users').doc(_userId).collection('wallet_transfers');

  Future<List<WalletTransfer>> fetchAll({int limit = 5000}) async {
    final snapshot = await _transfers
        .orderBy('occurred_at', descending: true)
        .limit(limit)
        .get();
    return <WalletTransfer>[
      for (final doc in snapshot.docs)
        WalletTransfer.fromJson(
          <String, dynamic>{...doc.data(), 'id': doc.id},
          id: doc.id,
        ),
    ];
  }

  Future<WalletTransfer> create(WalletTransfer transfer) async {
    final doc = _transfers.doc();
    final now = DateTime.now().toUtc().toIso8601String();
    await doc.set(<String, dynamic>{
      ...transfer.toRow(),
      'user_id': _userId,
      'created_at': now,
      'updated_at': now,
    });
    return WalletTransfer.fromJson(<String, dynamic>{
      ...transfer.toRow(),
      'id': doc.id,
      'user_id': _userId,
      'created_at': now,
      'updated_at': now,
    }, id: doc.id);
  }

  Future<void> delete(String id) => _transfers.doc(id).delete();
}

/// Firestore adjustments at `users/{uid}/wallet_adjustments/{adjustmentId}`.
class WalletAdjustmentRepository {
  WalletAdjustmentRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  CollectionReference<Map<String, dynamic>> get _adjustments =>
      _db.collection('users').doc(_userId).collection('wallet_adjustments');

  Future<List<WalletAdjustment>> fetchAll({int limit = 5000}) async {
    final snapshot = await _adjustments
        .orderBy('occurred_at', descending: true)
        .limit(limit)
        .get();
    return <WalletAdjustment>[
      for (final doc in snapshot.docs)
        WalletAdjustment.fromJson(
          <String, dynamic>{...doc.data(), 'id': doc.id},
          id: doc.id,
        ),
    ];
  }

  Future<WalletAdjustment> create(WalletAdjustment adjustment) async {
    final doc = _adjustments.doc();
    final now = DateTime.now().toUtc().toIso8601String();
    await doc.set(<String, dynamic>{
      ...adjustment.toRow(),
      'user_id': _userId,
      'created_at': now,
      'updated_at': now,
    });
    return WalletAdjustment.fromJson(<String, dynamic>{
      ...adjustment.toRow(),
      'id': doc.id,
      'user_id': _userId,
      'created_at': now,
      'updated_at': now,
    }, id: doc.id);
  }

  Future<void> delete(String id) => _adjustments.doc(id).delete();
}
