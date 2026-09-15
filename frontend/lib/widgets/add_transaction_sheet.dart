/// Bottom sheet for recording an income or expense — the app's capture path.
///
/// Type drives everything else: an expense can be paid from an account or a
/// credit card, income can only land in an account (the backend enforces the
/// same rule), so the source list re-filters when the type flips.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../models/transaction.dart';
import '../providers/transaction_providers.dart';
import '../utils/currency_formatter.dart';

class AddTransactionSheet extends ConsumerStatefulWidget {
  const AddTransactionSheet({
    super.key,
    required this.accounts,
    required this.cards,
  });

  final List<Account> accounts;
  final List<CreditCard> cards;

  static Future<bool?> show(
    BuildContext context, {
    required List<Account> accounts,
    required List<CreditCard> cards,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddTransactionSheet(accounts: accounts, cards: cards),
    );
  }

  @override
  ConsumerState<AddTransactionSheet> createState() =>
      _AddTransactionSheetState();
}

class _AddTransactionSheetState extends ConsumerState<AddTransactionSheet> {
  final _amountController = TextEditingController();
  final _categoryController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _amountFocus = FocusNode();

  TransactionType _type = TransactionType.expense;
  SourceKind _sourceKind = SourceKind.account;
  String? _sourceId;
  DateTime _date = DateTime.now();
  bool _isHouseholdShared = false;
  bool _isSuccess = false;
  String? _amountError;

  bool get _isExpense => _type == TransactionType.expense;

  @override
  void initState() {
    super.initState();
    _sourceId = widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
    // The amount is the one field every entry needs — start there.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _amountFocus.requestFocus());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _categoryController.dispose();
    _descriptionController.dispose();
    _amountFocus.dispose();
    super.dispose();
  }

  void _setType(TransactionType type) {
    if (type == _type) return;
    setState(() {
      _type = type;
      _categoryController.clear();
      // Income can't land on a credit card — fall back to the first account.
      if (type == TransactionType.income &&
          _sourceKind == SourceKind.creditCard) {
        _sourceKind = SourceKind.account;
        _sourceId =
            widget.accounts.isNotEmpty ? widget.accounts.first.id : null;
      }
    });
    ref.read(transactionControllerProvider.notifier).clearError();
  }

  double? get _amount => double.tryParse(_amountController.text.trim());

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();

    final amount = _amount;
    if (amount == null || amount <= 0) {
      setState(() => _amountError = 'Enter an amount greater than zero');
      return;
    }
    if (_sourceId == null) {
      setState(() => _amountError = null);
      return;
    }
    setState(() => _amountError = null);

    final category = _categoryController.text.trim().isEmpty
        ? (_isExpense ? 'Uncategorised' : 'Income')
        : _categoryController.text.trim();

    final ok = await ref
        .read(transactionControllerProvider.notifier)
        .createTransaction(
          type: _type,
          amount: amount,
          category: category,
          sourceKind: _sourceKind,
          sourceId: _sourceId!,
          description: _descriptionController.text,
          date: _date,
          isHouseholdShared: _isHouseholdShared,
        );

    if (!ok || !mounted) return;

    HapticFeedback.mediumImpact();
    setState(() => _isSuccess = true);
    await Future.delayed(const Duration(milliseconds: 1100));
    if (mounted) Navigator.of(context).pop(true);
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
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
    final formState = ref.watch(transactionControllerProvider);
    final accent = _isExpense ? AppColors.neonPink : AppColors.neonGreen;

    const decoration = BoxDecoration(
      color: AppColors.charcoal,
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      border: Border(top: BorderSide(color: AppColors.subtleBorder)),
    );

