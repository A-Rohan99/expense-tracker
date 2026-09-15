/// Model representing a Loan liability.
library;

enum LoanType {
  personal,
  home,
  auto,
  education,
  other;

  static LoanType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'personal':
        return LoanType.personal;
      case 'home':
        return LoanType.home;
      case 'auto':
        return LoanType.auto;
      case 'education':
        return LoanType.education;
      default:
        return LoanType.other;
    }
  }
}

class Loan {
  const Loan({
    required this.id,
    required this.userId,
    required this.name,
    required this.loanType,
    required this.principalAmount,
    required this.interestRate,
    required this.tenureMonths,
    required this.outstandingBalance,
    required this.startDate,
    required this.currency,
    required this.isActive,
    required this.createdAt,
    this.emiPaidThisMonth = false,
    this.lastEmiPaymentDate,
  });

  final String id;
  final String userId;
  final String name;
  final LoanType loanType;
  final double principalAmount;
  final double interestRate;
  final int tenureMonths;
  final double outstandingBalance;
  final DateTime startDate;
  final String currency;
  final bool isActive;
  final DateTime createdAt;

  /// Derived server-side from the ledger. Never trust widget state for
  /// this — a restart used to make a paid EMI look payable again.
  final bool emiPaidThisMonth;
  final DateTime? lastEmiPaymentDate;

  factory Loan.fromJson(Map<String, dynamic> json) {
    return Loan(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      loanType: LoanType.fromString(json['loan_type'] as String? ?? 'other'),
      principalAmount: (num.tryParse(json['principal_amount'].toString()) ?? 0).toDouble(),
      interestRate: (num.tryParse(json['interest_rate'].toString()) ?? 0).toDouble(),
      tenureMonths: json['tenure_months'] as int? ?? 12,
      outstandingBalance: (num.tryParse(json['outstanding_balance'].toString()) ?? 0).toDouble(),
      startDate: DateTime.tryParse(json['start_date'] as String? ?? '') ?? DateTime.now(),
      currency: json['currency'] as String? ?? 'INR',
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
      emiPaidThisMonth: json['emi_paid_this_month'] as bool? ?? false,
      lastEmiPaymentDate:
          DateTime.tryParse(json['last_emi_payment_date'] as String? ?? ''),
    );
  }
}
