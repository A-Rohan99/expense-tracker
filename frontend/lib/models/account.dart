/// Model representing a liquid asset account (Bank, Cash, Wallet).
library;

enum AccountType {
  bank,
  cash,
  wallet;

  static AccountType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'bank':
        return AccountType.bank;
      case 'cash':
        return AccountType.cash;
      case 'wallet':
        return AccountType.wallet;
      default:
        return AccountType.bank;
    }
  }
}

class Account {
  const Account({
    required this.id,
    required this.userId,
    required this.name,
    required this.accountType,
    required this.currentBalance,
    required this.currency,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String userId;
  final String name;
  final AccountType accountType;
  final double currentBalance;
  final String currency;
  final bool isActive;
  final DateTime createdAt;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      accountType: AccountType.fromString(json['account_type'] as String),
      currentBalance: (num.tryParse(json['current_balance'].toString()) ?? 0).toDouble(),
      currency: json['currency'] as String? ?? 'INR',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'name': name,
    'account_type': accountType.name,
    'current_balance': currentBalance,
    'currency': currency,
    'is_active': isActive,
    'created_at': createdAt.toIso8601String(),
  };
}
