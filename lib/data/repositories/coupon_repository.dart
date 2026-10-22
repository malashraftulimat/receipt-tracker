import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../domain/models/coupon.dart';
import '../../domain/parser/receipt_parser.dart';
import '../services/coupons/coupon_action_store.dart';

/// Firestore coupons at `users/{userId}/coupons/{couponId}`.
///
/// Coupons are created when a scanned receipt prints one, and are marked
/// `used` from notification actions / the coupon list. `expireOverdue()`
/// flips `active` coupons to `expired` after their `validUntil` day.
class CouponRepository {
  CouponRepository([FirebaseFirestore? firestore, CouponActionStore? store])
      : _db = firestore ?? FirebaseFirestore.instance,
        _store = store ?? CouponActionStore();

  final FirebaseFirestore _db;
  final CouponActionStore _store;

  String get _userId {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    return user.uid;
  }

  bool get _signedIn => FirebaseAuth.instance.currentUser != null;

  CollectionReference<Map<String, dynamic>> get _coupons =>
      _db.collection('users').doc(_userId).collection('coupons');

  Future<List<Coupon>> fetchAll() async {
    if (!_signedIn) return const <Coupon>[];
    final snapshot = await _coupons
        .orderBy('created_at', descending: true)
        .limit(500)
        .get();
    return snapshot.docs
        .map((doc) => Coupon.fromJson(doc.data(), id: doc.id))
        .where((coupon) => coupon.name.isNotEmpty)
        .toList(growable: false);
  }

  /// Saves the coupon printed on a receipt, avoiding duplicates from rescans.
  Future<Coupon?> createFromParsed(
    ParsedCoupon parsed, {
    String? receiptId,
    String? merchant,
    DateTime? now,
  }) async {
    if (!_signedIn) return null;

    final current = now ?? DateTime.now();
    final name = parsed.name.trim();
    if (name.isEmpty) return null;

    final existing = await fetchAll();
    final normalized = name.toLowerCase();
    for (final coupon in existing) {
      final sameName = coupon.name.trim().toLowerCase() == normalized;
      final sameExpiry = _sameDay(coupon.validUntil, parsed.validUntil);
      if (sameName &&
          sameExpiry &&
          coupon.status != CouponStatus.used) {
        return coupon;
      }
    }

    final doc = _coupons.doc();
    final coupon = Coupon.fromParsed(
      doc.id,
      parsed,
      merchant: merchant,
      receiptId: receiptId,
      createdAt: current,
    );
    await doc.set(coupon.toJson());
    return coupon;
  }

  Future<void> updateStatus(String couponId, CouponStatus status) async {
    if (!_signedIn) return;
    await _coupons.doc(couponId).set(
      <String, dynamic>{
        'status': status.value,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      },
      SetOptions(merge: true),
    );
  }

  Future<void> delete(String couponId) async {
    if (!_signedIn) return;
    await _coupons.doc(couponId).delete();
  }

  /// Marks active coupons whose `validUntil` day has passed as expired.
  ///
  /// Returns the number of coupons updated in Firestore.
  Future<int> expireOverdue({DateTime? now}) async {
    if (!_signedIn) return 0;
    final current = now ?? DateTime.now();

    final snapshot = await _coupons
        .where('status', isEqualTo: CouponStatus.active.value)
        .limit(500)
        .get();

    final batch = _db.batch();
    var updated = 0;
    for (final doc in snapshot.docs) {
      final coupon = Coupon.fromJson(doc.data(), id: doc.id);
      if (!coupon.isExpiredAt(current)) continue;
      batch.set(
        doc.reference,
        <String, dynamic>{
          'status': CouponStatus.expired.value,
          'updated_at': current.toUtc().toIso8601String(),
        },
        SetOptions(merge: true),
      );
      updated++;
    }
    if (updated > 0) await batch.commit();
    return updated;
  }

  /// Applies actions recorded by the notification background isolate.
  ///
  /// "Mark as Used" becomes a Firestore status change; "Remind Tomorrow"
  /// records the resume day in the local reminder store.
  Future<int> applyPendingActions() async {
    if (!_signedIn) return 0;
    final actions = await _store.takeAll();
    var applied = 0;
    for (final action in actions) {
      try {
        if (action.kind == CouponActionKind.used) {
          await updateStatus(action.couponId, CouponStatus.used);
          await _store.clearRemindAfter(action.couponId);
        } else {
          await _store.setRemindAfter(
            action.couponId,
            DateTime.now().add(const Duration(days: 1)),
          );
        }
        applied++;
      } catch (error) {
        debugPrint('[CouponRepository] action failed: $error');
      }
    }
    return applied;
  }

  static bool _sameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return a == b;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
