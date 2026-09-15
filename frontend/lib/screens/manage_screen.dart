/// Everything the dashboard can't do: add and edit the instruments the ledger
/// records against, and sign out.
///
/// Before this screen a new signup landed on an empty dashboard with no way to
/// create an account, card or loan — and no way to log out either.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../models/loan.dart';
import '../providers/dashboard_providers.dart';
import '../providers/manage_providers.dart';
import '../utils/currency_formatter.dart';
import '../widgets/household_card.dart';
import '../widgets/instrument_form_sheet.dart';

class ManageScreen extends ConsumerWidget {
  const ManageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider);
    final cards = ref.watch(creditCardsProvider);
    final loans = ref.watch(loansProvider);

    return Scaffold(
      backgroundColor: AppColors.trueBlack,
      appBar: AppBar(
        backgroundColor: AppColors.trueBlack,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () => context.go('/home'),
        ),
        title: Text('Manage', style: AppTypography.headlineMedium),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.neonCyan,
          backgroundColor: AppColors.charcoal,
          onRefresh: () async {
            ref.invalidate(accountsProvider);
            ref.invalidate(creditCardsProvider);
            ref.invalidate(loansProvider);
            await ref.read(accountsProvider.future);
          },
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xxl,
            ),
            children: [
              _Section<Account>(
                title: 'ACCOUNTS & WALLETS',
                icon: Icons.account_balance_wallet_outlined,
                addLabel: 'Add account',
                data: accounts,
                emptyMessage:
                    'Add a bank account or wallet to start recording spending.',
                onAdd: () => InstrumentFormSheet.account(context),
                onEdit: (a) =>
                    InstrumentFormSheet.account(context, existing: a),
                titleOf: (a) => a.name,
                subtitleOf: (a) => a.accountType.name.toUpperCase(),
                trailingOf: (a) =>
                    CurrencyFormatter.format(a.currentBalance),
                iconOf: (a) => a.accountType == AccountType.cash
                    ? Icons.payments_outlined
                    : Icons.account_balance_outlined,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section<CreditCard>(
                title: 'CREDIT CARDS',
                icon: Icons.credit_card,
                addLabel: 'Add credit card',
                data: cards,
                emptyMessage:
                    'Add a card to track its bill and get due-date reminders.',
                onAdd: () => InstrumentFormSheet.creditCard(context),
                onEdit: (c) =>
                    InstrumentFormSheet.creditCard(context, existing: c),
                titleOf: (c) => c.name,
                subtitleOf: (c) => c.lastFour != null && c.lastFour!.isNotEmpty
                    ? '•••• ${c.lastFour}  ·  due ${c.dueDay}'
                    : 'Due day ${c.dueDay}',
                trailingOf: (c) =>
                    '${CurrencyFormatter.format(c.availableLimit)} left',
                iconOf: (_) => Icons.credit_card,
              ),
              const SizedBox(height: AppSpacing.lg),
              _Section<Loan>(
                title: 'LOANS',
                icon: Icons.account_balance_outlined,
                addLabel: 'Add loan',
                data: loans,
                emptyMessage: 'Add a loan to track its EMIs.',
                onAdd: () => InstrumentFormSheet.loan(context),
                onEdit: (l) => InstrumentFormSheet.loan(context, existing: l),
                titleOf: (l) => l.name,
                subtitleOf: (l) =>
                    '${l.interestRate}% p.a.  ·  ${l.tenureMonths}m',
                trailingOf: (l) =>
                    CurrencyFormatter.format(l.outstandingBalance),
                iconOf: (_) => Icons.account_balance_outlined,
              ),
              const SizedBox(height: AppSpacing.lg),
              const HouseholdCard(),
              const SizedBox(height: AppSpacing.xl),
              const _SignOutButton(),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled list of one instrument type, with an add button and an empty state.
class _Section<T> extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.addLabel,
    required this.data,
    required this.emptyMessage,
    required this.onAdd,
    required this.onEdit,
    required this.titleOf,
    required this.subtitleOf,
    required this.trailingOf,
    required this.iconOf,
  });

  final String title;
  final IconData icon;
  final String addLabel;
  final AsyncValue<List<T>> data;
  final String emptyMessage;
  final VoidCallback onAdd;
  final void Function(T) onEdit;
  final String Function(T) titleOf;
  final String Function(T) subtitleOf;
  final String Function(T) trailingOf;
  final IconData Function(T) iconOf;

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Icon(icon, size: 16, color: AppColors.neonGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          data.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
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
            error: (_, _) => Text(
              'Could not load these right now.',
              style: AppTypography.bodySmall
                  .copyWith(color: AppColors.neonPink),
            ),
            data: (items) => items.isEmpty
                ? Text(emptyMessage, style: AppTypography.bodySmall)
                : Column(
                    children: [
                      for (final item in items) _tile(item),
                    ],
                  ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 44,
            child: OutlinedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(addLabel, style: AppTypography.labelMedium),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tile(T item) {
    return InkWell(
      onTap: () => onEdit(item),
      borderRadius: AppRadius.mdAll,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: AppColors.subtleBorder),
              ),
              child: Icon(iconOf(item), size: 16, color: AppColors.textTertiary),
            ),
            const SizedBox(width: AppSpacing.md),
            // Expanded so a long name cannot overflow the row.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titleOf(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitleOf(item),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              trailingOf(item),
              style: AppTypography.amountSmall(color: AppColors.textPrimary),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textDisabled),
          ],
        ),
      ),
    );
  }
}

class _SignOutButton extends ConsumerWidget {
  const _SignOutButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SizedBox(
      height: 50,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.neonPink,
          side: BorderSide(color: AppColors.neonPink.withValues(alpha: 0.4)),
        ),
        onPressed: () async {
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('Sign out?'),
              content: const Text(
                'This signs you out on every device.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Stay signed in'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.neonPink),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          );
          if (confirmed != true) return;
          // GoRouter's redirect reacts to the auth state, so there is no
          // navigation to do here.
          await ref.read(logoutProvider)();
        },
        icon: const Icon(Icons.logout_rounded, size: 18),
        label: Text(
          'SIGN OUT',
          style: AppTypography.labelMedium.copyWith(
            color: AppColors.neonPink,
            letterSpacing: 1.1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ).animate().fadeIn(duration: 300.ms);
  }
}
