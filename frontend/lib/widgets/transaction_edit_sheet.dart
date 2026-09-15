/// Edit or delete a recorded transaction.
///
/// Amount and the instrument it moved through are immutable — the server
/// follows double-entry convention and will not rewrite history. To correct an
/// amount you delete the entry (which reverses its effect on balances) and
/// record it again. The sheet says so rather than leaving the user guessing
/// why the amount is greyed out.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/transaction.dart';
import '../providers/transaction_list_providers.dart';
import '../providers/transaction_providers.dart';
import '../utils/currency_formatter.dart';

class TransactionEditSheet extends ConsumerStatefulWidget {
  const TransactionEditSheet({super.key, required this.transaction});

  final TransactionModel transaction;

  static Future<bool?> show(
    BuildContext context, {
    required TransactionModel transaction,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => TransactionEditSheet(transaction: transaction),
    );
  }

  @override
  ConsumerState<TransactionEditSheet> createState() =>
      _TransactionEditSheetState();
}

class _TransactionEditSheetState extends ConsumerState<TransactionEditSheet> {
  late final TextEditingController _categoryController =
      TextEditingController(text: widget.transaction.category);
  late final TextEditingController _descriptionController =
      TextEditingController(text: widget.transaction.description ?? '');

  late DateTime _date = widget.transaction.transactionDate;
  late bool _isShared = widget.transaction.isHouseholdShared;
  bool _deleted = false;

  @override
  void dispose() {
    _categoryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final category = _categoryController.text.trim();
    if (category.isEmpty) return;

    final ok = await ref
        .read(transactionEditControllerProvider.notifier)
        .update(
          id: widget.transaction.id,
          category: category,
          description: _descriptionController.text.trim(),
          date: _date,
          isHouseholdShared: _isShared,
        );
    if (ok && mounted) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this transaction?'),
        content: Text(
          'The balance it moved will be put back. '
          '${CurrencyFormatter.format(widget.transaction.amount)} '
          '${widget.transaction.transactionType == TransactionType.income ? "will be removed from" : "will be returned to"} '
          'your balance.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await ref
        .read(transactionEditControllerProvider.notifier)
        .remove(widget.transaction.id);
    if (ok && mounted) {
      setState(() => _deleted = true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (mounted) Navigator.of(context).pop(true);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now(),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: AppColors.neonGreen,
            onPrimary: AppColors.trueBlack,
            surface: AppColors.charcoal,
            onSurface: AppColors.textPrimary,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(transactionEditControllerProvider);
    final txn = widget.transaction;
    final isIncome = txn.transactionType == TransactionType.income;
    final isTransfer = txn.transactionType == TransactionType.transfer;
    final accent = isIncome
        ? AppColors.neonGreen
        : (isTransfer ? AppColors.neonCyan : AppColors.neonPink);

    const decoration = BoxDecoration(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      border: Border(top: BorderSide(color: AppColors.subtleBorder)),
    );

    if (_deleted) {
      return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DecoratedBox(
          decoration: decoration,
          child: SizedBox(
            height: 220,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.check_circle_outline,
                        size: 48, color: AppColors.neonGreen)
                    .animate()
                    .scale(duration: 380.ms, curve: Curves.elasticOut),
                const SizedBox(height: AppSpacing.md),
                Text('DELETED', style: AppTypography.labelLarge),
                const SizedBox(height: AppSpacing.xs),
                Text('Your balance has been put back',
                    style: AppTypography.bodySmall),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.8,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DecoratedBox(
          decoration: decoration,
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
                  'EDIT TRANSACTION',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 2.0,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                // The amount is shown, not edited.
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.obsidian,
                    borderRadius: AppRadius.lgAll,
                    border:
                        Border.all(color: accent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              CurrencyFormatter.format(
                                isTransfer || isIncome
                                    ? txn.amount
                                    : -txn.amount,
                                showSign: !isTransfer,
                              ),
                              style: AppTypography.amountLarge(color: accent),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Amount cannot be changed — delete and record it '
                              'again to correct it.',
                              style: AppTypography.bodySmall
                                  .copyWith(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                _sectionLabel('CATEGORY'),
                const SizedBox(height: AppSpacing.sm),
                _buildCategoryChips(isIncome, accent),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _categoryController,
                  style: AppTypography.bodyLarge,
                  cursorColor: accent,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.local_offer_outlined,
                        color: AppColors.textTertiary, size: 18),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: AppSpacing.md),

                TextField(
                  controller: _descriptionController,
                  style: AppTypography.bodyLarge,
                  cursorColor: accent,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Note',
                    hintText: 'Optional',
                    prefixIcon: Icon(Icons.notes_rounded,
                        color: AppColors.textTertiary, size: 18),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),

                _buildDateRow(),
                const SizedBox(height: AppSpacing.sm),
                _buildSharedToggle(),

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
                            'SAVE CHANGES',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.trueBlack,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  onPressed: state.isLoading ? null : _delete,
                  style:
                      TextButton.styleFrom(foregroundColor: AppColors.neonPink),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete transaction'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Text(
        text,
        style: AppTypography.labelSmall.copyWith(
          color: AppColors.textTertiary,
          letterSpacing: 1.4,
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      );

  Widget _buildCategoryChips(bool isIncome, Color accent) {
    final categories = isIncome ? kIncomeCategories : kExpenseCategories;
    final selected = _categoryController.text.trim().toLowerCase();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: categories.map((c) {
        final isSelected = selected == c.toLowerCase();
        return Semantics(
          button: true,
          selected: isSelected,
          child: GestureDetector(
            onTap: () => setState(() => _categoryController.text = c),
            child: AnimatedContainer(
              duration: 180.ms,
              constraints: const BoxConstraints(minHeight: 44),
              padding:
                  const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: 0.14)
                    : AppColors.obsidian,
                borderRadius: AppRadius.pillAll,
                border: Border.all(
                  color: isSelected
                      ? accent.withValues(alpha: 0.55)
                      : AppColors.subtleBorder,
                ),
              ),
              // A Container with `alignment` set and a bounded maxWidth
              // stretches to that width, so every chip filled the row and
              // the Wrap never wrapped. A min-width Row shrinks to the
              // label while still centring it in the 44dp target.
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    c,
                    style: AppTypography.labelMedium.copyWith(
                      color: isSelected ? accent : AppColors.textSecondary,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDateRow() {
    return Semantics(
      button: true,
      label: 'Change date, currently ${_date.day}/${_date.month}/${_date.year}',
      child: GestureDetector(
        onTap: _pickDate,
        behavior: HitTestBehavior.opaque,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.subtleBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.calendar_today_outlined,
                  size: 18, color: AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Text(
                '${_date.day}/${_date.month}/${_date.year}',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
              const Spacer(),
              const Icon(Icons.chevron_right,
                  size: 18, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSharedToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.mdAll,
        border: Border.all(
          color: _isShared
              ? AppColors.neonCyan.withValues(alpha: 0.45)
              : AppColors.subtleBorder,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.people_outline,
              size: 18,
              color:
                  _isShared ? AppColors.neonCyan : AppColors.textTertiary),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'Shared with household',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
          Switch(
            value: _isShared,
            activeThumbColor: AppColors.trueBlack,
            activeTrackColor: AppColors.neonCyan,
            inactiveThumbColor: AppColors.textTertiary,
            inactiveTrackColor: AppColors.elevatedSurface,
            onChanged: (v) => setState(() => _isShared = v),
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
