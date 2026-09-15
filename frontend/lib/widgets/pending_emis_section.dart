/// "Pending EMIs" section with calculated monthly EMI and a highly satisfying
/// tactile "Mark as Paid" tickbox triggering FastAPI fund transfers.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/loan.dart';
import '../providers/payment_providers.dart';
import '../utils/currency_formatter.dart';
import '../utils/loan_calculator.dart';

class PendingEmisSection extends ConsumerWidget {
  const PendingEmisSection({
    super.key,
    required this.loans,
    required this.accounts,
  });

  final List<Loan> loans;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeLoans =
        loans.where((l) => l.isActive && l.outstandingBalance > 0).toList();
    if (activeLoans.isEmpty) return const SizedBox.shrink();

    // "Due" means not yet paid this month, per the server. Counting every
    // active loan claimed money was owed that had already been paid.
    final dueCount = activeLoans.where((l) => !l.emiPaidThisMonth).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section Header ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.check_circle_outline_rounded, size: 16, color: AppColors.neonGreen),
                  const SizedBox(width: 8),
                  Text(
                    'PENDING EMIs',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: AppColors.subtleBorder),
                ),
                child: Text(
                  '$dueCount DUE THIS MONTH',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── EMI Items List ──────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: activeLoans.length,
            separatorBuilder: (context, index) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (context, index) {
              final loan = activeLoans[index];
              return _EmiTickCard(
                // Keyed by loan id so per-card state follows the loan, not the
                // list position, when the list reorders after a refresh.
                key: ValueKey(loan.id),
                loan: loan,
                accounts: accounts,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _EmiTickCard extends ConsumerStatefulWidget {
  const _EmiTickCard({
    super.key,
    required this.loan,
    required this.accounts,
  });

  final Loan loan;
  final List<Account> accounts;

  @override
  ConsumerState<_EmiTickCard> createState() => _EmiTickCardState();
}

class _EmiTickCardState extends ConsumerState<_EmiTickCard> {
  /// Seeded from the server so a restart doesn't resurrect a paid EMI.
  /// Flipped locally only to play the success animation after paying.
  late bool _isPaid = widget.loan.emiPaidThisMonth;
  bool _isProcessing = false;
  Map<String, dynamic>? _paymentResult;

  @override
  Widget build(BuildContext context) {
    final emiAmount = LoanCalculator.calculateMonthlyEmi(
      principal: widget.loan.principalAmount,
      annualRate: widget.loan.interestRate,
      tenureMonths: widget.loan.tenureMonths,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: _isPaid ? AppColors.elevatedSurface : AppColors.charcoal,
        borderRadius: AppRadius.xlAll,
        border: Border.all(
          color: _isPaid ? AppColors.neonGreen : AppColors.subtleBorder,
          width: _isPaid ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
          if (_isPaid)
            BoxShadow(
              color: AppColors.neonGreen.withValues(alpha: 0.15),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header: Loan Name and Interest Rate ───────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Expanded: the name is user-supplied and sits beside a
              // fixed-width badge, so without it a long one overflows.
              Expanded(
                child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.loan.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.headlineSmall.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${widget.loan.interestRate}% p.a. • ${widget.loan.tenureMonths}m tenure',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: AppColors.subtleBorder),
                ),
                child: Text(
                  'LOAN',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.neonCyan,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Middle: Calculated EMI Amount ─────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'MONTHLY EMI',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        CurrencyFormatter.format(emiAmount),
                        style: AppTypography.displaySmall.copyWith(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _isPaid ? AppColors.neonGreen : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '/ month',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Outstanding',
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10.5,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(widget.loan.outstandingBalance),
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),

          // ── Satisfying "Mark as Paid" Tickbox / Button ────────────
          _isPaid ? _buildPaidSuccessBadge() : _buildTickToPayButton(emiAmount),
        ],
      ),
    );
  }

  Widget _buildTickToPayButton(double emiAmount) {
    return GestureDetector(
      onTap: _isProcessing ? null : () => _showAccountSelectionAndPay(emiAmount),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          color: AppColors.obsidian,
          borderRadius: AppRadius.pillAll,
          border: Border.all(
            color: AppColors.neonGreen.withValues(alpha: 0.4),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.neonGreen.withValues(alpha: 0.08),
              blurRadius: 14,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                // Custom tactile check circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: AppColors.neonGreen,
                      width: 2.0,
                    ),
                  ),
                  child: _isProcessing
                      ? const Padding(
                          padding: EdgeInsets.all(5),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.neonGreen,
                          ),
                        )
                      : const Icon(
                          Icons.check_rounded,
                          size: 16,
                          color: AppColors.neonGreen,
                        ),
                ),
                const SizedBox(width: 12),
                Text(
                  _isProcessing ? 'Processing EMI transfer...' : 'MARK AS PAID',
                  style: AppTypography.labelMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
            if (!_isProcessing)
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 13,
                color: AppColors.neonGreen.withValues(alpha: 0.7),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaidSuccessBadge() {
    final principalComp = _paymentResult?['principal_component']?.toString();
    final interestComp = _paymentResult?['interest_component']?.toString();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.neonGreen.withValues(alpha: 0.1),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: const BoxDecoration(
              color: AppColors.neonGreen,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded, size: 18, color: AppColors.trueBlack),
          )
              .animate()
              .scale(duration: 400.ms, curve: Curves.elasticOut),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PAID FOR THIS MONTH',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.neonGreen,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.0,
                  ),
                ),
                if (principalComp != null && interestComp != null)
                  Text(
                    'Principal: ₹$principalComp • Interest: ₹$interestComp',
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10.5,
                      color: AppColors.textSecondary,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAccountSelectionAndPay(double emiAmount) {
    if (widget.accounts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No bank account found to deduct EMI from.')),
      );
      return;
    }

    // Modal to pick account
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: AppColors.charcoal,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border.all(color: AppColors.subtleBorder),
          ),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.textDisabled,
                    borderRadius: AppRadius.pillAll,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'PAY EMI FROM ACCOUNT',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.neonCyan,
                  letterSpacing: 1.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Deduct ${CurrencyFormatter.format(emiAmount)} for ${widget.loan.name}',
                style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              ...widget.accounts.map((acc) {
                final hasBalance = acc.currentBalance >= emiAmount;

                return GestureDetector(
                  onTap: !hasBalance
                      ? null
                      : () async {
                          Navigator.of(ctx).pop();
                          await _executeEmiPayment(acc.id);
                        },
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                        color: hasBalance ? AppColors.subtleBorder : AppColors.neonPink.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acc.name,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: hasBalance ? AppColors.textPrimary : AppColors.textDisabled,
                              ),
                            ),
                            Text(
                              'Balance: ${CurrencyFormatter.format(acc.currentBalance)}',
                              style: AppTypography.bodySmall.copyWith(
                                fontSize: 11,
                                color: hasBalance ? AppColors.textSecondary : AppColors.neonPink,
                              ),
                            ),
                          ],
                        ),
                        if (hasBalance)
                          const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.neonGreen)
                        else
                          Text(
                            'Insufficient',
                            style: AppTypography.labelSmall.copyWith(
                              color: AppColors.neonPink,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }

  Future<void> _executeEmiPayment(String accountId) async {
    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    final result = await ref.read(paymentControllerProvider.notifier).payLoanEmi(
          loanId: widget.loan.id,
          accountId: accountId,
        );

    if (mounted) {
      if (result != null) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isProcessing = false;
          _isPaid = true;
          _paymentResult = result;
        });
      } else {
        setState(() => _isProcessing = false);
        final err = ref.read(paymentControllerProvider).errorMessage ?? 'Payment failed';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.charcoal,
            content: Text(err, style: const TextStyle(color: AppColors.neonPink)),
          ),
        );
      }
    }
  }
}
