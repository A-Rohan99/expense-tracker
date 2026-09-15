/// Card displaying user's liquid asset accounts (Banks, Wallets, Cash).
library;

import 'package:flutter/material.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../utils/currency_formatter.dart';

class AccountsListCard extends StatelessWidget {
  const AccountsListCard({
    super.key,
    required this.accounts,
    this.onAddAccount,
  });

  final List<Account> accounts;
  final VoidCallback? onAddAccount;

  @override
  Widget build(BuildContext context) {
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
                  const Icon(Icons.account_balance_wallet_outlined, size: 16, color: AppColors.neonGreen),
                  const SizedBox(width: 8),
                  Text(
                    'BANK ACCOUNTS & WALLETS',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              Text(
                '${accounts.length} ACCOUNTS',
                style: AppTypography.labelSmall.copyWith(
                  color: AppColors.textDisabled,
                  fontSize: 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),

          // ── Account Items ────────────────────────────────────────
          if (accounts.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(
                child: Text(
                  'No accounts linked yet.',
                  style: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: accounts.length,
              separatorBuilder: (context, index) => const Divider(color: AppColors.subtleBorder, height: 16),
              itemBuilder: (context, index) {
                final account = accounts[index];
                final icon = _getAccountIcon(account.accountType);

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
                      child: Icon(icon, size: 18, color: AppColors.textSecondary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            account.name,
                            style: AppTypography.bodyMedium.copyWith(
                              fontWeight: FontWeight.w600,
                              color: AppColors.textPrimary,
                            ),
                          ),
                          Text(
                            account.accountType.name.toUpperCase(),
                            style: AppTypography.bodySmall.copyWith(
                              fontSize: 10.5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      CurrencyFormatter.format(account.currentBalance),
                      style: AppTypography.amountSmall(color: AppColors.textPrimary).copyWith(
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

  IconData _getAccountIcon(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return Icons.account_balance_rounded;
      case AccountType.cash:
        return Icons.money_rounded;
      case AccountType.wallet:
        return Icons.wallet_rounded;
    }
  }
}
