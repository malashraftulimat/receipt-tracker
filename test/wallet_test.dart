import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/domain/models/exchange_rates.dart';
import 'package:receipt_tracker/domain/models/income_entry.dart';
import 'package:receipt_tracker/domain/models/income_source.dart';
import 'package:receipt_tracker/domain/models/money_totals.dart';
import 'package:receipt_tracker/domain/models/receipt.dart';
import 'package:receipt_tracker/domain/models/wallet.dart';
import 'package:receipt_tracker/domain/models/wallet_adjustment.dart';
import 'package:receipt_tracker/domain/models/wallet_ledger.dart';
import 'package:receipt_tracker/domain/models/wallet_transfer.dart';

final created = DateTime(2026, 10, 1);

Wallet wallet({
  String id = 'w1',
  String name = 'Wallet',
  WalletType type = WalletType.cash,
  String currency = 'JPY',
  double opening = 0,
  bool? includeInTotal,
  bool archived = false,
  double? creditLimit,
  double? openingAvailable,
  int? closingDay,
  int? dueDay,
}) {
  return Wallet(
    id: id,
    name: name,
    type: type,
    currency: currency,
    openingBalance: opening,
    includeInTotal: includeInTotal,
    archived: archived,
    creditLimit: creditLimit,
    openingAvailable: openingAvailable,
    closingDay: closingDay,
    paymentDueDay: dueDay,
    createdAt: created,
    updatedAt: created,
  );
}

Receipt receipt({
  String id = 'r1',
  String? walletId,
  double amount = 1000,
  String currency = 'JPY',
  DateTime? at,
}) {
  final date = at ?? DateTime(2026, 10, 10, 12);
  return Receipt(
    id: id,
    userId: 'u1',
    merchant: 'Shop',
    currency: currency,
    purchasedAt: date,
    totalAmount: amount,
    walletId: walletId,
    createdAt: date,
    updatedAt: date,
  );
}

IncomeEntry income({
  String id = 'i1',
  String? walletId,
  double amount = 1000,
  String currency = 'JPY',
  DateTime? at,
}) {
  final date = at ?? DateTime(2026, 10, 11, 12);
  return IncomeEntry(
    id: id,
    userId: 'u1',
    amount: amount,
    currency: currency,
    receivedAt: date,
    source: 'Shift',
    walletId: walletId,
    createdAt: date,
    updatedAt: date,
  );
}

WalletTransfer transfer({
  String id = 't1',
  required String from,
  required String to,
  double fromAmount = 1000,
  double toAmount = 1000,
  DateTime? at,
}) {
  final date = at ?? DateTime(2026, 10, 12, 12);
  return WalletTransfer(
    id: id,
    userId: 'u1',
    fromWalletId: from,
    toWalletId: to,
    fromAmount: fromAmount,
    toAmount: toAmount,
    occurredAt: date,
    createdAt: date,
    updatedAt: date,
  );
}

WalletAdjustment adjustment({
  String id = 'a1',
  required String walletId,
  double amount = 500,
  DateTime? at,
}) {
  final date = at ?? DateTime(2026, 10, 13, 12);
  return WalletAdjustment(
    id: id,
    userId: 'u1',
    walletId: walletId,
    amount: amount,
    occurredAt: date,
    createdAt: date,
    updatedAt: date,
  );
}

FxSnapshot fx({Map<String, double>? rates, Map<String, double>? overrides}) {
  return FxSnapshot(
    base: 'JPY',
    rates: rates ?? const <String, double>{'USD': 1 / 150, 'EUR': 1 / 160},
    fetchedAt: DateTime(2026, 10, 25, 9),
    source: FxSource.frankfurter,
    overrides: overrides ?? const <String, double>{},
  );
}