    // The success state is short and fixed — no need to make it scrollable.
    if (_isSuccess) {
      return Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: DecoratedBox(
          decoration: decoration,
          child: _buildSuccess(accent),
        ),
      );
    }

    // The form is taller than a phone screen, so it needs a scroll view driven
    // by the sheet's own controller — a bare SingleChildScrollView inside a
    // height-constrained box gets no scroll extent and strands the submit
    // button off-screen.
    return Padding(
      // Lift the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.88,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DecoratedBox(
          decoration: decoration,
          child: _buildForm(formState, accent, scrollController),
        ),
      ),
    );
  }

  // ── Form ─────────────────────────────────────────────────────────────────

  Widget _buildForm(
    TransactionFormState formState,
    Color accent,
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
            'RECORD TRANSACTION',
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 2.0,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          _TypeSwitch(type: _type, onChanged: _setType),
          const SizedBox(height: AppSpacing.lg),

          _buildAmountField(accent),
          if (_amountError != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              _amountError!,
              style: AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('CATEGORY'),
          const SizedBox(height: AppSpacing.sm),
          _buildCategoryChips(accent),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _categoryController,
            style: AppTypography.bodyLarge,
            cursorColor: accent,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Or type your own',
              prefixIcon: Icon(Icons.local_offer_outlined,
                  color: AppColors.textTertiary, size: 18),
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel(_isExpense ? 'PAID FROM' : 'RECEIVED INTO'),
          const SizedBox(height: AppSpacing.sm),
          _buildSourceList(accent),
          const SizedBox(height: AppSpacing.lg),

          _sectionLabel('DETAILS'),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _descriptionController,
            style: AppTypography.bodyLarge,
            cursorColor: accent,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Note (optional)',
              prefixIcon: Icon(Icons.notes_rounded,
                  color: AppColors.textTertiary, size: 18),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _buildDateRow(),
          const SizedBox(height: AppSpacing.sm),
          _buildHouseholdToggle(),

          if (formState.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.md),
            _ErrorBanner(message: formState.errorMessage!),
          ],

          const SizedBox(height: AppSpacing.lg),
          _buildSubmit(formState.isLoading, accent),
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

  Widget _buildAmountField(Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            _isExpense ? '−' : '+',
            style: AppTypography.amountLarge(color: accent),
          ),
          const SizedBox(width: 4),
          Text('₹', style: AppTypography.amountLarge(color: accent)),
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
              cursorColor: accent,
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
                ref.read(transactionControllerProvider.notifier).clearError();
              },
              onSubmitted: (_) => _submit(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(Color accent) {
    final categories = _isExpense ? kExpenseCategories : kIncomeCategories;
    final selected = _categoryController.text.trim();

    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: categories.map((c) {
        final isSelected = selected.toLowerCase() == c.toLowerCase();
        return Semantics(
          button: true,
          selected: isSelected,
          label: '$c category',
          child: GestureDetector(
          onTap: () {
            setState(() {
              _categoryController.text = isSelected ? '' : c;
            });
          },
          child: AnimatedContainer(
            duration: 180.ms,
            // 44dp minimum so the chip is a reachable tap target.
            constraints: const BoxConstraints(minHeight: 44),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
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
            // stretches to that width, so every chip filled the row and the
            // Wrap never wrapped. A min-width Row shrinks to the label while
            // still centring it in the 44dp target.
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

  Widget _buildSourceList(Color accent) {
    final tiles = <Widget>[
      for (final a in widget.accounts)
        _sourceTile(
          id: a.id,
          kind: SourceKind.account,
          title: a.name,
          subtitle: 'Balance: ${CurrencyFormatter.format(a.currentBalance)}',
          icon: a.accountType == AccountType.cash
              ? Icons.payments_outlined
              : Icons.account_balance_outlined,
          accent: accent,
        ),
      // A credit card is a way to pay, never a place income lands.
      if (_isExpense)
        for (final c in widget.cards)
          _sourceTile(
            id: c.id,
            kind: SourceKind.creditCard,
            title: c.name,
            subtitle: c.lastFour != null && c.lastFour!.isNotEmpty
                ? '•••• ${c.lastFour}'
                : 'Credit card',
            icon: Icons.credit_card,
            accent: accent,
          ),
    ];

    if (tiles.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.obsidian,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.subtleBorder),
        ),
        child: Text(
          'No accounts yet — add one before recording transactions.',
          style: AppTypography.bodySmall,
        ),
      );
    }

    return Column(children: tiles);
  }

  Widget _sourceTile({
    required String id,
    required SourceKind kind,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    final isSelected = _sourceId == id && _sourceKind == kind;
    return GestureDetector(
      onTap: () => setState(() {
        _sourceId = id;
        _sourceKind = kind;
      }),
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: 180.ms,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: isSelected
              ? accent.withValues(alpha: 0.08)
              : AppColors.obsidian,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: isSelected
                ? accent.withValues(alpha: 0.55)
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
              color: isSelected ? accent : AppColors.textDisabled,
            ),
            const SizedBox(width: AppSpacing.md),
            Icon(icon, size: 18, color: AppColors.textTertiary),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(subtitle, style: AppTypography.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRow() {
    final now = DateTime.now();
    final isToday = _date.year == now.year &&
        _date.month == now.month &&
        _date.day == now.day;

    return GestureDetector(
      onTap: _pickDate,
      behavior: HitTestBehavior.opaque,
      child: Container(
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
              isToday
                  ? 'Today'
                  : '${_date.day}/${_date.month}/${_date.year}',
              style: AppTypography.bodyMedium
                  .copyWith(color: AppColors.textPrimary),
            ),
            const Spacer(),
            const Icon(Icons.chevron_right,
                size: 18, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _buildHouseholdToggle() {
    return GestureDetector(
      onTap: () => setState(() => _isHouseholdShared = !_isHouseholdShared),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.obsidian,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: _isHouseholdShared
                ? AppColors.neonCyan.withValues(alpha: 0.45)
                : AppColors.subtleBorder,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.people_outline,
              size: 18,
              color: _isHouseholdShared
                  ? AppColors.neonCyan
                  : AppColors.textTertiary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'Share with household',
                style: AppTypography.bodyMedium
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
            Switch(
              value: _isHouseholdShared,
              activeThumbColor: AppColors.trueBlack,
              activeTrackColor: AppColors.neonCyan,
              inactiveThumbColor: AppColors.textTertiary,
              inactiveTrackColor: AppColors.elevatedSurface,
              onChanged: (v) => setState(() => _isHouseholdShared = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmit(bool isLoading, Color accent) {
    final canSubmit = !isLoading && _sourceId != null;
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: AppColors.trueBlack,
          disabledBackgroundColor: AppColors.elevatedSurface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        onPressed: canSubmit ? _submit : null,
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
                _isExpense ? 'RECORD EXPENSE' : 'RECORD INCOME',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.trueBlack,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  // ── Success ──────────────────────────────────────────────────────────────

  Widget _buildSuccess(Color accent) {
    final amount = _amount ?? 0;
    return SizedBox(
      height: 280,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: accent.withValues(alpha: 0.3),
                  blurRadius: 28,
                ),
              ],
            ),
            child: const Icon(Icons.check_rounded,
                size: 34, color: AppColors.trueBlack),
          )
              .animate()
              .scale(duration: 420.ms, curve: Curves.elasticOut)
              .fadeIn(duration: 180.ms),
          const SizedBox(height: AppSpacing.lg),
          Text(
            _isExpense ? 'EXPENSE RECORDED' : 'INCOME RECORDED',
            style: AppTypography.labelLarge.copyWith(
              color: accent,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            CurrencyFormatter.format(_isExpense ? -amount : amount,
                showSign: true),
            style: AppTypography.amountLarge(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Expense / Income switch
// ═══════════════════════════════════════════════════════════════════════════

class _TypeSwitch extends StatelessWidget {
  const _TypeSwitch({required this.type, required this.onChanged});

  final TransactionType type;
  final ValueChanged<TransactionType> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        children: [
          _segment('Expense', TransactionType.expense, AppColors.neonPink),
          _segment('Income', TransactionType.income, AppColors.neonGreen),
        ],
      ),
    );
  }

  Widget _segment(String label, TransactionType value, Color accent) {
    final isSelected = type == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => onChanged(value),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: 200.ms,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? accent : AppColors.textTertiary,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Error banner
// ═══════════════════════════════════════════════════════════════════════════

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
