/// Model representing a transaction in the double-entry unified ledger.
library;

enum TransactionType {
  income,
  expense,
  transfer;

  static TransactionType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'income':
        return TransactionType.income;
      case 'expense':
        return TransactionType.expense;
      case 'transfer':
        return TransactionType.transfer;
      default:
        return TransactionType.expense;
    }
  }
}

class TransactionModel {
  const TransactionModel({
    required this.id,
    required this.userId,
    required this.transactionType,
    required this.amount,
    required this.currency,
    required this.transactionDate,
    required this.category,
    this.description,
    required this.isHouseholdShared,
    this.accountId,
    this.creditCardId,
    this.loanId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String userId;
  final TransactionType transactionType;
  final double amount;
  final String currency;
  final DateTime transactionDate;
  final String category;
  final String? description;
  final bool isHouseholdShared;
  final String? accountId;
  final String? creditCardId;
  final String? loanId;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory TransactionModel.fromJson(Map<String, dynamic> json) {
    return TransactionModel(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      transactionType: TransactionType.fromString(json['transaction_type'] as String? ?? 'expense'),
      amount: (num.tryParse(json['amount'].toString()) ?? 0).toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      transactionDate: DateTime.tryParse(json['transaction_date'] as String? ?? '') ?? DateTime.now(),
      category: json['category'] as String? ?? 'General',
      description: json['description'] as String?,
      isHouseholdShared: json['is_household_shared'] as bool? ?? false,
      accountId: json['account_id'] as String?,
      creditCardId: json['credit_card_id'] as String?,
      loanId: json['loan_id'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ?? DateTime.now(),
    );
  }
}
