/// Full transaction history with search, filters and sorting.
///
/// The dashboard shows only the ten most recent entries, so until now an older
/// transaction could not be found, corrected or removed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../providers/transaction_list_providers.dart';
import '../utils/currency_formatter.dart';
import '../widgets/transaction_edit_sheet.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _searchController = TextEditingController();

  /// Search ran on submit only, so typing appeared to do nothing until the
  /// user found the keyboard's search key. Debounced instead — long enough
  /// that a normal typing burst is one request, not one per keystroke.
  static const _searchDebounce = Duration(milliseconds: 350);
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    _searchController.text =
        ref.read(transactionFilterProvider).search ?? '';
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  /// Apply straight away, cancelling any pending debounce.
  void _applySearch(String? value) {
    _searchTimer?.cancel();
    ref.read(transactionFilterProvider.notifier).setSearch(value);
  }

  void _onSearchChanged(String value) {
    // Repaints the clear button, which keys off the controller's text.
    setState(() {});
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () {
      if (!mounted) return;
      ref.read(transactionFilterProvider.notifier).setSearch(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(transactionFilterProvider);
    final transactions = ref.watch(filteredTransactionsProvider);

    return Scaffold(
      backgroundColor: AppColors.trueBlack,
      appBar: AppBar(
        backgroundColor: AppColors.trueBlack,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          tooltip: 'Back to dashboard',
          onPressed: () => context.go('/home'),
        ),
        title: Text('Transactions', style: AppTypography.headlineMedium),
        actions: [
          if (filter.isFiltered)
            TextButton(
              onPressed: () {
                // Without the cancel, a debounce still in flight would put
                // the search term straight back after the reset.
                _searchTimer?.cancel();
                _searchController.clear();
                ref.read(transactionFilterProvider.notifier).clear();
              },
              child: const Text('Clear'),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildSearchField(),
            _buildFilterChips(filter),
            const Divider(height: 1),
            Expanded(
              child: transactions.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: AppColors.neonGreen),
                ),
                error: (error, _) => _buildError(),
                data: (rows) =>
                    rows.isEmpty ? _buildEmpty(filter) : _buildList(rows),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: _searchController,
        style: AppTypography.bodyLarge,
        cursorColor: AppColors.neonGreen,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Search notes and categories',
          prefixIcon: const Icon(Icons.search,
              color: AppColors.textTertiary, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() {});
                    _applySearch(null);
                  },
                ),
        ),
        onSubmitted: _applySearch,
        onChanged: _onSearchChanged,
      ),
    );
  }

  Widget _buildFilterChips(TransactionFilter filter) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        children: [
          _FilterChip(
            label: 'All',
            isSelected: filter.type == null,
            onTap: () =>
                ref.read(transactionFilterProvider.notifier).setType(null),
          ),
          for (final type in TransactionType.values)
            _FilterChip(
              label: switch (type) {
                TransactionType.income => 'Income',
                TransactionType.expense => 'Expenses',
                TransactionType.transfer => 'Transfers',
              },
              isSelected: filter.type == type,
              onTap: () =>
                  ref.read(transactionFilterProvider.notifier).setType(type),
            ),
          const SizedBox(width: AppSpacing.sm),
          _SortChip(current: filter.sort),
        ],
      ),
    );
  }

  Widget _buildList(List<TransactionModel> rows) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      itemCount: rows.length,
      separatorBuilder: (_, _) =>
          const Divider(color: AppColors.subtleBorder, height: 20),
      itemBuilder: (context, index) => _TransactionRow(
        // Keyed by id so row state follows the transaction, not the position.
        key: ValueKey(rows[index].id),
        transaction: rows[index],
      ),
    );
  }

  Widget _buildEmpty(TransactionFilter filter) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.receipt_long_outlined,
                size: 40, color: AppColors.textDisabled),
            const SizedBox(height: AppSpacing.md),
            Text(
              filter.isFiltered
                  ? 'Nothing matches those filters.'
                  : 'No transactions yet.',
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Could not load your transactions.',
              style: AppTypography.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () =>
                  ref.invalidate(filteredTransactionsProvider),
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.sm),
      child: Semantics(
        button: true,
        selected: isSelected,
        label: '$label filter',
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.pillAll,
          child: Container(
            // 44 tall keeps the tap target at the accessible minimum.
            constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.neonGreen.withValues(alpha: 0.14)
                  : AppColors.charcoal,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: isSelected
                    ? AppColors.neonGreen.withValues(alpha: 0.55)
                    : AppColors.subtleBorder,
              ),
            ),
            child: Text(
              label,
              style: AppTypography.labelMedium.copyWith(
                color:
                    isSelected ? AppColors.neonGreen : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SortChip extends ConsumerWidget {
  const _SortChip({required this.current});

  final TransactionSort current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<TransactionSort>(
      tooltip: 'Change sort order',
      color: AppColors.charcoal,
      initialValue: current,
      onSelected: (value) =>
          ref.read(transactionFilterProvider.notifier).setSort(value),
      itemBuilder: (context) => [
        for (final option in TransactionSort.values)
          PopupMenuItem(
            value: option,
            child: Text(option.label, style: AppTypography.bodyMedium),
          ),
      ],
      child: Container(
        constraints: const BoxConstraints(minHeight: 44, minWidth: 44),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.charcoal,
          borderRadius: AppRadius.pillAll,
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.swap_vert, size: 16,
                color: AppColors.textTertiary),
            const SizedBox(width: 6),
            Text(current.label, style: AppTypography.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({super.key, required this.transaction});

  final TransactionModel transaction;

  @override
  Widget build(BuildContext context) {
    final isIncome = transaction.transactionType == TransactionType.income;
    final isTransfer = transaction.transactionType == TransactionType.transfer;
    final accent = isIncome
        ? AppColors.neonGreen
        : (isTransfer ? AppColors.neonCyan : AppColors.neonPink);

    final amount = CurrencyFormatter.format(
      isTransfer || isIncome ? transaction.amount : -transaction.amount,
      showSign: !isTransfer,
    );

    return Semantics(
      button: true,
      label: '${transaction.category}, $amount. Tap to edit.',
      child: InkWell(
        onTap: () =>
            TransactionEditSheet.show(context, transaction: transaction),
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.obsidian,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: accent.withValues(alpha: 0.2)),
                ),
                child: Icon(
                  isIncome
                      ? Icons.arrow_downward_rounded
                      : (isTransfer
                          ? Icons.swap_horiz_rounded
                          : Icons.arrow_upward_rounded),
                  size: 16,
                  color: accent,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              // Expanded so a long category or note cannot overflow the row.
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            transaction.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTypography.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        if (transaction.isHouseholdShared) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color:
                                  AppColors.neonCyan.withValues(alpha: 0.1),
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
                      _subtitle(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              ExcludeSemantics(
                child: Text(
                  amount,
                  style: AppTypography.amountSmall(color: accent).copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle() {
    final date = transaction.transactionDate;
    final stamp = '${date.day}/${date.month}/${date.year}';
    final note = transaction.description;
    return note == null || note.isEmpty ? stamp : '$note · $stamp';
  }
}
