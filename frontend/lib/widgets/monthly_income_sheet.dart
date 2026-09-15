/// Bottom sheet for setting up (or editing) the standing monthly income.
///
/// Asks three things: how much, which day of the month, and where it lands.
/// From then on the server posts it automatically each month.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/recurring_income.dart';
import '../providers/recurring_income_providers.dart';
import '../utils/currency_formatter.dart';

class MonthlyIncomeSheet extends ConsumerStatefulWidget {
  const MonthlyIncomeSheet({
    super.key,
    required this.accounts,
    this.existing,
  });

  final List<Account> accounts;
  final RecurringIncome? existing;

  static Future<bool?> show(
    BuildContext context, {
    required List<Account> accounts,
    RecurringIncome? existing,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MonthlyIncomeSheet(
        accounts: accounts,
        existing: existing,
      ),
    );
  }

  @override
  ConsumerState<MonthlyIncomeSheet> createState() => _MonthlyIncomeSheetState();
}

class _MonthlyIncomeSheetState extends ConsumerState<MonthlyIncomeSheet> {
  late final TextEditingController _amountController;
  late final TextEditingController _nameController;
  final _amountFocus = FocusNode();

  late int _dayOfMonth;
  String? _accountId;
  String? _amountError;
  bool _isSuccess = false;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _amountController = TextEditingController(
      text: existing != null ? existing.amount.toStringAsFixed(0) : '',
    );
    _nameController = TextEditingController(
      text: existing?.name ?? 'Monthly income',
    );
    _dayOfMonth = existing?.dayOfMonth ?? 1;
    _accountId = existing?.accountId ??
        (widget.accounts.isNotEmpty ? widget.accounts.first.id : null);

