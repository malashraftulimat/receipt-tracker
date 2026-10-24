import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/parser/receipt_amount_check.dart';
import 'package:receipt_tracker/domain/parser/receipt_identity.dart';

void main() {
  group('receipt identity', () {
    test('registration numbers are never receipt numbers', () {
      for (final value in <String>[
        'T8012402001708',
        't8012402001708',
        'Ｔ8012402001708',
      ]) {
        expect(ReceiptIdentity.isInvoiceRegistrationNumber(value), isTrue);
        expect(ReceiptIdentity.normalizeReceiptNumber(value), isNull);
        expect(
          ReceiptIdentity.normalizeInvoiceRegistrationNumber(value),
          'T8012402001708',
        );
      }
    });

    test('two purchases from the same shop with the same T-number differ', () {
      // Both receipts carry the shop's 登録番号, but their own numbers differ.
      const shopRegistration = 'T8012402001708';
      expect(
        ReceiptIdentity.normalizeReceiptNumber(shopRegistration),
        isNull,
      );

      final firstNumber = ReceiptIdentity.normalizeReceiptNumber('0001-2026');
      final secondNumber = ReceiptIdentity.normalizeReceiptNumber('0002-2026');
      expect(firstNumber, isNotNull);
      expect(secondNumber, isNotNull);
      expect(firstNumber, isNot(secondNumber));
    });

    test('fallback fingerprint needs merchant, minute and total', () {
      final at = DateTime(2026, 10, 19, 14, 32, 45);
      expect(
        ReceiptIdentity.matchesFallback(
          merchantA: 'スーパーABC',
          purchasedAtA: at,
          totalA: 227,
          merchantB: ' スーパーabc ',
          purchasedAtB: DateTime(2026, 10, 19, 14, 32, 1),
          totalB: 227,
        ),
        isTrue,
      );
      expect(
        ReceiptIdentity.matchesFallback(
          merchantA: 'スーパーABC',
          purchasedAtA: at,
          totalA: 227,
          merchantB: 'スーパーABC',
          purchasedAtB: DateTime(2026, 10, 19, 14, 33),
          totalB: 227,
        ),
        isFalse,
      );
      expect(
        ReceiptIdentity.matchesFallback(
          merchantA: 'スーパーABC',
          purchasedAtA: at,
          totalA: 227,
          merchantB: 'スーパーABC',
          purchasedAtB: at,
          totalB: 228,
        ),
        isFalse,
      );
    });
  });

  group('amount consistency', () {
    test('170 + 41 = 211 with tax 16 and total 227 is consistent', () {
      expect(
        itemsTotalMatchesReceipt(
          itemsTotal: 211,
          subtotalAmount: 211,
          taxTotal: 16,
          totalAmount: 227,
        ),
        isTrue,
      );
    });

    test('items + tax may match the total without a printed subtotal', () {
      expect(
        itemsTotalMatchesReceipt(
          itemsTotal: 211,
          taxTotal: 16,
          totalAmount: 227,
        ),
        isTrue,
      );
    });

    test('tax-included line prices may match the grand total', () {
      expect(
        itemsTotalMatchesReceipt(
          itemsTotal: 227,
          subtotalAmount: 211,
          taxTotal: 16,
          totalAmount: 227,
        ),
        isTrue,
      );
    });

    test('a genuinely wrong item sum is reported', () {
      expect(
        itemsTotalMatchesReceipt(
          itemsTotal: 190,
          subtotalAmount: 211,
          taxTotal: 16,
          totalAmount: 227,
        ),
        isFalse,
      );
    });
  });
}
