/// Dashboard card for the standing monthly income.
///
/// Two states: a call to action when nothing is set up, and a summary with the
/// next deposit date once it is.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/recurring_income.dart';
import '../providers/recurring_income_providers.dart';
import '../utils/currency_formatter.dart';
import 'monthly_income_sheet.dart';

class MonthlyIncomeCard extends ConsumerWidget {
  const MonthlyIncomeCard({super.key, required this.accounts});

  final List<Account> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final incomeAsync = ref.watch(recurringIncomeProvider);

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
          Row(
            children: [
              const Icon(Icons.event_repeat_outlined,
                  size: 16, color: AppColors.neonGreen),
              const SizedBox(width: 8),
              Text(
                'MONTHLY INCOME',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textTertiary,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          incomeAsync.when(
            loading: () => const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonGreen,
                  ),
                ),
              ),
            ),
            error: (err, _) => Text(
              'Could not load your monthly income.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.neonPink),
            ),
            data: (income) => income == null
                ? _buildEmpty(context)
                : _buildConfigured(context, income),
          ),
        ],
      ),
    );
  }

  // ── Not set up yet ───────────────────────────────────────────────────────

  Widget _buildEmpty(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Tell us what you earn each month and when it arrives — '
          'it will be added to your balance automatically.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 46,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.neonGreen,
              foregroundColor: AppColors.trueBlack,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
            onPressed: () => MonthlyIncomeSheet.show(
              context,
              accounts: accounts,
            ),
            icon: const Icon(Icons.add_rounded, size: 20),
            label: Text(
              'SET MONTHLY INCOME',
              style: AppTypography.labelLarge.copyWith(
                color: AppColors.trueBlack,
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Configured ───────────────────────────────────────────────────────────

  Widget _buildConfigured(BuildContext context, RecurringIncome income) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    CurrencyFormatter.format(income.amount),
                    style: AppTypography.amountLarge(
                      color: AppColors.neonGreen,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'every month on the ${income.dayLabel}'
                    '${income.accountName != null ? ' → ${income.accountName}' : ''}',
                    style: AppTypography.bodySmall,
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: () => MonthlyIncomeSheet.show(
                context,
                accounts: accounts,
                existing: income,
              ),
              child: const Text('Edit'),
            ),
          ],
        ),

        if (income.nextDueDate != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.obsidian,
              borderRadius: AppRadius.mdAll,
              border: Border.all(color: AppColors.subtleBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule,
                    size: 15, color: AppColors.neonCyan),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Next deposit ${_friendlyDate(income.nextDueDate!)}',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ],

        // The server may have posted months while the app was closed — say so
        // rather than letting the balance change without explanation.
        if (income.postedThisRun > 0) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            decoration: BoxDecoration(
              color: AppColors.neonGreen.withValues(alpha: 0.08),
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: AppColors.neonGreen.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline,
                    size: 15, color: AppColors.neonGreen),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    income.postedThisRun == 1
                        ? 'Just added this month\'s income'
                        : 'Just added ${income.postedThisRun} months of income',
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.neonGreen),
                  ),
                ),
              ],
            ),
          ),
        ],

        if (!income.isActive) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Paused — no new months will be added.',
            style:
                AppTypography.bodySmall.copyWith(color: AppColors.neonAmber),
          ),
        ],
      ],
    );
  }

  String _friendlyDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final today = DateTime.now();
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(today.year, today.month, today.day))
        .inDays;

    if (days == 0) return 'today';
    if (days == 1) return 'tomorrow';
    if (days > 1 && days <= 30) return 'in $days days';
    return 'on ${d.day} ${months[d.month - 1]}';
  }
}
