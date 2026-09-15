/// Card displaying user's Credit Cards, dynamic billing summaries, and due dates.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/credit_card.dart';
import '../utils/currency_formatter.dart';

class CreditCardsListCard extends StatelessWidget {
  const CreditCardsListCard({
    super.key,
    required this.cards,
    required this.summaries,
  });

  final List<CreditCard> cards;
  final List<CreditCardSummary> summaries;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    // Map summary by cardId for quick lookup
    final summaryMap = {for (final s in summaries) s.cardId: s};

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
                  const Icon(Icons.credit_card_rounded, size: 16, color: AppColors.neonPink),
                  const SizedBox(width: 8),
                  Text(
                    'CREDIT CARDS & BILLS',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${cards.length} CARDS',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Card List ────────────────────────────────────────────
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cards.length,
            separatorBuilder: (context, index) => const Divider(color: AppColors.subtleBorder, height: 24),
            itemBuilder: (context, index) {
              final card = cards[index];
              final summary = summaryMap[card.id];
              final outstanding = summary?.totalOutstanding ?? (card.billedAmount + card.unbilledAmount);
              final totalLimit = summary?.totalLimit ?? card.totalLimit;
              final billed = summary?.billedAmount ?? card.billedAmount;
              final unbilled = summary?.unbilledAmount ?? card.unbilledAmount;
              // Null means the billing cycle is unknown; never default to a
              // comfortable-looking number, which reads as fact.
              final daysUntilDue = summary?.daysUntilDue;
              final usageRatio = totalLimit > 0 ? (outstanding / totalLimit).clamp(0.0, 1.0) : 0.0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                card.name,
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              if (card.lastFour != null) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '•• ${card.lastFour}',
                                  style: AppTypography.bodySmall.copyWith(
                                    color: AppColors.textTertiary,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Limit: ${CurrencyFormatter.format(totalLimit)}',
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 11,
                              color: AppColors.textDisabled,
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            CurrencyFormatter.format(outstanding),
                            style: AppTypography.amountSmall(color: AppColors.textPrimary).copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            daysUntilDue == null
                                ? 'Due date unavailable'
                                : daysUntilDue >= 0
                                    ? 'Due in $daysUntilDue days'
                                    : 'Overdue by ${daysUntilDue.abs()} days',
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: daysUntilDue == null
                                  ? AppColors.textTertiary
                                  : daysUntilDue <= 3
                                      ? AppColors.neonPink
                                      : AppColors.neonCyan,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // ── Utilization Progress Bar ──────────────────────────
                  ClipRRect(
                    borderRadius: AppRadius.pillAll,
                    child: LinearProgressIndicator(
                      value: usageRatio,
                      minHeight: 4,
                      backgroundColor: AppColors.obsidian,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usageRatio > 0.6 ? AppColors.neonPink : AppColors.neonCyan,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // ── Billed vs Unbilled tags ───────────────────────────
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Billed: ${CurrencyFormatter.format(billed)}',
                        style: AppTypography.bodySmall.copyWith(
                          fontSize: 11,
                          color: billed > 0 ? AppColors.neonPink : AppColors.textTertiary,
                        ),
                      ),
                      Text(
                        'Unbilled: ${CurrencyFormatter.format(unbilled)}',
                        style: AppTypography.bodySmall.copyWith(
                          fontSize: 11,
                          color: AppColors.textTertiary,
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
