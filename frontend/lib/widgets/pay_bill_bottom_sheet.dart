/// Tactile modal bottom sheet to select a Bank Account and pay a Credit Card bill.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../providers/payment_providers.dart';
import '../utils/currency_formatter.dart';

class PayBillBottomSheet extends ConsumerStatefulWidget {
  const PayBillBottomSheet({
    super.key,
    required this.card,
    required this.summary,
    required this.accounts,
  });

  final CreditCard card;
  final CreditCardSummary summary;
  final List<Account> accounts;

  static Future<bool?> show(
    BuildContext context, {
    required CreditCard card,
    required CreditCardSummary summary,
    required List<Account> accounts,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PayBillBottomSheet(
        card: card,
        summary: summary,
        accounts: accounts,
      ),
    );
  }

  @override
  ConsumerState<PayBillBottomSheet> createState() => _PayBillBottomSheetState();
}

class _PayBillBottomSheetState extends ConsumerState<PayBillBottomSheet> {
  late String? _selectedAccountId;
  late double _amountToPay;
  bool _isSuccess = false;

  @override
  void initState() {
    super.initState();
    // Default to billed amount (or total outstanding if billed is 0)
    _amountToPay = widget.summary.billedAmount > 0
        ? widget.summary.billedAmount
        : widget.summary.totalOutstanding;

    // Pick first bank account with sufficient balance if available
    final eligible = widget.accounts.where((a) => a.currentBalance >= _amountToPay).toList();
    _selectedAccountId = eligible.isNotEmpty
        ? eligible.first.id
        : (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);
  }

  @override
  Widget build(BuildContext context) {
    final paymentState = ref.watch(paymentControllerProvider);
    final selectedAccount = widget.accounts.where((a) => a.id == _selectedAccountId).firstOrNull;
    final hasEnoughBalance = selectedAccount != null && selectedAccount.currentBalance >= _amountToPay;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        border: Border.all(color: AppColors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.8),
            blurRadius: 36,
            offset: const Offset(0, -10),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xl,
      ),
      child: _isSuccess
          ? _buildSuccessView()
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Drag Handle ──────────────────────────────────────────
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

                // ── Title & Card Info ────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Expanded: the name is user-supplied and sits beside a
                    // fixed-width chip.
                    Expanded(
                      child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'PAY CREDIT CARD BILL',
                          style: AppTypography.labelSmall.copyWith(
                            color: AppColors.neonCyan,
                            letterSpacing: 1.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.card.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.headlineSmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    if (widget.card.lastFour != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: AppColors.obsidian,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(color: AppColors.subtleBorder),
                        ),
                        child: Text(
                          '•••• ${widget.card.lastFour}',
                          style: AppTypography.labelMedium.copyWith(
                            letterSpacing: 1.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Amount Pill Selection ────────────────────────────────
                Text(
                  'SELECT AMOUNT',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    if (widget.summary.billedAmount > 0)
                      Expanded(
                        child: _buildAmountOption(
                          label: 'BILLED',
                          amount: widget.summary.billedAmount,
                          isSelected: _amountToPay == widget.summary.billedAmount,
                          onTap: () => setState(() => _amountToPay = widget.summary.billedAmount),
                        ),
                      ),
                    if (widget.summary.billedAmount > 0) const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _buildAmountOption(
                        label: 'TOTAL DUE',
                        amount: widget.summary.totalOutstanding,
                        isSelected: _amountToPay == widget.summary.totalOutstanding,
                        onTap: () => setState(() => _amountToPay = widget.summary.totalOutstanding),
                      ),
                    ),
                    if (widget.summary.minDueAmount > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _buildAmountOption(
                          label: 'MIN DUE',
                          amount: widget.summary.minDueAmount,
                          isSelected: _amountToPay == widget.summary.minDueAmount,
                          onTap: () => setState(() => _amountToPay = widget.summary.minDueAmount),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),

                // ── Account Selector ─────────────────────────────────────
                Text(
                  'PAY FROM BANK ACCOUNT',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (widget.accounts.isEmpty)
                  Text(
                    'No bank accounts found to deduct from.',
                    style: AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
                  )
                else
                  ...widget.accounts.map((acc) {
                    final isSelected = acc.id == _selectedAccountId;
                    final hasBalance = acc.currentBalance >= _amountToPay;

                    return GestureDetector(
                      onTap: () => setState(() => _selectedAccountId = acc.id),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.elevatedSurface : AppColors.obsidian,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(
                            color: isSelected
                                ? AppColors.neonCyan
                                : AppColors.subtleBorder,
                            width: isSelected ? 1.5 : 1.0,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
                              size: 18,
                              color: isSelected ? AppColors.neonCyan : AppColors.textTertiary,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    acc.name,
                                    style: AppTypography.bodyMedium.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    'Balance: ${CurrencyFormatter.format(acc.currentBalance)}',
                                    style: AppTypography.bodySmall.copyWith(
                                      color: hasBalance ? AppColors.textSecondary : AppColors.neonPink,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!hasBalance)
                              Text(
                                'Low balance',
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

                if (paymentState.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    paymentState.errorMessage!,
                    style: AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
                  ),
                ],

                const SizedBox(height: AppSpacing.lg),

                // ── Pay CTA Button ───────────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: hasEnoughBalance ? AppColors.neonCyan : AppColors.elevatedSurface,
                      foregroundColor: AppColors.trueBlack,
                      disabledBackgroundColor: AppColors.elevatedSurface,
                      disabledForegroundColor: AppColors.textDisabled,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
                      elevation: hasEnoughBalance ? 8 : 0,
                    ),
                    onPressed: (!hasEnoughBalance || paymentState.isLoading)
                        ? null
                        : () async {
                            final navigator = Navigator.of(context);
                            final success = await ref
                                .read(paymentControllerProvider.notifier)
                                .payCreditCardBill(
                                  cardId: widget.card.id,
                                  cardName: widget.card.name,
                                  accountId: _selectedAccountId!,
                                  amount: _amountToPay,
                                );
                            if (!mounted) return;
                            if (success) {
                              setState(() => _isSuccess = true);
                              Future.delayed(const Duration(milliseconds: 1400), () {
                                if (mounted) navigator.pop(true);
                              });
                            }
                          },
                    child: paymentState.isLoading
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : Text(
                            'PAY ${CurrencyFormatter.format(_amountToPay)}',
                            style: AppTypography.labelLarge.copyWith(
                              color: hasEnoughBalance ? AppColors.trueBlack : AppColors.textDisabled,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.0,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildAmountOption({
    required String label,
    required double amount,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.elevatedSurface : AppColors.obsidian,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: isSelected ? AppColors.neonCyan : AppColors.subtleBorder,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                fontSize: 9.5,
                color: isSelected ? AppColors.neonCyan : AppColors.textTertiary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              CurrencyFormatter.format(amount),
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                fontSize: 12.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSuccessView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.neonGreen,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, size: 38, color: AppColors.trueBlack),
            )
                .animate()
                .scale(duration: 400.ms, curve: Curves.elasticOut),
            const SizedBox(height: AppSpacing.md),
            Text(
              'PAYMENT SUCCESSFUL',
              style: AppTypography.headlineSmall.copyWith(
                color: AppColors.neonGreen,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${CurrencyFormatter.format(_amountToPay)} transferred to ${widget.card.name}',
              style: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
