/// Elevated Card (#1E1E1E) showing Total Debt (Credit Cards + Loans)
/// with subtle neon glow and dynamic countdowns.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import 'animated_counter.dart';

class DebtCard extends StatelessWidget {
  const DebtCard({
    super.key,
    required this.totalDebt,
    required this.creditCardDebt,
    required this.loanDebt,
    this.creditCardCount = 0,
    this.loanCount = 0,
  });

  final double totalDebt;
  final double creditCardDebt;
  final double loanDebt;
  final int creditCardCount;
  final int loanCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.charcoal, // #1E1E1E
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: AppColors.neonPink.withValues(alpha: 0.04),
            blurRadius: 32,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Title & Badge ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.neonPink,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TOTAL DEBT',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.neonPink.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                  border: Border.all(
                    color: AppColors.neonPink.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'LIABILITIES',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.neonPink,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Large Total Debt Amount ───────────────────────────────────
          AnimatedAmountCounter(
            amount: totalDebt,
            style: AppTypography.displayMedium.copyWith(
              fontSize: 32,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Visual Ratio Bar ──────────────────────────────────────────
          if (totalDebt > 0) ...[
            ClipRRect(
              borderRadius: AppRadius.pillAll,
              child: SizedBox(
                height: 5,
                child: Row(
                  children: [
                    Expanded(
                      flex: (creditCardDebt > 0 ? (creditCardDebt / totalDebt * 100).round() : 0).clamp(1, 99),
                      child: Container(color: AppColors.neonPink),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      flex: (loanDebt > 0 ? (loanDebt / totalDebt * 100).round() : 0).clamp(1, 99),
                      child: Container(color: AppColors.neonCyan),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          // ── Breakdown Row (Credit Cards & Loans) ───────────────────────
          Row(
            children: [
              Expanded(
                child: _buildDebtSubitem(
                  title: 'CREDIT CARDS',
                  subtitle: '$creditCardCount active cards',
                  amount: creditCardDebt,
                  dotColor: AppColors.neonPink,
                  icon: Icons.credit_card_rounded,
                ),
              ),
              Container(
                width: 1,
                height: 48,
                color: AppColors.subtleBorder,
                margin: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              ),
              Expanded(
                child: _buildDebtSubitem(
                  title: 'LOANS',
                  subtitle: '$loanCount active loans',
                  amount: loanDebt,
                  dotColor: AppColors.neonCyan,
                  icon: Icons.account_balance_outlined,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDebtSubitem({
    required String title,
    required String subtitle,
    required double amount,
    required Color dotColor,
    required IconData icon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: dotColor),
            const SizedBox(width: 6),
            Text(
              title,
              style: AppTypography.labelSmall.copyWith(
                color: AppColors.textTertiary,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        AnimatedAmountCounter(
          amount: amount,
          duration: const Duration(milliseconds: 1200),
          style: AppTypography.amountSmall(color: AppColors.textPrimary).copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textDisabled,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}
