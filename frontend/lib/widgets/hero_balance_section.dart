/// Hero section for the Dashboard displaying Total Liquid Balance
/// and the monthly Net Income indicator.
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../utils/currency_formatter.dart';
import 'animated_counter.dart';

class HeroBalanceSection extends StatelessWidget {
  const HeroBalanceSection({
    super.key,
    required this.totalLiquidBalance,
    required this.netIncomeThisMonth,
    required this.incomeThisMonth,
    required this.expenseThisMonth,
    required this.isHousehold,
  });

  final double totalLiquidBalance;
  final double netIncomeThisMonth;
  final double incomeThisMonth;
  final double expenseThisMonth;
  final bool isHousehold;

  @override
  Widget build(BuildContext context) {
    final isPositive = netIncomeThisMonth >= 0;
    final netIncomeColor = isPositive ? AppColors.neonGreen : AppColors.neonPink;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: AppColors.neonGreen.withValues(alpha: 0.03),
            blurRadius: 36,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header Label ──────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: AppColors.neonGreen,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    isHousehold ? 'HOUSEHOLD LIQUID BALANCE' : 'TOTAL LIQUID BALANCE',
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
                  color: AppColors.obsidian,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(color: AppColors.subtleBorder),
                ),
                child: Text(
                  'ASSETS',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),

          // ── Hero Amount (Dynamic Counter) ─────────────────────────────
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFFFFFFFF), Color(0xFFE0E0E0)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(bounds),
            child: AnimatedAmountCounter(
              amount: totalLiquidBalance,
              style: AppTypography.displayLarge.copyWith(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.2,
                height: 1.15,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Net Income This Month Indicator ───────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: netIncomeColor.withValues(alpha: 0.08),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: netIncomeColor.withValues(alpha: 0.25),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isPositive ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                  size: 18,
                  color: netIncomeColor,
                ),
                const SizedBox(width: 8),
                Text(
                  isPositive
                      ? '+${CurrencyFormatter.format(netIncomeThisMonth)}'
                      : CurrencyFormatter.format(netIncomeThisMonth),
                  style: AppTypography.labelMedium.copyWith(
                    color: netIncomeColor,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  'net cashflow this month',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Inflow vs Outflow Mini Stats ──────────────────────────────
          const Divider(color: AppColors.subtleBorder, height: 1),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: _buildCashflowPill(
                  label: 'INFLOW',
                  amount: incomeThisMonth,
                  color: AppColors.neonGreen,
                  icon: Icons.arrow_downward_rounded,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _buildCashflowPill(
                  label: 'OUTFLOW',
                  amount: expenseThisMonth,
                  color: AppColors.neonPink,
                  icon: Icons.arrow_upward_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCashflowPill({
    required String label,
    required double amount,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  fontSize: 10,
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
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
