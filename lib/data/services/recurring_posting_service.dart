import '../../domain/models/income_entry.dart';
import '../../domain/models/pay_cycle.dart';
import '../../domain/models/receipt.dart';
import '../../domain/models/receipt_draft.dart';
import '../repositories/income_repository.dart';
import '../repositories/receipt_repository.dart';
import '../repositories/recurring_repository.dart';

class RecurringPostingResult {
  const RecurringPostingResult({this.receipts = 0, this.incomes = 0});

  final int receipts;
  final int incomes;

  int get total => receipts + incomes;
  bool get postedAnything => total > 0;
}

/// Posts due recurring transactions into the normal receipts / income
/// collections. Each post carries `recurring_id`, and the recurring item stores
/// `last_posted_at`, so the same cycle is not posted twice.
class RecurringPostingService {
  const RecurringPostingService({
    required RecurringTransactionRepository recurring,
    required ReceiptRepository receipts,
    required IncomeEntryRepository incomes,
  })  : _recurring = recurring,
        _receipts = receipts,
        _incomes = incomes;

  final RecurringTransactionRepository _recurring;
  final ReceiptRepository _receipts;
  final IncomeEntryRepository _incomes;

  Future<RecurringPostingResult> postDue({DateTime? now}) async {
    final current = now ?? DateTime.now();
    final today = dateOnly(current);
    var postedReceipts = 0;
    var postedIncomes = 0;

    final items = await _recurring.fetchAll();
    for (final item in items) {
      if (!item.active) continue;
      final after = item.lastPostedAt ?? addDays(item.startDate, -1);
      final occurrences = item.occurrencesBetween(after, today);
      if (occurrences.isEmpty) continue;

      DateTime latest = item.lastPostedAt ?? after;
      for (final occurrence in occurrences) {
        if (item.direction.isExpense) {
          await _receipts.create(
            ReceiptDraft(
              merchant: item.name,
              currency: item.currency,
              purchasedAt: occurrence,
              totalAmount: item.amount,
              categoryId: item.categoryId,
              walletId: item.walletId,
              note: item.note,
              recurringId: item.id,
              source: ReceiptSource.manual,
            ),
            skipDuplicateCheck: true,
          );
          postedReceipts++;
        } else {
          final stamp = DateTime.now();
          await _incomes.create(
            IncomeEntry(
              id: '',
              userId: item.userId,
              amount: item.amount,
              currency: item.currency,
              receivedAt: occurrence,
              source: item.name,
              note: item.note,
              walletId: item.walletId,
              recurringId: item.id,
              createdAt: stamp,
              updatedAt: stamp,
            ),
          );
          postedIncomes++;
        }
        latest = occurrence;
      }
      await _recurring.save(item.copyWith(lastPostedAt: latest));
    }

    return RecurringPostingResult(
      receipts: postedReceipts,
      incomes: postedIncomes,
    );
  }
}
