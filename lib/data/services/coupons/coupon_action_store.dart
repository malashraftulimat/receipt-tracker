import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Notification action selected by the user.
enum CouponActionKind {
  used('coupon_used'),
  remindTomorrow('coupon_tomorrow');

  const CouponActionKind(this.actionId);

  /// Stable id shared with the Android / iOS / web action buttons.
  final String actionId;

  static CouponActionKind? fromActionId(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final kind in CouponActionKind.values) {
      if (kind.actionId == value) return kind;
    }
    return null;
  }
}

/// A "Mark as Used" / "Remind Tomorrow" selection.
class CouponAction {
  const CouponAction({
    required this.couponId,
    required this.kind,
    this.requestedAt,
  });

  final String couponId;
  final CouponActionKind kind;
  final DateTime? requestedAt;
}

/// Small local journal shared with notification action handlers.
///
/// Actions pressed while the app is terminated are executed in a background
/// isolate (Android/iOS). That isolate cannot safely use Firestore, so it
/// appends the action here (SharedPreferences) and cancels the coupon's
/// notifications. The app drains the journal on the next launch and writes the
/// status change to Firestore.
class CouponActionStore {
  CouponActionStore({SharedPreferences? preferences})
      : _preferences = preferences;

  static const String pendingKey = 'coupon_pending_actions';
  static const String _notifiedPrefix = 'coupon_notified_';
  static const String _remindAfterPrefix = 'coupon_remind_after_';
  static const String _notifiedSeparator = '|';

  SharedPreferences? _preferences;

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<void> add(CouponAction action) async {
    final prefs = await _prefs;
    final entries = prefs.getStringList(pendingKey) ?? <String>[];
    entries.add(jsonEncode(<String, Object?>{
      'couponId': action.couponId,
      'action': action.kind.actionId,
      'requestedAt':
          (action.requestedAt ?? DateTime.now()).toUtc().toIso8601String(),
    }));
    await prefs.setStringList(pendingKey, entries);
  }

  /// Reads and clears the journal.
  Future<List<CouponAction>> takeAll() async {
    final prefs = await _prefs;
    // Pick up actions written by the notification background isolate.
    await prefs.reload();
    final entries = prefs.getStringList(pendingKey) ?? const <String>[];
    if (entries.isEmpty) return const <CouponAction>[];
    await prefs.remove(pendingKey);
    return entries.map(parseEntry).whereType<CouponAction>().toList();
  }

  Future<List<CouponAction>> peek() async {
    final prefs = await _prefs;
    await prefs.reload();
    return (prefs.getStringList(pendingKey) ?? const <String>[])
        .map(parseEntry)
        .whereType<CouponAction>()
        .toList();
  }

  /// Last day a notification was shown for [couponId] (`YYYY-MM-DD`).
  Future<String?> lastNotifiedOn(String couponId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_notifiedPrefix$couponId');
    if (raw == null) return null;
    return raw.split(_notifiedSeparator).first;
  }

  Future<void> markNotified(String couponId, DateTime day) async {
    final prefs = await _prefs;
    await prefs.setString(
      '$_notifiedPrefix$couponId',
      '${dateKey(day)}$_notifiedSeparator${day.toUtc().toIso8601String()}',
    );
  }

  /// `YYYY-MM-DD` key for local-calendar comparisons.
  static String dateKey(DateTime day) {
    final month = day.month.toString().padLeft(2, '0');
    final date = day.day.toString().padLeft(2, '0');
    return '${day.year.toString().padLeft(4, '0')}-$month-$date';
  }

  /// First day reminders may resume after "Remind Tomorrow".
  Future<DateTime?> remindAfter(String couponId) async {
    final prefs = await _prefs;
    final raw = prefs.getString('$_remindAfterPrefix$couponId');
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setRemindAfter(String couponId, DateTime day) async {
    final prefs = await _prefs;
    await prefs.setString('$_remindAfterPrefix$couponId', dateKey(day));
  }

  Future<void> clearRemindAfter(String couponId) async {
    final prefs = await _prefs;
    await prefs.remove('$_remindAfterPrefix$couponId');
  }

  /// Notification payload (coupon id only; the action comes from the response).
  static String encodePayload(String couponId) =>
      jsonEncode(<String, Object?>{'couponId': couponId});

  /// Builds an action from a notification response.
  static CouponAction? fromResponse({
    String? payload,
    String? actionId,
  }) {
    final kind = CouponActionKind.fromActionId(actionId);
    if (kind == null) return null;

    String? couponId;
    if (payload != null && payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map) {
          final value = decoded['couponId'];
          if (value is String && value.isNotEmpty) couponId = value;
        }
      } on FormatException {
        couponId = null;
      }
    }
    if (couponId == null) return null;
    return CouponAction(couponId: couponId, kind: kind);
  }

  static CouponAction? parseEntry(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final couponId = decoded['couponId'];
      final kind = CouponActionKind.fromActionId(
        decoded['action'] is String ? decoded['action'] as String : null,
      );
      if (couponId is! String || couponId.isEmpty || kind == null) return null;
      final requestedAt = decoded['requestedAt'];
      return CouponAction(
        couponId: couponId,
        kind: kind,
        requestedAt:
            requestedAt is String ? DateTime.tryParse(requestedAt) : null,
      );
    } on FormatException {
      return null;
    }
  }
}
