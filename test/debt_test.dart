import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/calendar_export_service.dart';
import 'package:receipt_tracker/domain/models/debt.dart';
import 'package:receipt_tracker/domain/models/reminder.dart';
import 'package:receipt_tracker/domain/models/wallet.dart';
import 'package:receipt_tracker/domain/models/wallet_ledger.dart';

final created = DateTime(2026, 10, 1);

Debt debt({
  String id = 'd1',
  DebtDirection direction = DebtDirection.iLent,
  double amount = 10000,
  String? walletId,
  String currency = 'JPY',
  DebtStatus status = DebtStatus.open,
  List<DebtRepayment> repayments = const <DebtRepayment>[],
  DateTime? dueDate,
}) {
  return Debt(
    id: id,
    userId: 'u1',
    direction: direction,
    counterparty: 'Alex',
    amount: amount,
    currency: currency,
    date: created,
    dueDate: dueDate,
    walletId: walletId,
    repayments: repayments,
    status: status,
    createdAt: created,
    updatedAt: created,
  );
}

DebtRepayment repayment({
  String id = 'r1',
  double amount = 1000,
  String? walletId,
  DateTime? date,
}) {
  return DebtRepayment(
    id: id,
    amount: amount,
    date: date ?? DateTime(2026, 10, 5),
    walletId: walletId,
  );
}

void main() {
  group('Debt repayment math and status', () {
    test('open -> partial -> settled', () {
      var item = debt();
      expect(item.derivedStatus, DebtStatus.open);
      expect(item.remaining, 10000);
      expect(item.outstanding, 10000);

      item = item.withRepayment(repayment(amount: 4000));
      expect(item.repaidAmount, 4000);
      expect(item.remaining, 6000);
      expect(item.derivedStatus, DebtStatus.partial);
      expect(item.outstanding, 6000);

      item = item.withRepayment(repayment(id: 'r2', amount: 6000));
      expect(item.repaidAmount, 10000);
      expect(item.remaining, 0);
      expect(item.derivedStatus, DebtStatus.settled);
      expect(item.outstanding, 0);
    });

    test('mark settled hides the remaining amount from totals', () {
      final item = debt(amount: 5000).copyWith(status: DebtStatus.settled);
      expect(item.derivedStatus, DebtStatus.settled);
      expect(item.remaining, 5000);
      expect(item.outstanding, 0);
    });

    test('json round trip keeps repayments and status', () {
      final original = debt(
        repayments: <DebtRepayment>[
          repayment(amount: 2500, walletId: 'wallet_cash'),
        ],
        status: DebtStatus.partial,
        dueDate: DateTime(2026, 11, 1),
      );
      final restored = Debt.fromJson(<String, dynamic>{
        ...original.toRow(),
        'id': original.id,
        'user_id': original.userId,
      });
      expect(restored.direction, DebtDirection.iLent);
      expect(restored.repayments.single.amount, 2500);
      expect(restored.repayments.single.walletId, 'wallet_cash');
      expect(restored.remaining, 7500);
      expect(restored.derivedStatus, DebtStatus.partial);
      expect(restored.dueDate, DateTime(2026, 11, 1));
    });
  });

  group('Debt wallet movements', () {
    final wallet = Wallet(
      id: 'wallet_cash',
      name: 'Cash',
      currency: 'JPY',
      openingBalance: 10000,
      createdAt: created,
      updatedAt: created,
    );

    test('lending leaves the wallet and a repayment returns money', () {
      final lent = debt(amount: 3000, walletId: 'wallet_cash');
      final ledger = buildWalletLedger(
        wallets: <Wallet>[wallet],
        receipts: const [],
        incomeEntries: const [],
        transfers: const [],
        adjustments: const [],
        debts: <Debt>[lent],
      );
      expect(ledger.accountFor('wallet_cash')!.balance, 7000);

      final repaid = lent.withRepayment(
        repayment(amount: 1000, walletId: 'wallet_cash'),
      );
      final after = buildWalletLedger(
        wallets: <Wallet>[wallet],
        receipts: const [],
        incomeEntries: const [],
        transfers: const [],
        adjustments: const [],
        debts: <Debt>[repaid],
      );
      expect(after.accountFor('wallet_cash')!.balance, 8000);
    });

    test('borrowing adds money and repaying leaves the wallet', () {
      final borrowed = debt(
        direction: DebtDirection.iBorrowed,
        amount: 2000,
        walletId: 'wallet_cash',
        repayments: <DebtRepayment>[
          repayment(amount: 500, walletId: 'wallet_cash'),
        ],
      );
      final ledger = buildWalletLedger(
        wallets: <Wallet>[wallet],
        receipts: const [],
        incomeEntries: const [],
        transfers: const [],
        adjustments: const [],
        debts: <Debt>[borrowed],
      );
      expect(ledger.accountFor('wallet_cash')!.balance, 11500);
    });
  });

  group('Reminder window', () {
    final now = DateTime(2026, 10, 20);

    test('shows a few days before, on the day and while overdue', () {
      expect(isReminderActive(DateTime(2026, 10, 23), now), isTrue);
      expect(isReminderActive(DateTime(2026, 10, 24), now), isFalse);
      expect(isReminderActive(DateTime(2026, 10, 20), now), isTrue);
      expect(isReminderActive(DateTime(2026, 10, 15), now), isTrue);
      expect(isReminderActive(DateTime(2026, 8, 1), now), isFalse);
    });

    test('daysUntil uses calendar days', () {
      final reminder = ReminderItem(
        id: '1',
        kind: ReminderKind.debt,
        title: 'Alex',
        amount: 1000,
        currency: 'JPY',
        dueDate: DateTime(2026, 10, 22),
      );
      expect(reminder.daysUntil(now), 2);
    });
  });

  group('Calendar export', () {
    test('builds an all-day VEVENT with escaped text', () {
      final ics = CalendarExportService.buildIcs(
        <CalendarEvent>[
          CalendarEvent(
            uid: 'debt_1@receipt-tracker',
            title: 'Alex; rent, October',
            date: DateTime(2026, 10, 27),
            description: 'Line 1\nLine 2',
          ),
        ],
        now: DateTime.utc(2026, 10, 20, 12),
      );
      expect(ics, contains('BEGIN:VCALENDAR'));
      expect(ics, contains('DTSTART;VALUE=DATE:20261027'));
      expect(ics, contains('DTEND;VALUE=DATE:20261028'));
      expect(ics, contains(r'SUMMARY:Alex\; rent\, October'));
      expect(ics, contains(r'DESCRIPTION:Line 1\nLine 2'));
      expect(ics, contains('DTSTAMP:20261020T120000Z'));
      expect('BEGIN:VEVENT'.allMatches(ics).length, 1);
    });

    test('writes one VEVENT per reminder', () {
      final ics = CalendarExportService.buildIcs(<CalendarEvent>[
        CalendarEvent(
          uid: 'a',
          title: 'A',
          date: DateTime(2026, 10, 21),
        ),
        CalendarEvent(
          uid: 'b',
          title: 'B',
          date: DateTime(2026, 10, 22),
        ),
      ]);
      expect('BEGIN:VEVENT'.allMatches(ics).length, 2);
    });
  });
}
