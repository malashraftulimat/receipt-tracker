import 'dart:async';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../domain/models/coupon.dart';
import 'coupon_action_store.dart';

/// Called when the user picks a notification action while the app is running.
typedef CouponActionCallback = Future<void> Function(CouponAction action);

/// Entry point used by the plugin when an action is pressed on a notification
/// while the app is terminated / in the background (Android + iOS).
///
/// Runs in a separate isolate: no Firestore here. It records the action in the
/// SharedPreferences journal and cancels the coupon's pending reminders. The
/// app applies the journal on its next launch.
@pragma('vm:entry-point')
Future<void> couponNotificationBackgroundHandler(
  NotificationResponse response,
) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final action = CouponActionStore.fromResponse(
    payload: response.payload,
    actionId: response.actionId,
  );
  if (action == null) return;

  await CouponActionStore().add(action);
  await CouponNotificationScheduler().cancelCoupon(action.couponId);
}

/// Schedules the daily coupon reminders.
///
/// * Android / iOS / macOS: one notification per active coupon per day at
///   [reminderHour], up to the coupon's `validUntil` (capped at
///   [_maxScheduledDays]).
/// * Web: browsers cannot schedule notifications, so the same notification is
///   shown at most once per day when the app is opened.
class CouponNotificationScheduler {
  CouponNotificationScheduler({
    FlutterLocalNotificationsPlugin? plugin,
    CouponActionStore? store,
    this.reminderHour = 9,
  })  : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _store = store ?? CouponActionStore();

  static const String channelId = 'coupon_reminders';
  static const String channelName = 'クーポンのお知らせ';
  static const String categoryId = 'coupon_reminder';
  static const int _maxScheduledDays = 90;
  static const int _maxNotificationIds = 128;

  final FlutterLocalNotificationsPlugin _plugin;
  final CouponActionStore _store;

  /// Local hour of the daily reminder (24h clock).
  final int reminderHour;

  bool _initialized = false;
  CouponActionCallback? _onAction;

  static final List<DarwinNotificationCategory> _darwinCategories =
      <DarwinNotificationCategory>[
    DarwinNotificationCategory(
      categoryId,
      actions: <DarwinNotificationAction>[
        DarwinNotificationAction.plain('coupon_used', 'Mark as Used'),
        DarwinNotificationAction.plain('coupon_tomorrow', 'Remind Tomorrow'),
      ],
    ),
  ];

