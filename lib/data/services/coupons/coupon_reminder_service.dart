import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../../domain/models/coupon.dart';
import '../../repositories/coupon_repository.dart';
import 'coupon_action_store.dart';
import 'coupon_notification_scheduler.dart';

/// Coordinates coupon persistence, expiry and local reminders.
class CouponReminderService {
  CouponReminderService({
    required CouponRepository repository,
    CouponNotificationScheduler? scheduler,
    CouponActionStore? store,
  })  : _repository = repository,
        _scheduler = scheduler ?? CouponNotificationScheduler(),
        _store = store ?? CouponActionStore();

  final CouponRepository _repository;
  final CouponNotificationScheduler _scheduler;
  final CouponActionStore _store;

  bool _started = false;
  Future<void>? _running;

  CouponNotificationScheduler get scheduler => _scheduler;

  /// Initialises notifications and runs the first sync. Safe to call twice.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    await _scheduler.initialize(onAction: handleAction);
    await sync();
  }

  /// Applies queued notification actions, expires overdue coupons and
  /// (re)schedules reminders for the currently usable coupons.
  Future<void> sync() {
    // Serialise concurrent syncs (startup + auth change + save).
    final running = _running;
    if (running != null) return running;
    final future = _syncOnce();
    _running = future;
    return future.whenComplete(() => _running = null);
  }

  Future<void> _syncOnce() async {
    if (FirebaseAuth.instance.currentUser == null) return;
    try {
      await _repository.applyPendingActions();
      await _repository.expireOverdue();
      final coupons = await _repository.fetchAll();
      final now = DateTime.now();
      final usable = coupons
          .where((coupon) => coupon.isUsableAt(now))
          .toList(growable: false);
      // scheduleAll also shows today's reminder on web (no scheduling there).
      await _scheduler.scheduleAll(usable);
    } catch (error) {
      debugPrint('[CouponReminderService] sync failed: $error');
    }
  }

  /// Handles an action pressed on a notification while the app is running.
  Future<void> handleAction(CouponAction action) async {
    if (action.kind == CouponActionKind.used) {
      try {
        await _repository.updateStatus(action.couponId, CouponStatus.used);
        await _scheduler.cancelCoupon(action.couponId);
        await _store.clearRemindAfter(action.couponId);
      } catch (error) {
        debugPrint('[CouponReminderService] mark used failed: $error');
      }
    } else {
      // Suppress the rest of today and resume with tomorrow's reminder.
      await _store.setRemindAfter(
        action.couponId,
        DateTime.now().add(const Duration(days: 1)),
      );
      await _scheduler.cancelCoupon(action.couponId);
    }
    await sync();
  }

  /// In-app "Mark as Used" / "Remind Tomorrow" buttons.
  Future<void> markUsed(String couponId) =>
      handleAction(CouponAction(couponId: couponId, kind: CouponActionKind.used));

  Future<void> remindTomorrow(String couponId) => handleAction(
        CouponAction(couponId: couponId, kind: CouponActionKind.remindTomorrow),
      );

  /// Requests notification permission (must come from a user gesture on web).
  Future<bool> enableNotifications() => _scheduler.requestPermission();

  /// Remembers that the user already got today's reminder for [couponId].
  Future<void> suppressToday(String couponId) =>
      _store.markNotified(couponId, DateTime.now());

  bool get supportsScheduling => _scheduler.supportsScheduling;
}
