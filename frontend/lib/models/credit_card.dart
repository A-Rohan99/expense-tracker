/// Models representing Credit Cards and dynamic billing summaries.
library;

class CreditCard {
  const CreditCard({
    required this.id,
    required this.userId,
    required this.name,
    this.lastFour,
    required this.totalLimit,
    required this.statementDay,
    required this.dueDay,
    required this.currency,
    required this.isActive,
    required this.createdAt,
    this.unbilledAmount = 0.0,
    this.billedAmount = 0.0,
    this.availableLimit = 0.0,
  });

  final String id;
  final String userId;
  final String name;
  final String? lastFour;
  final double totalLimit;
  final int statementDay;
  final int dueDay;
  final String currency;
  final bool isActive;
  final DateTime createdAt;
  final double unbilledAmount;
  final double billedAmount;
  final double availableLimit;

  factory CreditCard.fromJson(Map<String, dynamic> json) {
    return CreditCard(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      lastFour: json['last_four'] as String?,
      totalLimit: (num.tryParse(json['total_limit'].toString()) ?? 0).toDouble(),
      statementDay: json['statement_day'] as int? ?? 1,
      dueDay: json['due_day'] as int? ?? 20,
      currency: json['currency'] as String? ?? 'INR',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      unbilledAmount: (num.tryParse(json['unbilled_amount']?.toString() ?? '0') ?? 0).toDouble(),
      billedAmount: (num.tryParse(json['billed_amount']?.toString() ?? '0') ?? 0).toDouble(),
      availableLimit: (num.tryParse(json['available_limit']?.toString() ?? '0') ?? 0).toDouble(),
    );
  }
}

class CreditCardSummary {
  const CreditCardSummary({
    required this.cardId,
    required this.cardName,
    required this.totalLimit,
    required this.billedAmount,
    required this.unbilledAmount,
    required this.totalOutstanding,
    required this.availableLimit,
    required this.totalPayments,
    required this.minDueAmount,
    required this.lastStatementDate,
    required this.nextStatementDate,
    required this.dueDate,
    required this.daysUntilDue,
  });

  final String cardId;
  final String cardName;
  final double totalLimit;
  final double billedAmount;
  final double unbilledAmount;
  final double totalOutstanding;
  final double availableLimit;
  final double totalPayments;
  final double minDueAmount;
  final DateTime lastStatementDate;
  final DateTime nextStatementDate;
  final DateTime dueDate;
  final int daysUntilDue;

  factory CreditCardSummary.fromJson(Map<String, dynamic> json) {
    return CreditCardSummary(
      cardId: json['card_id'] as String,
      cardName: json['card_name'] as String,
      totalLimit: (num.tryParse(json['total_limit'].toString()) ?? 0).toDouble(),
      billedAmount: (num.tryParse(json['billed_amount'].toString()) ?? 0).toDouble(),
      unbilledAmount: (num.tryParse(json['unbilled_amount'].toString()) ?? 0).toDouble(),
      totalOutstanding: (num.tryParse(json['total_outstanding'].toString()) ?? 0).toDouble(),
      availableLimit: (num.tryParse(json['available_limit'].toString()) ?? 0).toDouble(),
      totalPayments: (num.tryParse(json['total_payments'].toString()) ?? 0).toDouble(),
      minDueAmount: (num.tryParse(json['min_due_amount'].toString()) ?? 0).toDouble(),
      lastStatementDate: DateTime.tryParse(json['last_statement_date'] as String? ?? '') ?? DateTime.now(),
      nextStatementDate: DateTime.tryParse(json['next_statement_date'] as String? ?? '') ?? DateTime.now(),
      dueDate: DateTime.tryParse(json['due_date'] as String? ?? '') ?? DateTime.now(),
      daysUntilDue: json['days_until_due'] as int? ?? 0,
    );
  }
}
