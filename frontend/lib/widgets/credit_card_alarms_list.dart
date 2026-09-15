/// Horizontally scrollable list of Credit Card Alarms with dynamic CRED neon styling.
///
/// Due Date Alarm States:
/// - > 7 days away: Subtle accent & border.
/// - <= 7 days away: Glowing Neon Amber border/accent.
/// - Overdue (< 0 days): Pulsating Neon Red accent with continuous glow animation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../utils/currency_formatter.dart';
import 'pay_bill_bottom_sheet.dart';

enum CardAlarmSeverity {
  subtle,
  warningAmber,
  overdueRed,

  /// The billing cycle could not be fetched. Distinct from [subtle] on
  /// purpose: "we don't know" must not look like "nothing due soon".
  unknown,
}

class CreditCardAlarmsList extends StatelessWidget {
  const CreditCardAlarmsList({
    super.key,
    required this.cards,
    required this.summaries,
    required this.accounts,
  });

  final List<CreditCard> cards;
  final List<CreditCardSummary> summaries;
  final List<Account> accounts;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();

    final summaryMap = {for (final s in summaries) s.cardId: s};

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
                  const Icon(Icons.notifications_active_outlined, size: 16, color: AppColors.neonAmber),
                  const SizedBox(width: 8),
                  Text(
                    'BILL ALARMS & CREDIT LINES',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Text(
                'SWIPE FOR MORE',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 9.5,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        // ── Horizontal Cards Slider ─────────────────────────────────
        SizedBox(
          height: 220,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            itemCount: cards.length,
            separatorBuilder: (context, index) => const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final card = cards[index];
              // No summary for this card means the billing cycle is unknown.
              // Leave the dates null rather than guessing one.
              final summary = summaryMap[card.id] ??
                  CreditCardSummary(
                    cardId: card.id,
                    cardName: card.name,
                    totalLimit: card.totalLimit,
                    billedAmount: card.billedAmount,
                    unbilledAmount: card.unbilledAmount,
                    totalOutstanding: card.billedAmount + card.unbilledAmount,
                    availableLimit:
                        card.totalLimit - (card.billedAmount + card.unbilledAmount),
                    totalPayments: 0.0,
                    minDueAmount: 0.0,
                  );

              return _CreditCardAlarmItem(
                card: card,
                summary: summary,
                accounts: accounts,
              );
            },
          ),
        ),
      ],
    );
  }
}

class _CreditCardAlarmItem extends StatelessWidget {
  const _CreditCardAlarmItem({
    required this.card,
    required this.summary,
    required this.accounts,
  });

  final CreditCard card;
  final CreditCardSummary summary;
  final List<Account> accounts;

  CardAlarmSeverity get _severity {
    final days = summary.daysUntilDue;
    // No cycle info means we genuinely don't know when this is due. Falling
    // through to `subtle` would quietly imply "plenty of time".
    if (days == null) return CardAlarmSeverity.unknown;
    if (days < 0) return CardAlarmSeverity.overdueRed;
    if (days <= 7) return CardAlarmSeverity.warningAmber;
    return CardAlarmSeverity.subtle;
  }

