/// A monthly spending cap, with its spend for the period being reported.
///
/// `spent`, `remaining` and `percentUsed` are computed server-side from the
/// ledger, never stored — so they cannot drift from the transactions behind
/// them, and the client never has to sum anything itself.
library;

class Budget {
  const Budget({
    required this.id,
    required this.amount,
    required this.spent,
    required this.remaining,
    required this.percentUsed,
    required this.period,
    this.category,
    this.includeHousehold = false,
    this.isActive = true,
  });

  final String id;
  final double amount;
  final double spent;
  final double remaining;
  final double percentUsed;

  /// `YYYY-MM` the spend figures cover.
  final String period;

  /// Null means this is the overall cap on all spending.
  final String? category;

  final bool includeHousehold;
  final bool isActive;

  bool get isOverall => category == null;

  String get label => category ?? 'Overall';

  /// How close to the cap, clamped for a progress bar.
  double get fraction => (percentUsed / 100).clamp(0.0, 1.0);

  bool get isOverBudget => spent > amount;

  factory Budget.fromJson(Map<String, dynamic> json) {
    double parse(String key) =>
        (num.tryParse(json[key]?.toString() ?? '0') ?? 0).toDouble();

    return Budget(
      id: json['id'] as String,
      amount: parse('amount'),
      spent: parse('spent'),
      remaining: parse('remaining'),
      percentUsed: parse('percent_used'),
      period: json['period'] as String? ?? '',
      category: json['category'] as String?,
      includeHousehold: json['include_household'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

/// One month's totals, from `GET /reports/monthly`.
class MonthlyReport {
  const MonthlyReport({
    required this.period,
    required this.income,
    required this.expense,
    required this.net,
    required this.transactionCount,
    required this.byCategory,
  });

  final String period;
  final double income;
  final double expense;
  final double net;
  final int transactionCount;
  final List<CategorySpend> byCategory;

  factory MonthlyReport.fromJson(Map<String, dynamic> json) {
    double parse(String key) =>
        (num.tryParse(json[key]?.toString() ?? '0') ?? 0).toDouble();

    return MonthlyReport(
      period: json['period'] as String? ?? '',
      income: parse('income'),
      expense: parse('expense'),
      net: parse('net'),
      transactionCount: json['transaction_count'] as int? ?? 0,
      byCategory: ((json['by_category'] as List?) ?? const [])
          .map((row) => CategorySpend.fromJson(row as Map<String, dynamic>))
          .toList(),
    );
  }
}

class CategorySpend {
  const CategorySpend({
    required this.category,
    required this.amount,
    required this.percent,
    required this.transactionCount,
  });

  final String category;
  final double amount;
  final double percent;
  final int transactionCount;

  factory CategorySpend.fromJson(Map<String, dynamic> json) {
    return CategorySpend(
      category: json['category'] as String? ?? 'Uncategorised',
      amount: (num.tryParse(json['amount']?.toString() ?? '0') ?? 0).toDouble(),
      percent:
          (num.tryParse(json['percent']?.toString() ?? '0') ?? 0).toDouble(),
      transactionCount: json['transaction_count'] as int? ?? 0,
    );
  }
}
