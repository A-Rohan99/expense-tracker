/// The standing monthly income instruction.
///
/// The server owns the calendar math — [nextDueDate] and [accountName] arrive
/// computed, so the client never has to reason about short months.
library;

class RecurringIncome {
  const RecurringIncome({
    required this.id,
    required this.accountId,
    required this.name,
    required this.amount,
    required this.dayOfMonth,
    required this.category,
    required this.currency,
    required this.isHouseholdShared,
    required this.isActive,
    this.lastPostedPeriod,
    this.nextDueDate,
    this.accountName,
    this.postedThisRun = 0,
  });

  final String id;
  final String accountId;
  final String name;
  final double amount;
  final int dayOfMonth;
  final String category;
  final String currency;
  final bool isHouseholdShared;
  final bool isActive;

  /// `YYYY-MM` of the last month already paid out.
  final String? lastPostedPeriod;

  /// When the next deposit lands.
  final DateTime? nextDueDate;

  /// Name of the destination account, resolved server-side.
  final String? accountName;

  /// How many months the server just posted while answering this request —
  /// lets the UI tell the user what changed behind their back.
  final int postedThisRun;

  factory RecurringIncome.fromJson(Map<String, dynamic> json) {
    return RecurringIncome(
      id: json['id'] as String,
      accountId: json['account_id'] as String,
      name: json['name'] as String? ?? 'Monthly income',
      amount: (num.tryParse(json['amount'].toString()) ?? 0).toDouble(),
      dayOfMonth: json['day_of_month'] as int? ?? 1,
      category: json['category'] as String? ?? 'Salary',
      currency: json['currency'] as String? ?? 'INR',
      isHouseholdShared: json['is_household_shared'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      lastPostedPeriod: json['last_posted_period'] as String?,
      nextDueDate: DateTime.tryParse(json['next_due_date'] as String? ?? ''),
      accountName: json['account_name'] as String?,
      postedThisRun: json['posted_this_run'] as int? ?? 0,
    );
  }

  /// "1st", "2nd", "23rd" — for reading back the chosen pay day.
  String get dayLabel {
    final d = dayOfMonth;
    if (d >= 11 && d <= 13) return '${d}th';
    switch (d % 10) {
      case 1:
        return '${d}st';
      case 2:
        return '${d}nd';
      case 3:
        return '${d}rd';
      default:
        return '${d}th';
    }
  }
}