    if (!_isEditing) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _amountFocus.requestFocus());
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _nameController.dispose();
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
    if (_accountId == null) return;
    setState(() => _amountError = null);

    final ok = await ref
        .read(recurringIncomeControllerProvider.notifier)
        .save(
          existingId: widget.existing?.id,
          amount: amount,
          dayOfMonth: _dayOfMonth,
          accountId: _accountId!,
          name: _nameController.text.trim().isEmpty
              ? 'Monthly income'
              : _nameController.text.trim(),
        );

    if (!ok || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSuccess = true);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop monthly income?'),
        content: const Text(
          'Future months will no longer be added automatically. '
          'Income already recorded stays in your ledger.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
            child: const Text('Stop'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok =
        await ref.read(recurringIncomeControllerProvider.notifier).remove();
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(recurringIncomeControllerProvider);

    const decoration = BoxDecoration(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      border: Border(top: BorderSide(color: AppColors.subtleBorder)),
    );

    if (_isSuccess) {
      return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DecoratedBox(decoration: decoration, child: _buildSuccess()),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DecoratedBox(
          decoration: decoration,
          child: _buildForm(formState, scrollController),
        ),
      ),
    );
  }

  Widget _buildForm(
    RecurringIncomeFormState formState,
    ScrollController scrollController,
  ) {
    return SingleChildScrollView(
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
            _isEditing ? 'EDIT MONTHLY INCOME' : 'SET UP MONTHLY INCOME',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 2.0,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Added to your balance automatically, every month.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('HOW MUCH'),
          const SizedBox(height: AppSpacing.sm),
          _buildAmountField(),
          if (_amountError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _amountError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('WHICH DAY OF THE MONTH'),
          const SizedBox(height: AppSpacing.sm),
          _buildDayPicker(),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('PAID INTO'),
          const SizedBox(height: AppSpacing.sm),
          _buildAccountList(),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('LABEL'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _nameController,
            style: AppTypography.bodyLarge,
            cursorColor: AppColors.neonGreen,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'e.g. Salary',
              prefixIcon: Icon(Icons.badge_outlined,
                  color: AppColors.textTertiary, size: 18),
            ),
          ),

          if (formState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: formState.errorMessage!),
          ],

          const SizedBox(height: AppSpacing.lg),
          _buildSubmit(formState.isLoading),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: formState.isLoading ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
              child: const Text('Stop monthly income'),
            ),
          ],
        ],
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
          Text('+', style: AppTypography.amountLarge(color: AppColors.neonGreen)),
          const SizedBox(width: 4),
          Text('₹', style: AppTypography.amountLarge(color: AppColors.neonGreen)),
          const SizedBox(width: 4),
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
                ref.read(recurringIncomeControllerProvider.notifier)
                    .clearError();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.obsidian,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.subtleBorder),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_repeat_outlined,
                  size: 18, color: AppColors.neonGreen),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  'Every month on the ${_ordinal(_dayOfMonth)}',
                  style: AppTypography.bodyMedium
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        // 1–31 as a wrap: one tap, no scroll wheel to fight.
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(31, (i) => i + 1).map((day) {
            final isSelected = day == _dayOfMonth;
            return Semantics(
              button: true,
              selected: isSelected,
              label: 'Day $day of the month',
              // The bare number would otherwise merge into the label.
              // excludeSemantics also drops the tap action, so declare it.
              excludeSemantics: true,
              onTap: () => setState(() => _dayOfMonth = day),
              child: GestureDetector(
              onTap: () => setState(() => _dayOfMonth = day),
              child: AnimatedContainer(
                duration: 150.ms,
                // 44dp square: the cells were 38x34, under the accessible
                // minimum and fiddly on a phone.
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected
                      ? AppColors.neonGreen.withValues(alpha: 0.16)
                      : AppColors.obsidian,
                  borderRadius: AppRadius.smAll,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.neonGreen.withValues(alpha: 0.6)
                        : AppColors.subtleBorder,
                  ),
                ),
                child: Text(
                  '$day',
                  style: AppTypography.labelMedium.copyWith(
                    color: isSelected
                        ? AppColors.neonGreen
                        : AppColors.textSecondary,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
              ),
            );
          }).toList(),
        ),
        if (_dayOfMonth > 28) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline,
                  size: 14, color: AppColors.neonAmber),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Shorter months pay on their last day instead.',
                  style: AppTypography.bodySmall
                      .copyWith(color: AppColors.neonAmber),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildAccountList() {
    if (widget.accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.obsidian,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Text(
          'No accounts yet — you need one for the income to land in.',
          style: AppTypography.bodySmall,
        ),
      );
    }

    return Column(
      children: widget.accounts.map((a) {
        final isSelected = _accountId == a.id;
        return GestureDetector(
          onTap: () => setState(() => _accountId = a.id),
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: 180.ms,
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.neonGreen.withValues(alpha: 0.08)
                  : AppColors.obsidian,
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: isSelected
                    ? AppColors.neonGreen.withValues(alpha: 0.55)
                    : AppColors.subtleBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                  color:
                      isSelected ? AppColors.neonGreen : AppColors.textDisabled,
                ),
                const SizedBox(width: AppSpacing.md),
                Icon(
                  a.accountType == AccountType.cash
                      ? Icons.payments_outlined
                      : Icons.account_balance_outlined,
                  size: 18,
                  color: AppColors.textTertiary,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        a.name,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Balance: ${CurrencyFormatter.format(a.currentBalance)}',
                        style: AppTypography.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubmit(bool isLoading) {
    final canSubmit = !isLoading && _accountId != null;
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: AppColors.trueBlack,
          disabledBackgroundColor: AppColors.elevatedSurface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        onPressed: canSubmit ? _save : null,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.trueBlack,
                ),
              )
            : Text(
                _isEditing ? 'SAVE CHANGES' : 'SET UP INCOME',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.trueBlack,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _buildSuccess() {
    return SizedBox(
      height: 290,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.neonGreen,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: AppColors.neonGreen.withValues(alpha: 0.3),
                  blurRadius: 28,
                ),
              ],
            ),
            child: const Icon(Icons.event_repeat_rounded,
                size: 32, color: AppColors.trueBlack),
          )
              .animate()
              .scale(duration: 420.ms, curve: Curves.elasticOut)
              .fadeIn(duration: 180.ms),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'MONTHLY INCOME SET',
            style: AppTypography.labelLarge.copyWith(
              color: AppColors.neonGreen,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            CurrencyFormatter.format(_amount ?? 0),
            style: AppTypography.amountLarge(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'every month on the ${_ordinal(_dayOfMonth)}',
            style: AppTypography.bodySmall,
          ),
        ],
      ),
    );
  }
}

String _ordinal(int d) {
  if (d >= 11 && d <= 13) return '${d}th';
  switch (d % 10) {
    case 1:
      return '${d}st';
    case 2:
      return '${d}nd';
    case 3:
      return '${d}rd';
    default:
      return '${d}th';
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
