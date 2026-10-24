enum ReminderKind { creditCard, debt }

/// One in-app due reminder (credit-card payment or debt due date).
class ReminderItem {
  const ReminderItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.amount,
    required this.currency,
    required this.dueDate,
    this.sourceId,
  });

  final String id;
  final ReminderKind kind;

  /// Wallet name or person name.
  final String title;

  /// Amount in [currency] (wallet or debt currency).
  final double amount;
  final String currency;
  final DateTime dueDate;

  /// Wallet id or debt id.
  final String? sourceId;

  int daysUntil(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return target.difference(today).inDays;
  }
}

/// Reminders are shown a few days before the due date, on the day, and while
/// overdue (capped so very old debts do not fill the dashboard forever).
bool isReminderActive(
  DateTime dueDate,
  DateTime now, {
  int daysBefore = 3,
  int overdueDays = 30,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final target = DateTime(dueDate.year, dueDate.month, dueDate.day);
  final days = target.difference(today).inDays;
  return days <= daysBefore && days >= -overdueDays;
}
