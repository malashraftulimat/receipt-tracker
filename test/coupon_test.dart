import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/ocr/ai_receipt_ocr_service.dart';

void main() {
  group('coupon extraction', () {
    test('parses name, validity window and discount', () {
      final coupon = AiReceiptOcrService.parseCoupon(<String, Object?>{
        'name': '次回使える500円クーポン',
        'valid_from': '2026-10-01',
        'valid_until': '2026-11-30',
        'discount_amount_or_percent': '500',
      });

      expect(coupon, isNotNull);
      expect(coupon!.name, '次回使える500円クーポン');
      expect(coupon.validFrom, DateTime(2026, 10, 1));
      expect(coupon.validUntil, DateTime(2026, 11, 30));
      expect(coupon.discountAmountOrPercent, '500');
    });

    test('keeps null validity and discount when not printed', () {
      final coupon = AiReceiptOcrService.parseCoupon(<String, Object?>{
        'name': 'ドリンク10%OFF',
        'valid_from': null,
        'valid_until': null,
        'discount_amount_or_percent': '10%',
      });

      expect(coupon, isNotNull);
      expect(coupon!.validFrom, isNull);
      expect(coupon.validUntil, isNull);
      expect(coupon.discountAmountOrPercent, '10%');
      expect(coupon.isExpired(), isFalse);
    });

    test('returns null when there is no usable coupon name', () {
      expect(AiReceiptOcrService.parseCoupon(null), isNull);
      expect(AiReceiptOcrService.parseCoupon('クーポン'), isNull);
      expect(
        AiReceiptOcrService.parseCoupon(<String, Object?>{'name': '   '}),
        isNull,
      );
    });

    test('expiry covers the whole printed day', () {
      final coupon = AiReceiptOcrService.parseCoupon(<String, Object?>{
        'name': 'クーポン',
        'valid_until': '2026-10-22',
      });

      expect(coupon!.isExpired(at: DateTime(2026, 10, 22, 23, 59)), isFalse);
      expect(coupon.isExpired(at: DateTime(2026, 10, 23)), isTrue);
    });

    test('normalises Japanese era validity dates', () {
      final coupon = AiReceiptOcrService.parseCoupon(<String, Object?>{
        'name': 'お食事券',
        'valid_from': '令和8年10月1日',
        'valid_until': '令和8年12月31日',
      });

      expect(coupon!.validFrom, DateTime(2026, 10, 1));
      expect(coupon.validUntil, DateTime(2026, 12, 31));
      expect(coupon.discountAmountOrPercent, isNull);
    });
  });
}
