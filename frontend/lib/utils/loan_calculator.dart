/// Utility for client-side loan calculations matching FastAPI backend.
library;

import 'dart:math' as math;

class LoanCalculator {
  LoanCalculator._();

  /// Calculates monthly EMI for given principal, annual interest rate %, and tenure in months.
  static double calculateMonthlyEmi({
    required double principal,
    required double annualRate,
    required int tenureMonths,
  }) {
    if (principal <= 0 || tenureMonths <= 0) return 0.0;
    if (annualRate <= 0) return principal / tenureMonths;

    final monthlyRate = (annualRate / 100) / 12;
    final factor = math.pow(1 + monthlyRate, tenureMonths);
    final emi = principal * monthlyRate * factor / (factor - 1);
    return emi.toDouble();
  }
}