  static const NotificationDetails _details = NotificationDetails(
    android: AndroidNotificationDetails(
      channelId,
      channelName,
      channelDescription: '有効期限が近づいたクーポンを毎日お知らせします',
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction('coupon_used', 'Mark as Used'),
        AndroidNotificationAction('coupon_tomorrow', 'Remind Tomorrow'),
      ],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: categoryId),
    macOS: DarwinNotificationDetails(categoryIdentifier: categoryId),
    web: WebNotificationDetails(
      requireInteraction: true,
      actions: <WebNotificationAction>[
        WebNotificationAction(action: 'coupon_used', title: 'Mark as Used'),
        WebNotificationAction(action: 'coupon_tomorrow', title: 'Remind Tomorrow'),
      ],
    ),
  );

  bool get supportsScheduling => !kIsWeb;

  /// Initialises the plugin and registers the foreground action handler.
  Future<void> initialize({CouponActionCallback? onAction}) async {
    _onAction = onAction;
    if (_initialized) return;

    try {
      await _plugin.initialize(
        settings: InitializationSettings(
          android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: _darwinCategories,
          ),
          macOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
            notificationCategories: _darwinCategories,
          ),
          web: const WebInitializationSettings(),
        ),
        onDidReceiveNotificationResponse: _handleResponse,
        onDidReceiveBackgroundNotificationResponse:
            couponNotificationBackgroundHandler,
      );
      _initialized = true;
    } catch (error) {
      // Notifications are optional: never block the app on a plugin failure.
      debugPrint('[CouponScheduler] initialize failed: $error');
    }
  }

  /// Asks for notification permission. Must be triggered by a user gesture on
  /// the web, so it is only called from an explicit button press.
  Future<bool> requestPermission() async {
    await initialize(onAction: _onAction);
    try {
      if (kIsWeb) {
        final web = _plugin.resolvePlatformSpecificImplementation<
            WebFlutterLocalNotificationsPlugin>();
        if (web == null) return false;
        if (web.permissionStatus == WebNotificationPermission.granted) {
          return true;
        }
        return await web.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.android) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
      if (defaultTargetPlatform == TargetPlatform.macOS) {
        final macos = _plugin.resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin>();
        return await macos?.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }
    } catch (error) {
      debugPrint('[CouponScheduler] permission request failed: $error');
    }
    return false;
  }

  /// Replaces every scheduled coupon reminder with the current active set.
  Future<void> scheduleAll(List<Coupon> coupons, {DateTime? now}) async {
    await initialize(onAction: _onAction);
    if (!_initialized) return;

    if (kIsWeb) {
      await showDueReminders(coupons, now: now);
      return;
    }

    try {
      await _plugin.cancelAll();
    } catch (error) {
      debugPrint('[CouponScheduler] cancelAll failed: $error');
    }

    final current = now ?? DateTime.now();
    for (final coupon in coupons) {
      if (!coupon.isUsableAt(current)) continue;
      await _scheduleCoupon(coupon, current);
    }
  }

  /// Schedules the daily reminders for one coupon.
  Future<void> _scheduleCoupon(Coupon coupon, DateTime now) async {
    final today = _dateOnly(now);
    final from = coupon.validFrom == null ? today : _dateOnly(coupon.validFrom!);
    final remindAfter = await _store.remindAfter(coupon.id);
    var start = from.isAfter(today) ? from : today;
    if (remindAfter != null && _dateOnly(remindAfter).isAfter(start)) {
      start = _dateOnly(remindAfter);
    }
    final wantedEnd = coupon.validUntil == null
        ? start.add(const Duration(days: 30))
        : _dateOnly(coupon.validUntil!);
    final maxEnd = start.add(const Duration(days: _maxScheduledDays - 1));
    final end = wantedEnd.isAfter(maxEnd) ? maxEnd : wantedEnd;
    final payload = CouponActionStore.encodePayload(coupon.id);

    for (var offset = 0; offset < _maxScheduledDays; offset++) {
      final day = start.add(Duration(days: offset));
      if (day.isAfter(end)) break;

      final at = DateTime(day.year, day.month, day.day, reminderHour);
      if (!at.isAfter(now)) continue; // today's slot already passed

      try {
        await _plugin.zonedSchedule(
          id: notificationIdFor(coupon.id, offset),
          title: 'クーポンが使えます',
          body: _body(coupon),
          scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: payload,
        );
      } catch (error) {
        debugPrint('[CouponScheduler] schedule failed: $error');
        break;
      }
    }
  }

  /// Web-only: shows today's reminder for each usable coupon, at most once a
  /// day (browsers cannot schedule future notifications).
  Future<void> showDueReminders(List<Coupon> coupons, {DateTime? now}) async {
    if (!kIsWeb || !_initialized) return;

    final web = _plugin.resolvePlatformSpecificImplementation<
        WebFlutterLocalNotificationsPlugin>();
    if (web == null || web.permissionStatus != WebNotificationPermission.granted) {
      return;
    }

    final current = now ?? DateTime.now();
    final todayDate = _dateOnly(current);
    final today = CouponActionStore.dateKey(current);
    for (final coupon in coupons) {
      if (!coupon.isUsableAt(current)) continue;

      final remindAfter = await _store.remindAfter(coupon.id);
      if (remindAfter != null && _dateOnly(remindAfter).isAfter(todayDate)) {
        continue; // user chose "Remind Tomorrow"
      }

      final lastShown = await _store.lastNotifiedOn(coupon.id);
      if (lastShown == today) continue;

      try {
        await _plugin.show(
          id: notificationIdFor(coupon.id, 0),
          title: 'クーポンが使えます',
          body: _body(coupon),
          notificationDetails: _details,
          payload: CouponActionStore.encodePayload(coupon.id),
        );
        await _store.markNotified(coupon.id, current);
      } catch (error) {
        debugPrint('[CouponScheduler] show failed: $error');
      }
    }
  }

  /// Cancels every pending reminder for [couponId].
  ///
  /// Ids are derived from the coupon id, so this also works from the background
  /// isolate without any stored state.
  Future<void> cancelCoupon(String couponId) async {
    for (var offset = 0; offset < _maxNotificationIds; offset++) {
      try {
        await _plugin.cancel(id: notificationIdFor(couponId, offset));
      } catch (error) {
        debugPrint('[CouponScheduler] cancel failed: $error');
        break;
      }
    }
  }

  Future<void> _handleResponse(NotificationResponse response) async {
    final action = CouponActionStore.fromResponse(
      payload: response.payload,
      actionId: response.actionId,
    );
    if (action == null) return;
    final callback = _onAction;
    if (callback != null) await callback(action);
  }

  String _body(Coupon coupon) {
    final parts = <String>[coupon.name];
    final discount = coupon.discountAmountOrPercent;
    if (discount != null && discount.isNotEmpty) parts.add(discount);
    final until = coupon.validUntil;
    if (until != null) {
      parts.add('${until.year}/${until.month}/${until.day} まで');
    } else {
      parts.add('有効期限なし');
    }
    return parts.join(' ・ ');
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  /// Stable notification id for a coupon and day offset (0..127).
  ///
  /// 24-bit FNV-1a hash * 128 + offset stays inside the 31-bit id range used by
  /// Android/iOS.
  @visibleForTesting
  static int notificationIdFor(String couponId, int dayOffset) {
    var hash = 0x811c9dc5;
    for (final unit in couponId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    final base = hash & 0xFFFFFF;
    return base * _maxNotificationIds + (dayOffset % _maxNotificationIds);
  }
}