  Color get _accentColor {
    switch (_severity) {
      case CardAlarmSeverity.overdueRed:
        return AppColors.neonRed;
      case CardAlarmSeverity.warningAmber:
        return AppColors.neonAmber;
      case CardAlarmSeverity.subtle:
        return AppColors.neonCyan;
      case CardAlarmSeverity.unknown:
        return AppColors.textTertiary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final billed = summary.billedAmount > 0 ? summary.billedAmount : summary.totalOutstanding;
    final isOverdue = _severity == CardAlarmSeverity.overdueRed;
    final isAmberWarning = _severity == CardAlarmSeverity.warningAmber;

    Widget cardWidget = Container(
      width: 305,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: AppRadius.xlAll,
        border: Border.all(
          color: isOverdue
              ? AppColors.neonRed
              : (isAmberWarning ? AppColors.neonAmber : AppColors.subtleBorder),
          width: isOverdue ? 1.8 : (isAmberWarning ? 1.5 : 1.0),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.6),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
          if (isAmberWarning)
            BoxShadow(
              color: AppColors.neonAmber.withValues(alpha: 0.22),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          if (isOverdue)
            BoxShadow(
              color: AppColors.neonRed.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, 4),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // ── Top Row: Name, Chip & Alarm Badge ───────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 30,
                    height: 22,
                    decoration: BoxDecoration(
                      color: AppColors.obsidian,
                      borderRadius: AppRadius.smAll,
                      border: Border.all(color: _accentColor.withValues(alpha: 0.4)),
                    ),
                    child: Center(
                      child: Icon(Icons.credit_card, size: 14, color: _accentColor),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.name,
                        style: AppTypography.bodyMedium.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      if (card.lastFour != null)
                        Text(
                          '•••• ${card.lastFour}',
                          style: AppTypography.bodySmall.copyWith(
                            fontSize: 10.5,
                            color: AppColors.textTertiary,
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              _buildAlarmBadge(),
            ],
          ),

          // ── Middle: Billed Balance & Available Limit ────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    summary.billedAmount > 0 ? 'BILLED DUE' : 'OUTSTANDING',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.0,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    CurrencyFormatter.format(billed),
                    style: AppTypography.displaySmall.copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Available Limit',
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 10,
                      color: AppColors.textDisabled,
                    ),
                  ),
                  Text(
                    CurrencyFormatter.format(summary.availableLimit),
                    style: AppTypography.bodySmall.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ],
          ),

          // ── Bottom: Tactile "Pay Bill" Button ───────────────────────
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isOverdue
                    ? AppColors.neonRed.withValues(alpha: 0.15)
                    : (isAmberWarning
                        ? AppColors.neonAmber.withValues(alpha: 0.15)
                        : AppColors.obsidian),
                foregroundColor: AppColors.textPrimary,
                elevation: 0,
                side: BorderSide(
                  color: isOverdue
                      ? AppColors.neonRed
                      : (isAmberWarning ? AppColors.neonAmber : AppColors.subtleBorder),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
                padding: const EdgeInsets.symmetric(horizontal: 16),
              ),
              onPressed: () {
                PayBillBottomSheet.show(
                  context,
                  card: card,
                  summary: summary,
                  accounts: accounts,
                );
              },
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.bolt_rounded,
                    size: 16,
                    color: _accentColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'PAY BILL',
                    style: AppTypography.labelSmall.copyWith(
                      color: _accentColor,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    // Apply pulsating neon animation for overdue cards
    if (isOverdue) {
      cardWidget = cardWidget
          .animate(onPlay: (controller) => controller.repeat(reverse: true))
          .scaleXY(
            begin: 1.0,
            end: 1.015,
            duration: 800.ms,
            curve: Curves.easeInOut,
          );
    }

    return cardWidget;
  }

  Widget _buildAlarmBadge() {
    final days = summary.daysUntilDue;

    String label;
    IconData icon;
    Color color;

    switch (_severity) {
      case CardAlarmSeverity.overdueRed:
        label = 'OVERDUE ${days!.abs()}d';
        icon = Icons.error_outline_rounded;
        color = AppColors.neonRed;
      case CardAlarmSeverity.warningAmber:
        label = 'DUE IN ${days}d';
        icon = Icons.access_time_rounded;
        color = AppColors.neonAmber;
      case CardAlarmSeverity.subtle:
        label = 'Due in ${days}d';
        icon = Icons.calendar_today_rounded;
        color = AppColors.textTertiary;
      case CardAlarmSeverity.unknown:
        label = 'DUE DATE UNAVAILABLE';
        icon = Icons.help_outline_rounded;
        color = AppColors.textTertiary;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.smAll,
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: AppTypography.labelSmall.copyWith(
              color: color,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
