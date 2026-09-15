/// Card displaying recent ledger transactions with CRED neon styling.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../utils/currency_formatter.dart';

class RecentActivityCard extends StatelessWidget {
  const RecentActivityCard({
    super.key,
    required this.transactions,
  });

  final List<TransactionModel> transactions;

  @override
  Widget build(BuildContext context) {
    if (transactions.isEmpty) return const SizedBox.shrink();

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
                  const Icon(Icons.receipt_long_outlined, size: 16, color: AppColors.neonCyan),
                  const SizedBox(width: 8),
                  Text(
                    'RECENT ACTIVITY',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                'LATEST LEDGER',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Transaction Items ────────────────────────────────────
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: transactions.length.clamp(0, 5),
            separatorBuilder: (context, index) => const Divider(color: AppColors.subtleBorder, height: 16),
            itemBuilder: (context, index) {
              final tx = transactions[index];
              final isIncome = tx.transactionType == TransactionType.income;
              final isTransfer = tx.transactionType == TransactionType.transfer;

              final Color accentColor = isIncome
                  ? AppColors.neonGreen
                  : (isTransfer ? AppColors.neonCyan : AppColors.neonPink);

              final IconData iconData = isIncome
                  ? Icons.arrow_downward_rounded
                  : (isTransfer ? Icons.swap_horiz_rounded : Icons.arrow_upward_rounded);

              return Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                    ),
                    child: Icon(iconData, size: 16, color: accentColor),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              tx.category,
                              style: AppTypography.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            if (tx.isHouseholdShared) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: AppColors.neonCyan.withValues(alpha: 0.1),
                                  borderRadius: AppRadius.smAll,
                                ),
                                child: Text(
                                  'SHARED',
                                  style: AppTypography.labelSmall.copyWith(
                                    fontSize: 8.5,
                                    color: AppColors.neonCyan,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          tx.description?.isNotEmpty == true
                              ? tx.description!
                              : '${tx.transactionDate.day}/${tx.transactionDate.month}/${tx.transactionDate.year}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 11,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    // `tx.amount` is always positive — direction lives in
                    // transactionType — so the sign has to come from there.
                    // A transfer moves money between the user's own pots, so
                    // it stays unsigned.
                    CurrencyFormatter.format(
                      isTransfer || isIncome ? tx.amount : -tx.amount,
                      showSign: !isTransfer,
                    ),
                    style: AppTypography.amountSmall(color: accentColor).copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
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
