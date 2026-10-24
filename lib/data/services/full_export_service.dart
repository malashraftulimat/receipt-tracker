import 'dart:convert';
import 'dart:typed_data';

import '../../core/localization/currencies.dart';
import '../../domain/models/category.dart';
import '../../domain/models/debt.dart';
import '../../domain/models/income_entry.dart';
import '../../domain/models/income_source.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/recurring_transaction.dart';
import '../../domain/models/wallet.dart';
import '../../domain/models/wallet_adjustment.dart';
import '../../domain/models/wallet_transfer.dart';
import 'export_service.dart';

/// One CSV containing wallets, transactions, income, debts and recurring
/// definitions. A `record_type` column distinguishes the rows.
class FullExportService {
  const FullExportService._();

  static const List<String> header = <String>[
    'record_type',
    'id',
    'date',
    'name',
    'wallet',
    'to_wallet',
    'category',
    'amount',
    'currency',
    'status',
    'note',
    'extra',
  ];

  static String buildCsv({
    required List<Wallet> wallets,
    required List<Receipt> receipts,
    required List<IncomeSource> incomeSources,
    required List<IncomeEntry> incomeEntries,
    required List<WalletTransfer> transfers,
    required List<WalletAdjustment> adjustments,
    required List<Debt> debts,
    required List<RecurringTransaction> recurring,
    List<ExpenseCategory> categories = const <ExpenseCategory>[],
  }) {
    final walletNames = <String, String>{
      for (final wallet in wallets) wallet.id: wallet.name,
    };
    final walletCurrencies = <String, String>{
      for (final wallet in wallets) wallet.id: wallet.currency,
    };
    final categoryNames = <String, String>{
      for (final category in categories) category.id: category.name,
    };

    final rows = <List<String>>[header];

    for (final wallet in wallets) {
      final extra = <String>[
        'type=${wallet.type.wireName}',
        'include_in_total=${wallet.countsInTotal}',
        if (wallet.last4 != null) 'last4=${wallet.last4}',
        if (wallet.isCredit) 'credit_limit=${_amount(wallet.creditLimit, wallet.currency)}',
        if (wallet.isCredit) 'opening_available=${_amount(wallet.openingAvailable, wallet.currency)}',
        if (wallet.closingDay != null) 'closing_day=${wallet.closingDay}',
        if (wallet.paymentDueDay != null) 'payment_due_day=${wallet.paymentDueDay}',
      ].join('; ');
      rows.add(<String>[
        'wallet',
        wallet.id,
        _date(wallet.createdAt),
        wallet.name,
        wallet.name,
        '',
        '',
        _amount(wallet.openingBalance, wallet.currency),
        wallet.currency,
        wallet.archived ? 'archived' : 'active',
        '',
        extra,
      ]);
    }

    for (final receipt in receipts) {
      rows.add(<String>[
        'transaction',
        receipt.id,
        _date(receipt.purchasedAt),
        receipt.displayTitle,
        receipt.walletId == null ? '' : walletNames[receipt.walletId] ?? '',
        '',
        receipt.category?.name ?? categoryNames[receipt.categoryId] ?? '',
        _amount(receipt.totalAmount, receipt.currency),
        receipt.currency,
        'expense',
        receipt.note ?? '',
        <String>[
          if (receipt.paymentMethod != null)
            'payment_method=${receipt.paymentMethod!.wireName}',
          if (receipt.recurringId != null)
            'recurring_id=${receipt.recurringId}',
        ].join('; '),
      ]);
    }

    for (final entry in incomeEntries) {
      rows.add(<String>[
        'transaction',
        entry.id,
        _date(entry.receivedAt),
        entry.source,
        entry.walletId == null ? '' : walletNames[entry.walletId] ?? '',
        '',
        '',
        _amount(entry.amount, entry.currency),
        entry.currency,
        'income',
        entry.note ?? '',
        entry.recurringId == null ? '' : 'recurring_id=${entry.recurringId}',
      ]);
    }

    for (final transfer in transfers) {
      final currency = walletCurrencies[transfer.fromWalletId] ?? '';
      final toCurrency = walletCurrencies[transfer.toWalletId] ?? '';
      rows.add(<String>[
        'transaction',
        transfer.id,
        _date(transfer.occurredAt),
        'transfer',
        walletNames[transfer.fromWalletId] ?? '',
        walletNames[transfer.toWalletId] ?? '',
        '',
        _amount(transfer.fromAmount, currency),
        currency,
        'transfer',
        transfer.note ?? '',
        'to_amount=${_amount(transfer.toAmount, toCurrency)}; '
            'to_currency=$toCurrency',
      ]);
    }

    for (final adjustment in adjustments) {
      final currency = walletCurrencies[adjustment.walletId] ?? '';
      rows.add(<String>[
        'transaction',
        adjustment.id,
        _date(adjustment.occurredAt),
        'adjustment',
        walletNames[adjustment.walletId] ?? '',
        '',
        '',
        _amount(adjustment.amount, currency),
        currency,
        'adjustment',
        adjustment.note ?? '',
        '',
      ]);
    }

    for (final source in incomeSources) {
      rows.add(<String>[
        'income_source',
        source.id,
        _date(source.createdAt),
        source.name,
        source.walletId == null ? '' : walletNames[source.walletId] ?? '',
        '',
        '',
        _amount(source.amountPerCycle, source.currency),
        source.currency,
        source.active ? 'active' : 'inactive',
        '',
        'cycle=${source.cycle.name}; weekly_weekday=${source.weeklyStartWeekday}; '
            'monthly_pay_day=${source.monthlyPayDay}; '
            'defines_budget_period=${source.definesBudgetPeriod}',
      ]);
    }

    for (final debt in debts) {
      rows.add(<String>[
        'debt',
        debt.id,
        _date(debt.date),
        debt.counterparty,
        debt.walletId == null ? '' : walletNames[debt.walletId] ?? '',
        '',
        '',
        _amount(debt.amount, debt.currency),
        debt.currency,
        debt.derivedStatus.wireName,
        debt.note ?? '',
        'direction=${debt.direction.wireName}; '
            'repaid=${_amount(debt.repaidAmount, debt.currency)}; '
            'remaining=${_amount(debt.remaining, debt.currency)}; '
            'due=${debt.dueDate == null ? '' : _date(debt.dueDate!)}',
      ]);
      for (final repayment in debt.repayments) {
        rows.add(<String>[
          'debt_repayment',
          repayment.id,
          _date(repayment.date),
          debt.counterparty,
          repayment.walletId == null
              ? ''
              : walletNames[repayment.walletId] ?? '',
          '',
          '',
          _amount(repayment.amount, debt.currency),
          debt.currency,
          'repayment',
          repayment.note ?? '',
          'debt_id=${debt.id}',
        ]);
      }
    }

    for (final item in recurring) {
      rows.add(<String>[
        'recurring',
        item.id,
        _date(item.startDate),
        item.name,
        item.walletId == null ? '' : walletNames[item.walletId] ?? '',
        '',
        item.categoryId == null
            ? ''
            : categoryNames[item.categoryId] ?? '',
        _amount(item.amount, item.currency),
        item.currency,
        item.active ? 'active' : 'inactive',
        item.note ?? '',
        'direction=${item.direction.wireName}; cycle=${item.cycle.name}; '
            'weekly_weekday=${item.weeklyStartWeekday}; '
            'monthly_pay_day=${item.monthlyPayDay}; '
            'last_posted=${item.lastPostedAt == null ? '' : _date(item.lastPostedAt!)}',
      ]);
    }

    return rows.map((row) => row.map(_escape).join(',')).join('\r\n');
  }

  static Future<String> exportCsv(String csv, {required String filename}) {
    final bytes = Uint8List.fromList(utf8.encode('\uFEFF$csv'));
    return ExportService.saveBytes(
      bytes,
      filename,
      'text/csv;charset=utf-8',
    );
  }

  static String filename({DateTime? now}) {
    final date = now ?? DateTime.now();
    return 'receipt_tracker_all_${date.year}'
        '${_two(date.month)}${_two(date.day)}.csv';
  }

  static String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${_two(value.month)}-${_two(value.day)} '
      '${_two(value.hour)}:${_two(value.minute)}';

  static String _amount(num? value, String currency) {
    if (value == null) return '';
    final digits = currencyOrDefault(currency).decimalDigits;
    return value.toStringAsFixed(digits);
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _escape(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
