import 'package:flutter_test/flutter_test.dart';
import 'package:receipt_tracker/data/services/export_service.dart';
import 'package:receipt_tracker/domain/models/monthly_budget.dart';
import 'package:receipt_tracker/domain/models/receipt.dart';

Receipt sampleReceipt() {
  final created = DateTime(2026, 10, 19, 12, 30);
  return Receipt(
    id: 'r1',
    userId: 'u1',
    merchant: 'A, B ストア',
    purchasedAt: created,
    totalAmount: 1234,
    subtotalAmount: 1200,
    tax8Amount: 34,
    tax8ItemsTotal: 700,
    dueDate: DateTime(2026, 10, 31),
    pointBrand: 'dポイント',
    pointAmount: 15,
    note: 'メモ "引用"',
    barcodeId: '4901234567894',
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CSV export', () {
    test('writes a header and one escaped row per receipt', () {
      final csv = ExportService.buildCsv(<Receipt>[sampleReceipt()]);
      final lines = csv.split('\r\n');

      expect(lines.length, 2);
      expect(lines.first, contains('日付'));
      expect(lines.first, contains('支払期限'));
      expect(lines.first, contains('ポイント'));

      expect(lines[1], contains('"A, B ストア"'));
      expect(lines[1], contains('2026-10-19'));
      expect(lines[1], contains('12:30'));
      expect(lines[1], contains('1234'));
      expect(lines[1], contains('2026-10-31'));
      expect(lines[1], contains('dポイント'));
      expect(lines[1], contains('15'));
      expect(lines[1], contains('""引用""'));
    });

    test('filename helpers', () {
      expect(
        ExportService.filenameForMonth(DateTime(2026, 3)),
        'receipts_2026-03.csv',
      );
      expect(ExportService.allFilename(), startsWith('receipts_all_'));
    });
  });

  group('Budget summary', () {
    final budget = MonthlyBudget(
      month: _october,
      salary: 300000,
      savingsGoal: 50000,
      fixedExpenses: 80000,
    );

    test('disposable income subtracts savings and fixed costs', () {
      expect(budget.disposableIncome, 170000);
    });

    test('on-track pacing', () {
      final summary = BudgetSummary(
        month: _october,
        budget: budget,
        spent: 60000,
        receiptCount: 5,
        daysInMonth: 30,
        daysElapsed: 10,
        todaySpent: 2000,
      );

      expect(summary.remaining, 110000);
      expect(summary.daysRemaining, 21);
      expect(summary.dailyAllowance, 110000 ~/ 21);
      expect(summary.progress, closeTo(0.3529, 0.001));
      expect(summary.expectedSpentByToday, 56667);
      expect(summary.velocityDelta, greaterThan(0));
      expect(summary.status, BudgetStatus.onTrack);
    });

    test('over budget', () {
      final summary = BudgetSummary(
        month: _october,
        budget: budget,
        spent: 180000,
        receiptCount: 12,
        daysInMonth: 30,
        daysElapsed: 20,
        todaySpent: 0,
      );
      expect(summary.remaining, -10000);
      expect(summary.dailyAllowance, 0);
      expect(summary.status, BudgetStatus.overBudget);
    });

    test('unconfigured budget', () {
      final summary = BudgetSummary(
        month: _october,
        budget: null,
        spent: 1000,
        receiptCount: 1,
        daysInMonth: 30,
        daysElapsed: 5,
        todaySpent: 0,
      );
      expect(summary.configured, isFalse);
      expect(summary.status, BudgetStatus.unset);
    });
  });

}

final DateTime _october = DateTime(2026, 10);
