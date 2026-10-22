import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/coupons/coupon_action_store.dart';
import 'package:receipt_tracker/data/services/coupons/coupon_notification_scheduler.dart';
import 'package:receipt_tracker/domain/models/coupon.dart';
import 'package:receipt_tracker/domain/parser/receipt_parser.dart';
import 'package:shared_preferences/shared_preferences.dart';

Coupon _coupon({
  CouponStatus status = CouponStatus.active,
  DateTime? validFrom,
  DateTime? validUntil,
}) =>
    Coupon(
      id: 'coupon-1',
      name: '次回使える500円クーポン',
      merchant: 'テストストア',
      validFrom: validFrom,
      validUntil: validUntil,
      discountAmountOrPercent: '500',
      status: status,
      createdAt: DateTime(2026, 10, 1, 12),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Coupon validity', () {
    test('stays usable for the whole validUntil day', () {
      final coupon = _coupon(validUntil: DateTime(2026, 10, 22));

      expect(coupon.isUsableAt(DateTime(2026, 10, 22, 0, 1)), isTrue);
      expect(coupon.isUsableAt(DateTime(2026, 10, 22, 23, 59)), isTrue);
      expect(coupon.isExpiredAt(DateTime(2026, 10, 23)), isTrue);
      expect(coupon.isUsableAt(DateTime(2026, 10, 23)), isFalse);
      expect(coupon.daysUntilExpiry(DateTime(2026, 10, 20, 15)), 2);
      expect(coupon.daysUntilExpiry(DateTime(2026, 10, 22, 15)), 0);
    });

    test('respects validFrom and no-expiry coupons', () {
      final future = _coupon(validFrom: DateTime(2026, 11, 1));
      final open = _coupon();

      expect(future.isUsableAt(DateTime(2026, 10, 31)), isFalse);
      expect(future.isUsableAt(DateTime(2026, 11, 1)), isTrue);
      expect(open.isUsableAt(DateTime(2030, 1, 1)), isTrue);
      expect(open.daysUntilExpiry(DateTime(2030, 1, 1)), isNull);
    });

    test('used and expired coupons are not usable', () {
      final used = _coupon(status: CouponStatus.used);
      final expired = _coupon(
        status: CouponStatus.expired,
        validUntil: DateTime(2026, 10, 1),
      );

      expect(used.isUsableAt(DateTime(2026, 10, 2)), isFalse);
      expect(expired.isUsableAt(DateTime(2026, 10, 2)), isFalse);
      expect(expired.statusAt(DateTime(2026, 10, 2)), CouponStatus.expired);
    });

    test('statusAt expires only after the last day', () {
      final coupon = _coupon(validUntil: DateTime(2026, 10, 22));

      expect(coupon.statusAt(DateTime(2026, 10, 22, 23)), CouponStatus.active);
      expect(coupon.statusAt(DateTime(2026, 10, 23)), CouponStatus.expired);
      expect(
        coupon
            .withStatus(CouponStatus.used)
            .statusAt(DateTime(2027, 1, 1)),
        CouponStatus.used,
      );
    });
  });

  group('Coupon serialisation', () {
    test('roundtrips Firestore fields with date-only values', () {
      final coupon = _coupon(
        validFrom: DateTime(2026, 10, 1, 18, 30),
        validUntil: DateTime(2026, 11, 30, 9),
      );
      final json = coupon.toJson();
      final restored = Coupon.fromJson(
        jsonDecode(jsonEncode(json)) as Map<String, dynamic>,
        id: coupon.id,
      );

      expect(json['valid_from'], '2026-10-01');
      expect(json['valid_until'], '2026-11-30');
      expect(json['status'], 'active');
      expect(restored.name, coupon.name);
      expect(restored.merchant, coupon.merchant);
      expect(restored.validFrom, DateTime(2026, 10, 1));
      expect(restored.validUntil, DateTime(2026, 11, 30));
      expect(restored.discountAmountOrPercent, '500');
      expect(restored.status, CouponStatus.active);
    });

    test('builds from OCR output', () {
      final parsed = ParsedCoupon(
        name: 'ドリンク10%OFF',
        validFrom: DateTime(2026, 12, 1),
        validUntil: DateTime(2026, 12, 31),
        discountAmountOrPercent: '10%',
      );
      final coupon = Coupon.fromParsed(
        'doc-1',
        parsed,
        merchant: 'カフェ',
        receiptId: 'receipt-9',
        createdAt: DateTime(2026, 11, 20),
      );

      expect(coupon.id, 'doc-1');
      expect(coupon.name, 'ドリンク10%OFF');
      expect(coupon.merchant, 'カフェ');
      expect(coupon.receiptId, 'receipt-9');
      expect(coupon.validFrom, DateTime(2026, 12, 1));
      expect(coupon.validUntil, DateTime(2026, 12, 31));
      expect(coupon.discountAmountOrPercent, '10%');
      expect(coupon.status, CouponStatus.active);
    });
  });

  group('CouponActionStore', () {
    late CouponActionStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      store = CouponActionStore(
        preferences: await SharedPreferences.getInstance(),
      );
    });

    test('journals actions and drains them atomically', () async {
      await store.add(
        const CouponAction(
          couponId: 'c1',
          kind: CouponActionKind.used,
        ),
      );
      await store.add(
        const CouponAction(
          couponId: 'c2',
          kind: CouponActionKind.remindTomorrow,
        ),
      );

      expect((await store.peek()).length, 2);
      final actions = await store.takeAll();
      expect(actions.map((a) => a.couponId), <String>['c1', 'c2']);
      expect(actions.first.kind, CouponActionKind.used);
      expect(await store.peek(), isEmpty);
    });

    test('parses notification responses and payloads', () {
      final payload = CouponActionStore.encodePayload('coupon-42');
      final action = CouponActionStore.fromResponse(
        payload: payload,
        actionId: 'coupon_tomorrow',
      );

      expect(action, isNotNull);
      expect(action!.couponId, 'coupon-42');
      expect(action.kind, CouponActionKind.remindTomorrow);
      expect(
        CouponActionStore.fromResponse(payload: payload, actionId: null),
        isNull,
      );
      expect(
        CouponActionStore.fromResponse(payload: 'not-json', actionId: 'coupon_used'),
        isNull,
      );
    });

    test('remembers the last notification day per coupon', () async {
      expect(await store.lastNotifiedOn('c1'), isNull);
      await store.markNotified('c1', DateTime(2026, 10, 22, 9));
      expect(await store.lastNotifiedOn('c1'), '2026-10-22');
      expect(await store.lastNotifiedOn('c2'), isNull);
    });

    test('records the resume day for Remind Tomorrow', () async {
      expect(await store.remindAfter('c1'), isNull);
      await store.setRemindAfter('c1', DateTime(2026, 10, 23));
      expect(await store.remindAfter('c1'), DateTime(2026, 10, 23));

      await store.clearRemindAfter('c1');
      expect(await store.remindAfter('c1'), isNull);
    });
  });

  group('notification ids', () {
    test('are stable, distinct and inside the 31-bit range', () {
      final first = CouponNotificationScheduler.notificationIdFor('coupon-a', 0);
      final second =
          CouponNotificationScheduler.notificationIdFor('coupon-a', 1);
      final other = CouponNotificationScheduler.notificationIdFor('coupon-b', 0);

      expect(CouponNotificationScheduler.notificationIdFor('coupon-a', 0), first);
      expect(second, first + 1);
      expect(other, isNot(first));
      expect(first, greaterThanOrEqualTo(0));
      expect(
        CouponNotificationScheduler.notificationIdFor('zzzzzzzzzzzzzzzz', 127),
        lessThan(1 << 31),
      );
    });
  });
}
