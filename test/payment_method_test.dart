import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/models/payment_method.dart';
import 'package:receipt_tracker/domain/models/pay_cycle.dart';
import 'package:receipt_tracker/domain/models/receipt.dart';
import 'package:receipt_tracker/domain/models/receipt_draft.dart';
import 'package:receipt_tracker/domain/models/receipt_filter.dart';

Receipt payment({
  String id = 'p1',
  required DateTime purchasedAt,
  double total = 1000,
  PaymentMethod? method = PaymentMethod.cash,
  String? merchant,
  String? note,
  ReceiptSource source = ReceiptSource.manual,
}) {
  final created = DateTime(2026, 10, 1, 9);
  return Receipt(
    id: id,
    userId: 'u1',
    merchant: merchant,
    note: note,
    purchasedAt: purchasedAt,
    totalAmount: total,
    paymentMethod: method,
    source: source,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  group('PaymentMethod', () {
    test('every method has a unique wire name that parses back', () {
      final names = PaymentMethod.values.map((m) => m.wireName).toSet();
      expect(names.length, PaymentMethod.values.length);
      for (final method in PaymentMethod.values) {
        expect(PaymentMethod.tryParse(method.wireName), method);
      }
    });

    test('parses legacy and unknown values', () {
      expect(PaymentMethod.tryParse('credit_card'), PaymentMethod.creditCard);
      expect(PaymentMethod.tryParse('creditCard'), PaymentMethod.creditCard);
      expect(PaymentMethod.tryParse('BANK-TRANSFER'), PaymentMethod.bankTransfer);
      expect(PaymentMethod.tryParse(' qr_emoney '), PaymentMethod.qrEmoney);
      expect(PaymentMethod.tryParse(null), isNull);
      expect(PaymentMethod.tryParse(''), isNull);
      expect(PaymentMethod.tryParse('bitcoin'), isNull);
    });

    test('labels fall back to 未設定 when unset', () {
      expect(PaymentMethod.labelOf(null), '未設定');
      expect(PaymentMethod.labelOf(PaymentMethod.cash), '現金');
      expect(PaymentMethod.labelOf(PaymentMethod.icCard), 'ICカード（Suica / PASMO）');
    });
  });

  group('Receipt serialization', () {
    Map<String, dynamic> row({Object? paymentMethod}) => <String, dynamic>{
          'id': 'r1',
          'user_id': 'u1',
          'merchant': null,
          'note': '家賃',
          'purchased_at': '2026-10-21T03:00:00.000Z',
          'total_amount': 85000,
          'source': 'manual',
          'created_at': '2026-10-21T03:00:00.000Z',
          'updated_at': '2026-10-21T03:00:00.000Z',
          if (paymentMethod != null) 'payment_method': paymentMethod,
        };

    test('reads the stored payment method', () {
      final receipt = Receipt.fromJson(row(paymentMethod: 'bank_transfer'));
      expect(receipt.paymentMethod, PaymentMethod.bankTransfer);
      expect(receipt.displayPaymentMethod, '銀行振込');
    });

    test('tolerates old documents without the field', () {
      final receipt = Receipt.fromJson(row());
      expect(receipt.paymentMethod, isNull);
      expect(receipt.displayPaymentMethod, '未設定');
    });

    test('tolerates unknown stored values', () {
      final receipt = Receipt.fromJson(row(paymentMethod: 'cheque'));
      expect(receipt.paymentMethod, isNull);
    });

    test('copyWith can set the payment method', () {
      final receipt = Receipt.fromJson(row());
      expect(
        receipt.copyWith(paymentMethod: PaymentMethod.creditCard).paymentMethod,
        PaymentMethod.creditCard,
      );
    });

    test('receiptless payments use the note as the list title', () {
      final receipt = Receipt.fromJson(row(paymentMethod: 'cash'));
      expect(receipt.displayTitle, '家賃');
      expect(receipt.displayMerchant, '店舗名なし');
      expect(
        Receipt.fromJson(row()).copyWith(merchant: 'やよい軒').displayTitle,
        'やよい軒',
      );
    });
  });

  group('ReceiptDraft serialization', () {
    test('writes the enum wire name', () {
      final draft = ReceiptDraft(
        purchasedAt: DateTime(2026, 10, 21, 9),
        totalAmount: 85000,
        note: '家賃',
        paymentMethod: PaymentMethod.directDebit,
        source: ReceiptSource.manual,
      );
      final row = draft.toRow();
      expect(row['payment_method'], 'direct_debit');
      expect(row['source'], 'manual');
      expect(row['merchant'], isNull); // no store for a receiptless payment
      expect(row['note'], '家賃');
    });

    test('leaves the field null when unset', () {
      final draft = ReceiptDraft(
        purchasedAt: DateTime(2026, 10, 21, 9),
        totalAmount: 500,
      );
      expect(draft.toRow()['payment_method'], isNull);
    });

    test('round-trips through an existing receipt', () {
      final receipt = payment(
        purchasedAt: DateTime(2026, 10, 21, 9),
        total: 85000,
        method: PaymentMethod.bankTransfer,
        note: '家賃',
      );
      final draft = ReceiptDraft.fromReceipt(receipt);
      expect(draft.paymentMethod, PaymentMethod.bankTransfer);
      expect(draft.toRow()['payment_method'], 'bank_transfer');
    });
  });

  group('ReceiptFilter', () {
    test('filters by payment method and clears it again', () {
      final filter = const ReceiptFilter().copyWith(
        paymentMethod: PaymentMethod.qrEmoney,
      );
      expect(filter.paymentMethod, PaymentMethod.qrEmoney);
      expect(filter.hasFilters, isTrue);

      final cleared = filter.copyWith(paymentMethod: null);
      expect(cleared.paymentMethod, isNull);
      expect(cleared.hasFilters, isFalse);
    });

    test('reset keeps the view mode but drops the method', () {
      const filter = ReceiptFilter(
        paymentMethod: PaymentMethod.cash,
        view: ReceiptViewMode.grid,
      );
      final reset = ReceiptFilter(view: filter.view);
      expect(reset.paymentMethod, isNull);
      expect(reset.view, ReceiptViewMode.grid);
    });
  });

  group('Pay-cycle period inclusion', () {
    test('quick payments are counted in the current weekly period', () {
      const config = PayCycleConfig(
        cycle: PayCycle.weekly,
        weeklyStartWeekday: DateTime.monday,
      );
      final period = config.periodFor(DateTime(2026, 10, 21)); // mid-week

      final receipts = <Receipt>[
        // Quick payment inside the period.
        payment(
          id: 'rent',
          purchasedAt: DateTime(2026, 10, 20, 9),
          total: 85000,
          method: PaymentMethod.directDebit,
          note: '家賃',
        ),
        // Scanned receipt inside the period.
        payment(
          id: 'lunch',
          purchasedAt: DateTime(2026, 10, 21, 12),
          total: 1200,
          method: PaymentMethod.qrEmoney,
          merchant: 'やよい軒',
          source: ReceiptSource.ocr,
        ),
        // Day before the period starts.
        payment(
          id: 'old',
          purchasedAt: addDays(period.start, -1),
          total: 9999,
        ),
        // First day of the next period (exclusive end).
        payment(
          id: 'next',
          purchasedAt: period.end,
          total: 8888,
        ),
      ];

      expect(period.contains(DateTime(2026, 10, 20, 9)), isTrue);
      expect(receipts.totalInPeriod(period), 86200);
      expect(
        receipts.withinPeriod(period).map((r) => r.id),
        <String>['lunch', 'rent'],
      );
    });

    test('monthly payday periods include payments across month boundaries', () {
      const config = PayCycleConfig(
        cycle: PayCycle.monthly,
        monthlyPayDay: 25,
      );
      final period = config.periodFor(DateTime(2026, 10, 3));
      expect(period.start, DateTime(2026, 9, 25));
      expect(period.end, DateTime(2026, 10, 25));

      final receipts = <Receipt>[
        payment(
          id: 'sep',
          purchasedAt: DateTime(2026, 9, 30, 20),
          total: 4000,
          method: PaymentMethod.cash,
        ),
        payment(
          id: 'oct',
          purchasedAt: DateTime(2026, 10, 24, 23, 59),
          total: 6000,
          method: PaymentMethod.creditCard,
        ),
        payment(
          id: 'payday',
          purchasedAt: DateTime(2026, 10, 25),
          total: 7000,
          method: PaymentMethod.cash,
        ),
      ];

      expect(receipts.totalInPeriod(period), 10000);
    });

    test('daily periods contain only that day', () {
      final period =
          const PayCycleConfig(cycle: PayCycle.daily).periodFor(
        DateTime(2026, 10, 21, 8),
      );
      final receipts = <Receipt>[
        payment(
          id: 'today',
          purchasedAt: DateTime(2026, 10, 21, 22),
          total: 780,
          method: PaymentMethod.icCard,
        ),
        payment(
          id: 'tomorrow',
          purchasedAt: DateTime(2026, 10, 22, 0, 1),
          total: 500,
          method: PaymentMethod.cash,
        ),
      ];

      expect(receipts.totalInPeriod(period), 780);
    });
  });
}
