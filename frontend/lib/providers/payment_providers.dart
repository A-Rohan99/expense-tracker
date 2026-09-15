/// Riverpod payment controller handling Credit Card bill payments and Loan EMI deductions.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_service.dart';
import 'dashboard_providers.dart';

class PaymentState {
  const PaymentState({
    this.isLoading = false,
    this.errorMessage,
    this.successMessage,
  });

  final bool isLoading;
  final String? errorMessage;
  final String? successMessage;

  PaymentState copyWith({
    bool? isLoading,
    String? errorMessage,
    String? successMessage,
  }) {
    return PaymentState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
  }
}

class PaymentController extends Notifier<PaymentState> {
  @override
  PaymentState build() => const PaymentState();

  /// Executes Credit Card bill payment by creating a transfer transaction.
  Future<bool> payCreditCardBill({
    required String cardId,
    required String cardName,
    required String accountId,
    required double amount,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, successMessage: null);

    try {
      final dio = ref.read(dioProvider);
      await dio.post(
        '/transactions/',
        data: {
          'transaction_type': 'transfer',
          'amount': amount,
          'currency': 'INR',
          'category': 'Credit Card Bill',
          'description': 'Payment for $cardName',
          'account_id': accountId,
          'credit_card_id': cardId,
          'is_household_shared': false,
        },
      );

      // Invalidate relevant providers to trigger immediate reactive refresh
      _refreshAllData();

      state = state.copyWith(
        isLoading: false,
        successMessage: 'Bill payment of ₹${amount.toStringAsFixed(0)} successful!',
      );
      return true;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail']?.toString() ?? e.message ?? 'Payment failed';
      state = state.copyWith(isLoading: false, errorMessage: detail);
      return false;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return false;
    }
  }

  /// Executes Loan EMI payment via POST /loans/{loan_id}/pay-emi
  Future<Map<String, dynamic>?> payLoanEmi({
    required String loanId,
    required String accountId,
  }) async {
    state = state.copyWith(isLoading: true, errorMessage: null, successMessage: null);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/loans/$loanId/pay-emi',
        data: {
          'account_id': accountId,
        },
      );

      _refreshAllData();

      final data = response.data as Map<String, dynamic>;
      final emiAmount = data['emi_amount']?.toString() ?? '0';

      state = state.copyWith(
        isLoading: false,
        successMessage: 'EMI of ₹$emiAmount deducted successfully!',
      );
      return data;
    } on DioException catch (e) {
      final detail = e.response?.data?['detail']?.toString() ?? e.message ?? 'EMI payment failed';
      state = state.copyWith(isLoading: false, errorMessage: detail);
      return null;
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
      return null;
    }
  }

  void _refreshAllData() {
    ref.invalidate(accountsProvider);
    ref.invalidate(creditCardsProvider);
    ref.invalidate(creditCardSummariesProvider);
    ref.invalidate(loansProvider);
    ref.invalidate(monthlyTransactionsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(dashboardSummaryProvider);
  }
}

final paymentControllerProvider = NotifierProvider<PaymentController, PaymentState>(
  PaymentController.new,
);