void main() {
  group('Wallet model', () {
    test('includeInTotal defaults: savings and points out, others in', () {
      expect(wallet(type: WalletType.cash).countsInTotal, isTrue);
      expect(wallet(type: WalletType.bank).countsInTotal, isTrue);
      expect(wallet(type: WalletType.credit).countsInTotal, isTrue);
      expect(wallet(type: WalletType.savings).countsInTotal, isFalse);
      expect(wallet(type: WalletType.points).countsInTotal, isFalse);
      expect(
        wallet(type: WalletType.savings, includeInTotal: true).countsInTotal,
        isTrue,
      );
    });

    test('archived wallets are always excluded', () {
      expect(wallet(archived: true).countsInTotal, isFalse);
      expect(
        wallet(type: WalletType.cash, includeInTotal: true, archived: true)
            .countsInTotal,
        isFalse,
      );
    });

    test('last4 keeps only four digits and never a full card number', () {
      expect(Wallet.sanitizeLast4('1234'), '1234');
      expect(Wallet.sanitizeLast4(' 1234 '), '1234');
      expect(Wallet.sanitizeLast4('1234567890123456'), isNull);
      expect(Wallet.sanitizeLast4('12'), isNull);
    });

    test('copyWith preserves and updates last4 and settlementWalletId', () {
      final card = Wallet(
        id: 'c1',
        name: 'Card',
        type: WalletType.credit,
        currency: 'JPY',
        last4: '4321',
        settlementWalletId: 'bank1',
        createdAt: created,
        updatedAt: created,
      );
      final renamed = card.copyWith(name: 'Main Card');
      expect(renamed.last4, '4321');
      expect(renamed.settlementWalletId, 'bank1');

      final updated = card.copyWith(
        last4: '9876',
        settlementWalletId: 'bank2',
      );
      expect(updated.last4, '9876');
      expect(updated.settlementWalletId, 'bank2');
    });

    test('old documents without new fields still load', () {
      final restored = Wallet.fromJson(<String, dynamic>{
        'id': 'old',
        'name': 'Old wallet',
        'type': 'cash',
        'currency': 'JPY',
        'opening_balance': 1200,
      });
      expect(restored.openingBalance, 1200);
      expect(restored.archived, isFalse);
      expect(restored.includeInTotal, isNull);
      expect(restored.countsInTotal, isTrue);
      expect(restored.last4, isNull);
    });

    test('old receipts, income entries and sources have no wallet link', () {
      final oldReceipt = Receipt.fromJson(<String, dynamic>{
        'id': 'r1',
        'user_id': 'u1',
        'purchased_at': '2026-10-01T00:00:00.000Z',
        'total_amount': 500,
      });
      final oldIncome = IncomeEntry.fromJson(<String, dynamic>{
        'id': 'i1',
        'user_id': 'u1',
        'amount': 1000,
        'received_at': '2026-10-01T00:00:00.000Z',
        'source': 'Shift',
      });
      final oldSource = IncomeSource.fromJson(<String, dynamic>{
        'id': 's1',
        'name': 'Main',
        'cycle': 'monthly',
        'amount_per_cycle': 200000,
      });
      expect(oldReceipt.walletId, isNull);
      expect(oldIncome.walletId, isNull);
      expect(oldSource.walletId, isNull);
    });
  });

  group('Wallet balances', () {
    test('opening + income - spending + transfers +/- adjustments', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(id: 'cash', opening: 10000),
          wallet(id: 'bank', opening: 0),
        ],
        receipts: <Receipt>[receipt(walletId: 'cash', amount: 3000)],
        incomeEntries: <IncomeEntry>[income(walletId: 'cash', amount: 2000)],
        transfers: <WalletTransfer>[
          transfer(
            id: 'out',
            from: 'cash',
            to: 'bank',
            fromAmount: 1500,
            toAmount: 1500,
          ),
        ],
        adjustments: <WalletAdjustment>[
          adjustment(walletId: 'cash', amount: 500),
        ],
      );

      expect(ledger.accountFor('cash')!.balance, 8000);
      expect(ledger.accountFor('bank')!.balance, 1500);
    });

    test('a transfer between different currencies stores both amounts', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(id: 'usd', currency: 'USD', opening: 500),
          wallet(id: 'jpy', currency: 'JPY', opening: 0),
        ],
        receipts: const <Receipt>[],
        incomeEntries: const <IncomeEntry>[],
        transfers: <WalletTransfer>[
          transfer(
            id: 'fx',
            from: 'usd',
            to: 'jpy',
            fromAmount: 100,
            toAmount: 15000,
          ),
        ],
        adjustments: const <WalletAdjustment>[],
      );

      expect(ledger.accountFor('usd')!.balance, 400);
      expect(ledger.accountFor('jpy')!.balance, 15000);
    });

    test('receipts in another currency are excluded, not guessed', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[wallet(id: 'jpy', opening: 1000)],
        receipts: <Receipt>[
          receipt(id: 'jpy', walletId: 'jpy', amount: 300),
          receipt(id: 'usd', walletId: 'jpy', amount: 10, currency: 'USD'),
        ],
        incomeEntries: <IncomeEntry>[
          income(walletId: 'jpy', amount: 500),
          income(id: 'usd-income', walletId: 'jpy', amount: 9, currency: 'USD'),
        ],
        transfers: const <WalletTransfer>[],
        adjustments: const <WalletAdjustment>[],
      );

      expect(ledger.accountFor('jpy')!.balance, 1200);
      expect(ledger.mismatchedTransactionCount, 2);
    });
  });

  group('Credit cards', () {
    test('opening owed, charges and repayments change owed/available', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(
            id: 'card',
            type: WalletType.credit,
            creditLimit: 100000,
            openingAvailable: 80000,
            closingDay: 15,
            dueDay: 27,
          ),
          wallet(id: 'bank', opening: 50000),
        ],
        receipts: <Receipt>[
          receipt(walletId: 'card', amount: 5000),
        ],
        incomeEntries: const <IncomeEntry>[],
        transfers: <WalletTransfer>[
          transfer(
            id: 'repay',
            from: 'bank',
            to: 'card',
            fromAmount: 10000,
            toAmount: 10000,
          ),
        ],
        adjustments: const <WalletAdjustment>[],
      );

      final card = ledger.accountFor('card')!;
      expect(card.balance, 0);
      expect(card.owed, 15000);
      expect(card.availableCredit, 85000);
      expect(ledger.accountFor('bank')!.balance, 40000);
    });

    test('next due date handles due after closing and passed dates', () {
      expect(
        walletNextDueDate(DateTime(2026, 10, 20), 15, 27),
        DateTime(2026, 10, 27),
      );
      expect(
        walletNextDueDate(DateTime(2026, 10, 28), 15, 27),
        DateTime(2026, 11, 27),
      );
      // A due day on or before the closing day belongs to the next month.
      expect(
        walletNextDueDate(DateTime(2026, 10, 20), 15, 10),
        DateTime(2026, 11, 10),
      );
    });

    test('owedThisCycle counts charges since the last closing', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(
            id: 'card',
            type: WalletType.credit,
            creditLimit: 100000,
            openingAvailable: 100000,
            closingDay: 15,
            dueDay: 27,
          ),
        ],
        receipts: <Receipt>[
          receipt(
            id: 'before',
            walletId: 'card',
            amount: 2000,
            at: DateTime(2026, 10, 5),
          ),
          receipt(
            id: 'after',
            walletId: 'card',
            amount: 3000,
            at: DateTime(2026, 10, 20),
          ),
        ],
        incomeEntries: const <IncomeEntry>[],
        transfers: const <WalletTransfer>[],
        adjustments: const <WalletAdjustment>[],
      );

      expect(
        ledger.accountFor('card')!.owedThisCycle(asOf: DateTime(2026, 10, 25)),
        3000,
      );
    });
  });

  group('Money totals', () {
    test('available money, after obligations and net worth', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(id: 'cash', opening: 10000),
          wallet(id: 'bank', opening: 5000),
          wallet(
            id: 'savings',
            type: WalletType.savings,
            opening: 50000,
          ),
          wallet(id: 'points', type: WalletType.points, opening: 1000),
          wallet(
            id: 'card',
            type: WalletType.credit,
            creditLimit: 100000,
            openingAvailable: 98000,
            closingDay: 15,
            dueDay: 27,
          ),
          wallet(id: 'archived', opening: 9999, archived: true),
        ],
        receipts: const <Receipt>[],
        incomeEntries: const <IncomeEntry>[],
        transfers: const <WalletTransfer>[],
        adjustments: const <WalletAdjustment>[],
      );

      final totals = computeMoneyTotals(
        ledger: ledger,
        fx: fx(),
        asOf: DateTime(2026, 10, 20),
      );

      expect(totals.availableMoney, 15000);
      expect(totals.afterObligations, 13000);
      expect(totals.cardOwed, 2000);
      expect(totals.netWorth, 64000);
      expect(totals.missingRateCount, 0);
    });

    test('no rate means the wallet is excluded from converted totals', () {
      final ledger = buildWalletLedger(
        wallets: <Wallet>[
          wallet(id: 'jpy', opening: 10000),
          wallet(id: 'usd', currency: 'USD', opening: 100),
        ],
        receipts: const <Receipt>[],
        incomeEntries: const <IncomeEntry>[],
        transfers: const <WalletTransfer>[],
        adjustments: const <WalletAdjustment>[],
      );

      final totals = computeMoneyTotals(
        ledger: ledger,
        fx: fx(rates: const <String, double>{}),
        asOf: DateTime(2026, 10, 20),
      );

      expect(totals.availableMoney, 10000);
      expect(totals.missingRateCount, 1);
      expect(totals.netWorth, 10000);
    });

    test('card warning is only for large dues within a few days', () {
      expect(
        cardWarning(
          available: 10000,
          cardOwed: 4000,
          nextDueDate: DateTime(2026, 10, 22),
          asOf: DateTime(2026, 10, 20),
        ),
        isTrue,
      );
      expect(
        cardWarning(
          available: 10000,
          cardOwed: 4000,
          nextDueDate: DateTime(2026, 11, 5),
          asOf: DateTime(2026, 10, 20),
        ),
        isFalse,
      );
      expect(
        cardWarning(
          available: 10000,
          cardOwed: 1000,
          nextDueDate: DateTime(2026, 10, 22),
          asOf: DateTime(2026, 10, 20),
        ),
        isFalse,
      );
    });
  });
}
