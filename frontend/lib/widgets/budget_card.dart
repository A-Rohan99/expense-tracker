/// Monthly budget with a progress bar that changes colour as the cap nears.
///
/// Called for in AGENT_BUILD_SPEC §2.6. The colour is the whole point: a number
/// needs reading, a red bar does not.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/budget.dart';
import '../providers/budget_providers.dart';
import '../utils/currency_formatter.dart';

/// Green while there's room, amber as it tightens, red once it's blown.
Color budgetColor(double percentUsed) {
  if (percentUsed >= 100) return AppColors.neonRed;
  if (percentUsed >= 80) return AppColors.neonAmber;
  return AppColors.neonGreen;
}

class BudgetCard extends ConsumerWidget {
  const BudgetCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final budgets = ref.watch(budgetsProvider);

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
              const Icon(Icons.pie_chart_outline,
                  size: 16, color: AppColors.neonGreen),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MONTHLY BUDGET',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              budgets.maybeWhen(
                data: (list) => list.isEmpty
                    ? const SizedBox.shrink()
                    : TextButton(
                        onPressed: () => BudgetSheet.show(context),
                        child: const Text('Edit'),
                      ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          budgets.when(
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
            error: (_, _) => Text(
              'Could not load your budget.',
              style:
                  AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
            ),
            data: (list) =>
                list.isEmpty ? _buildEmpty(context) : _buildBudgets(list),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Set a monthly cap and watch how much of it you have left.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => BudgetSheet.show(context),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text('Set a budget', style: AppTypography.labelMedium),
          ),
        ),
      ],
    );
  }

  Widget _buildBudgets(List<Budget> budgets) {
    return Column(
      children: [
        for (var i = 0; i < budgets.length; i++) ...[
          if (i > 0) const SizedBox(height: AppSpacing.md),
          _BudgetRow(budget: budgets[i]),
        ],
      ],
    );
  }
}

class _BudgetRow extends StatelessWidget {
  const _BudgetRow({required this.budget});

  final Budget budget;

  @override
  Widget build(BuildContext context) {
    final color = budgetColor(budget.percentUsed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Expanded so a long category name can't overflow the row.
            Expanded(
              child: Text(
                budget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              '${CurrencyFormatter.format(budget.spent)} '
              '/ ${CurrencyFormatter.format(budget.amount)}',
              style: AppTypography.amountSmall(color: color),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        ClipRRect(
          borderRadius: AppRadius.pillAll,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: budget.fraction),
            duration: 650.ms,
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 8,
              backgroundColor: AppColors.obsidian,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          budget.isOverBudget
              ? 'Over by ${CurrencyFormatter.format(budget.spent - budget.amount)}'
              : '${CurrencyFormatter.format(budget.remaining)} left '
                  '· ${budget.percentUsed.toStringAsFixed(0)}% used',
          style: AppTypography.bodySmall.copyWith(
            fontSize: 11,
            color: budget.isOverBudget ? AppColors.neonRed : null,
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Set / edit sheet
// ═══════════════════════════════════════════════════════════════════════════

class BudgetSheet extends ConsumerStatefulWidget {
  const BudgetSheet({super.key});

  static Future<bool?> show(BuildContext context) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BudgetSheet(),
    );
  }

  @override
  ConsumerState<BudgetSheet> createState() => _BudgetSheetState();
}

class _BudgetSheetState extends ConsumerState<BudgetSheet> {
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _amountFocus = FocusNode();

  String? _editingId;
  String? _amountError;
  bool _seeded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _amountFocus.requestFocus());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  double? get _amount => double.tryParse(_amountController.text.trim());

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      return;
    }
    setState(() => _amountError = null);

    final ok = await ref.read(budgetControllerProvider.notifier).save(
          amount: amount,
          existingId: _editingId,
          category: _editingId == null
              ? _categoryController.text.trim()
              : null,
        );
    if (ok && mounted) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete(String id) async {
    final ok = await ref.read(budgetControllerProvider.notifier).remove(id);
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(budgetControllerProvider);
    final budgets =
        ref.watch(budgetsProvider).asData?.value ?? const <Budget>[];

    // Editing the overall budget is the common case, so prefill it.
    if (!_seeded && budgets.isNotEmpty) {
      final overall = budgets.where((b) => b.isOverall).firstOrNull;
      if (overall != null) {
        _editingId = overall.id;
        _amountController.text = overall.amount.toStringAsFixed(0);
      }
      _seeded = true;
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.charcoal,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border(top: BorderSide(color: AppColors.subtleBorder)),
          ),
          child: SingleChildScrollView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
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
                const SizedBox(height: AppSpacing.lg),
                Text(
                  _editingId == null ? 'SET A BUDGET' : 'EDIT BUDGET',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 2.0,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Spending is counted from your transactions, so this stays '
                  'accurate on its own.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),

                _buildAmountField(),
                if (_amountError != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _amountError!,
                    style: AppTypography.bodySmall
                        .copyWith(color: AppColors.neonPink),
                  ),
                ],

                if (_editingId == null) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _categoryController,
                    style: AppTypography.bodyLarge,
                    cursorColor: AppColors.neonGreen,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Category (optional)',
                      hintText: 'Leave blank to cap all spending',
                      prefixIcon: Icon(Icons.local_offer_outlined,
                          color: AppColors.textTertiary, size: 18),
                    ),
                  ),
                ],

                if (state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  _ErrorBanner(message: state.errorMessage!),
                ],

                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonGreen,
                      foregroundColor: AppColors.trueBlack,
                      shape:
                          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                    ),
                    onPressed: state.isLoading ? null : _save,
                    child: state.isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppColors.trueBlack,
                            ),
                          )
                        : Text(
                            _editingId == null ? 'SET BUDGET' : 'SAVE',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.trueBlack,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),

                if (budgets.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    'YOUR BUDGETS',
                    style: AppTypography.labelSmall.copyWith(
                      color: AppColors.textTertiary,
                      letterSpacing: 1.4,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final budget in budgets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${budget.label} · '
                              '${CurrencyFormatter.format(budget.amount)}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTypography.bodyMedium,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: AppColors.neonPink,
                            tooltip: 'Remove ${budget.label} budget',
                            onPressed: state.isLoading
                                ? null
                                : () => _delete(budget.id),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.neonGreen.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Text('₹', style: AppTypography.amountLarge(color: AppColors.neonGreen)),
          const SizedBox(width: 6),
          Expanded(
            child: TextField(
              controller: _amountController,
              focusNode: _amountFocus,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              style: AppTypography.amountLarge(color: AppColors.textPrimary),
              cursorColor: AppColors.neonGreen,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: '0',
                hintStyle:
                    AppTypography.amountLarge(color: AppColors.textDisabled),
              ),
              onChanged: (_) {
                if (_amountError != null) setState(() => _amountError = null);
                ref.read(budgetControllerProvider.notifier).clearError();
              },
              onSubmitted: (_) => _save(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.neonPink.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.neonPink.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.neonPink, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style:
                  AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}
