/// CRED-inspired Dashboard screen showcasing liquid balance, debt, and cashflow.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/dashboard_summary.dart';
import '../providers/dashboard_providers.dart';
import '../widgets/add_transaction_sheet.dart';
import '../widgets/budget_card.dart';
import '../widgets/credit_card_alarms_list.dart';
import '../widgets/debt_card.dart';
import '../widgets/hero_balance_section.dart';
import '../widgets/household_toggle.dart';
import '../widgets/monthly_income_card.dart';
import '../widgets/pending_emis_section.dart';
import '../widgets/recent_activity_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isHousehold = ref.watch(householdModeProvider);
    final summaryAsync = ref.watch(dashboardSummaryProvider);

    return Scaffold(
      backgroundColor: AppColors.trueBlack,
      // Capture is the app's primary action, so it gets the primary affordance.
      // It needs the account/card lists, so it only appears once they've loaded.
      floatingActionButton: summaryAsync.maybeWhen(
        data: (summary) => _buildAddTransactionButton(context, summary),
        orElse: () => null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── Top Navigation Bar ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'FINANCES',
                        style: AppTypography.labelSmall.copyWith(
                          color: AppColors.textTertiary,
                          letterSpacing: 2.0,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Dashboard',
                        style: AppTypography.headlineMedium.copyWith(
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  // Private vs Household Switch
                  Row(
                    children: [
                      HouseholdToggle(
                        isHousehold: isHousehold,
                        onChanged: (val) {
                          ref.read(householdModeProvider.notifier).setMode(val);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.tune_rounded, size: 20),
                        color: AppColors.textTertiary,
                        tooltip: 'Manage accounts, cards and loans',
                        onPressed: () => context.push('/manage'),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // ── Scrollable Body ────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                color: AppColors.neonCyan,
                backgroundColor: AppColors.charcoal,
                onRefresh: () async {
                  ref.invalidate(accountsProvider);
                  ref.invalidate(creditCardsProvider);
                  ref.invalidate(loansProvider);
                  ref.invalidate(monthlyTransactionsProvider);
                  ref.invalidate(recentTransactionsProvider);
                  await ref.read(dashboardSummaryProvider.future);
                },
                child: summaryAsync.when(
                  loading: () => _buildLoadingSkeleton(),
                  error: (err, stack) => _buildErrorState(context, ref, err),
                  data: (summary) => _buildDashboardContent(context, ref, summary, isHousehold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the capture sheet. Providers refresh themselves on success, so
  /// there is nothing to do with the result here.
  Widget _buildAddTransactionButton(
    BuildContext context,
    DashboardSummary summary,
  ) {
    return FloatingActionButton.extended(
      onPressed: () => AddTransactionSheet.show(
        context,
        accounts: summary.accounts,
        cards: summary.creditCards,
      ),
      backgroundColor: AppColors.neonGreen,
      foregroundColor: AppColors.trueBlack,
      // The app theme sets CircleBorder for round FABs; an extended FAB has to
      // opt out or its label overflows the circle and gets clipped.
      shape: const StadiumBorder(),
      extendedPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      icon: const Icon(Icons.add_rounded, size: 22),
      label: Text(
        'ADD',
        style: AppTypography.labelLarge.copyWith(
          color: AppColors.trueBlack,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildDashboardContent(
    BuildContext context,
    WidgetRef ref,
    DashboardSummary summary,
    bool isHousehold,
  ) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      // Bottom room so the last card clears the floating ADD button.
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.sm, 0, 96),
      children: [
        // 1. Hero Balance Card (Liquid Bank Accounts + Net Income this month)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: HeroBalanceSection(
            totalLiquidBalance: summary.totalLiquidBalance,
            netIncomeThisMonth: summary.netIncomeThisMonth,
            incomeThisMonth: summary.incomeThisMonth,
            expenseThisMonth: summary.expenseThisMonth,
            isHousehold: isHousehold,
          )
              .animate()
              .fadeIn(duration: 400.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 400.ms, curve: Curves.easeOutCubic),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 2. Elevated Floating Card: Total Debt (Cards + Loans)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: DebtCard(
            totalDebt: summary.totalDebt,
            creditCardDebt: summary.creditCardDebt,
            loanDebt: summary.loanDebt,
            creditCardCount: summary.creditCards.length,
            loanCount: summary.loans.length,
          )
              .animate()
              .fadeIn(duration: 450.ms, delay: 80.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 450.ms, curve: Curves.easeOutCubic),
        ),

        if (summary.creditCards.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          // 3. Credit Card Alarms (Horizontally Scrollable with Amber/Red glow)
          CreditCardAlarmsList(
            cards: summary.creditCards,
            summaries: summary.creditCardSummaries,
            accounts: summary.accounts,
          )
              .animate()
              .fadeIn(duration: 500.ms, delay: 140.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),
        ],

        if (summary.loans.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          // 4. Pending EMIs Tick-to-Pay Section
          PendingEmisSection(
            loans: summary.loans,
            accounts: summary.accounts,
          )
              .animate()
              .fadeIn(duration: 550.ms, delay: 200.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 550.ms, curve: Curves.easeOutCubic),
        ],

        const SizedBox(height: AppSpacing.lg),

        // 5. Monthly budget progress
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: const BudgetCard()
              .animate()
              .fadeIn(duration: 600.ms, delay: 230.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 600.ms, curve: Curves.easeOutCubic),
        ),

        const SizedBox(height: AppSpacing.lg),

        // 6. Standing monthly income (set up / next deposit)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: MonthlyIncomeCard(accounts: summary.accounts)
              .animate()
              .fadeIn(duration: 600.ms, delay: 260.ms, curve: Curves.easeOut)
              .slideY(begin: 0.08, end: 0, duration: 600.ms, curve: Curves.easeOutCubic),
        ),

        if (summary.recentTransactions.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          // 7. Recent Ledger Activity
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: RecentActivityCard(
              transactions: summary.recentTransactions,
            )
                .animate()
                .fadeIn(duration: 650.ms, delay: 320.ms, curve: Curves.easeOut)
                .slideY(begin: 0.08, end: 0, duration: 650.ms, curve: Curves.easeOutCubic),
          ),
        ],

        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }

  Widget _buildLoadingSkeleton() {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
      children: [
        _buildSkeletonBox(height: 230),
        const SizedBox(height: AppSpacing.lg),
        _buildSkeletonBox(height: 180),
        const SizedBox(height: AppSpacing.lg),
        _buildSkeletonBox(height: 140),
      ],
    );
  }

  Widget _buildSkeletonBox({required double height}) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: AppRadius.xlAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat(reverse: true))
        .shimmer(
          duration: 1200.ms,
          color: AppColors.elevatedSurface.withValues(alpha: 0.4),
        );
  }

  Widget _buildErrorState(BuildContext context, WidgetRef ref, Object error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.neonPink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.error_outline_rounded, size: 28, color: AppColors.neonPink),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Unable to load finances',
              style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              // Never surface error.toString(): for a Dio failure that is a
              // stack-ish dump including the internal API URL.
              _friendlyError(error),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.charcoal,
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.subtleBorder),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () {
                ref.invalidate(dashboardSummaryProvider);
              },
              child: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Turn an exception into something a person can act on.
///
/// The server sends `{"detail": ..., "request_id": ...}`; the request id is
/// worth showing because it is the thread back to the server-side log line.
String _friendlyError(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final detail = data['detail'];
      final requestId = data['request_id'];
      if (detail is String && detail.isNotEmpty) {
        return requestId is String && requestId != '-'
            ? '$detail (ref $requestId)'
            : detail;
      }
    }
    if (error.response == null) {
      return 'Cannot reach the server. Check your connection and try again.';
    }
    return 'The server returned an error (HTTP ${error.response?.statusCode}).';
  }
  return 'Something went wrong. Pull down to try again.';
}
