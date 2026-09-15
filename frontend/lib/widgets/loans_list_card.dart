/// Card displaying active Loans and monthly EMI details.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/loan.dart';
import '../utils/currency_formatter.dart';

class LoansListCard extends StatelessWidget {
  const LoansListCard({
    super.key,
    required this.loans,
  });

  final List<Loan> loans;

  @override
  Widget build(BuildContext context) {
    if (loans.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_outlined, size: 16, color: AppColors.neonCyan),
                  const SizedBox(width: 8),
                  Text(
                    'ACTIVE LOANS',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${loans.length} ACTIVE',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Loan Items ───────────────────────────────────────────
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: loans.length,
            separatorBuilder: (context, index) => const Divider(color: AppColors.subtleBorder, height: 16),
            itemBuilder: (context, index) {
              final loan = loans[index];
              return Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: AppColors.subtleBorder),
                    ),
                    child: const Icon(Icons.real_estate_agent_outlined, size: 18, color: AppColors.neonCyan),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loan.name,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Text(
                          '${loan.interestRate}% p.a. • ${loan.tenureMonths}m tenure',
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 10.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        CurrencyFormatter.format(loan.outstandingBalance),
                        style: AppTypography.amountSmall(color: AppColors.textPrimary).copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Outstanding',
                        style: AppTypography.bodySmall.copyWith(
                          fontSize: 10,
                          color: AppColors.textDisabled,
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
