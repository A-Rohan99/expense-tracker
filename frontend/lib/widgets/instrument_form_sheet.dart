/// Create / edit sheet for accounts, credit cards and loans.
///
/// One sheet rather than three: the three forms differ only in their fields, so
/// a shared shell keeps the validation, error handling, delete confirmation and
/// scrolling behaviour identical everywhere.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../models/account.dart';
import '../models/credit_card.dart';
import '../models/loan.dart';
import '../providers/manage_providers.dart';

/// One editable field in the sheet.
///
/// Public because it appears in the sheet's constructor signature; the
/// constructor itself is private, so these are only built by the named
/// factories below.
class FormFieldSpec {
  FormFieldSpec({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.initial = '',
    this.numeric = false,
    this.integer = false,
    this.digitsOnly = false,
    this.required = true,
    this.helper,
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final String initial;
  /// Send as a JSON number, and only accept digits.
  final bool integer;

  /// Only accept digits, but send as a string. `last_four` is digits-only and
  /// typed `str` server-side — sending it as a number is rejected.
  final bool digitsOnly;

  final bool numeric;
  final bool required;
  final String? helper;

  late final TextEditingController controller =
      TextEditingController(text: initial);
}

/// A fixed set of options rendered as chips (account type, loan type).
class FormChoiceSpec {
  FormChoiceSpec({
    required this.key,
    required this.label,
    required this.options,
    required this.initial,
  });

  final String key;
  final String label;
  final Map<String, String> options; // value -> display label
  final String initial;
}

class InstrumentFormSheet extends ConsumerStatefulWidget {
  const InstrumentFormSheet._({
    required this.kind,
    required this.title,
    required this.fields,
    required this.choices,
    this.existingId,
    this.note,
  });

  final InstrumentKind kind;
  final String title;
  final List<FormFieldSpec> fields;
  final List<FormChoiceSpec> choices;
  final String? existingId;
  final String? note;

  // ── Account ──────────────────────────────────────────────────────────────

  static Future<bool?> account(BuildContext context, {Account? existing}) {
    return _show(
      context,
      InstrumentFormSheet._(
        kind: InstrumentKind.account,
        title: existing == null ? 'Add account' : 'Edit account',
        existingId: existing?.id,
        note: existing != null
            // Balances move through the ledger; editing the number directly
            // would silently desync it from the transactions that produced it.
            ? 'Balance changes come from transactions, not from here.'
            : 'The starting balance is what the account holds right now.',
        fields: [
          FormFieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. HDFC Savings',
            icon: Icons.account_balance_outlined,
            initial: existing?.name ?? '',
          ),
          if (existing == null)
            FormFieldSpec(
              key: 'current_balance',
              label: 'Starting balance',
              hint: '0',
              icon: Icons.currency_rupee,
              numeric: true,
              required: false,
            ),
        ],
        choices: [
          FormChoiceSpec(
            key: 'account_type',
            label: 'TYPE',
            options: const {
              'bank': 'Bank',
              'cash': 'Cash',
              'wallet': 'Wallet',
            },
            initial: existing?.accountType.name ?? 'bank',
          ),
        ],
      ),
    );
  }

  // ── Credit card ──────────────────────────────────────────────────────────

  static Future<bool?> creditCard(BuildContext context, {CreditCard? existing}) {
    return _show(
      context,
      InstrumentFormSheet._(
        kind: InstrumentKind.creditCard,
        title: existing == null ? 'Add credit card' : 'Edit credit card',
        existingId: existing?.id,
        note: 'Outstanding is worked out from your transactions, so there is '
            'nothing to enter for it.',
        fields: [
          FormFieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. Amex Platinum',
            icon: Icons.credit_card,
            initial: existing?.name ?? '',
          ),
          FormFieldSpec(
            key: 'last_four',
            label: 'Last 4 digits',
            hint: '4021',
            icon: Icons.pin_outlined,
            initial: existing?.lastFour ?? '',
            digitsOnly: true,
            required: false,
          ),
          FormFieldSpec(
            key: 'total_limit',
            label: 'Credit limit',
            hint: '200000',
            icon: Icons.speed_outlined,
            initial: existing?.totalLimit.toStringAsFixed(0) ?? '',
            numeric: true,
          ),
          FormFieldSpec(
            key: 'statement_day',
            label: 'Statement day',
            hint: '5',
            icon: Icons.receipt_long_outlined,
            initial: existing?.statementDay.toString() ?? '',
            integer: true,
            helper: 'Day of the month your bill is generated (1–31).',
          ),
          FormFieldSpec(
            key: 'due_day',
            label: 'Payment due day',
            hint: '25',
            icon: Icons.event_outlined,
            initial: existing?.dueDay.toString() ?? '',
            integer: true,
            helper: 'Shorter months use their last day.',
          ),
        ],
        choices: const [],
      ),
    );
  }

  // ── Loan ─────────────────────────────────────────────────────────────────

  static Future<bool?> loan(BuildContext context, {Loan? existing}) {
    return _show(
      context,
      InstrumentFormSheet._(
        kind: InstrumentKind.loan,
        title: existing == null ? 'Add loan' : 'Edit loan',
        existingId: existing?.id,
        note: existing == null
            ? 'The EMI is calculated for you from these terms.'
            : 'Principal and tenure are fixed once a loan exists — they define '
                'the EMI schedule.',
        fields: [
          FormFieldSpec(
            key: 'name',
            label: 'Name',
            hint: 'e.g. Car Loan',
            icon: Icons.account_balance_outlined,
            initial: existing?.name ?? '',
          ),
          if (existing == null)
            FormFieldSpec(
              key: 'principal_amount',
              label: 'Loan amount',
              hint: '500000',
              icon: Icons.currency_rupee,
              numeric: true,
            ),
          FormFieldSpec(
            key: 'interest_rate',
            label: 'Interest rate (% per year)',
            hint: '9.5',
            icon: Icons.percent,
            initial: existing?.interestRate.toString() ?? '',
            numeric: true,
          ),
          if (existing == null)
            FormFieldSpec(
              key: 'tenure_months',
              label: 'Tenure (months)',
              hint: '60',
              icon: Icons.schedule,
              integer: true,
              helper: 'Up to 600 months.',
            ),
          FormFieldSpec(
            key: 'outstanding_balance',
            label: 'Outstanding balance',
            hint: '500000',
            icon: Icons.trending_down,
            initial: existing?.outstandingBalance.toStringAsFixed(0) ?? '',
            numeric: true,
            helper: 'What you still owe today.',
          ),
        ],
        choices: [
          FormChoiceSpec(
            key: 'loan_type',
            label: 'TYPE',
            options: const {
              'personal': 'Personal',
              'home': 'Home',
              'auto': 'Auto',
              'education': 'Education',
              'other': 'Other',
            },
            initial: existing?.loanType.name ?? 'personal',
          ),
        ],
      ),
    );
  }

  static Future<bool?> _show(BuildContext context, InstrumentFormSheet sheet) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => sheet,
    );
  }

  @override
  ConsumerState<InstrumentFormSheet> createState() =>
      _InstrumentFormSheetState();
}

class _InstrumentFormSheetState extends ConsumerState<InstrumentFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, String> _choiceValues = {
    for (final c in widget.choices) c.key: c.initial,
  };

  bool get _isEditing => widget.existingId != null;

  @override
  void dispose() {
    for (final field in widget.fields) {
      field.controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final body = <String, dynamic>{..._choiceValues};
    for (final field in widget.fields) {
      final raw = field.controller.text.trim();
      if (raw.isEmpty) continue;
      body[field.key] = field.integer ? int.parse(raw) : raw;
    }

    // A loan needs a start date and the API has no default for it.
    if (widget.kind == InstrumentKind.loan && !_isEditing) {
      body['start_date'] = DateTime.now().toIso8601String().split('T').first;
    }

    final ok = await ref.read(manageControllerProvider.notifier).save(
          kind: widget.kind,
          body: body,
          id: widget.existingId,
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
        title: Text('Delete this ${widget.kind.label.toLowerCase()}?'),
        content: const Text(
          'Transactions already recorded against it stay in your ledger.',
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

    final ok = await ref.read(manageControllerProvider.notifier).remove(
          kind: widget.kind,
          id: widget.existingId!,
        );
    if (ok && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manageControllerProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.charcoal,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
            border: Border(top: BorderSide(color: AppColors.subtleBorder)),
          ),
          child: Form(
            key: _formKey,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            child: _buildBody(state, scrollController),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ManageState state, ScrollController scrollController) {
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
            widget.title.toUpperCase(),
            style: AppTypography.labelSmall.copyWith(
              color: AppColors.textTertiary,
              letterSpacing: 2.0,
              fontSize: 10,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (widget.note != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(widget.note!, style: AppTypography.bodySmall),
          ],
          const SizedBox(height: AppSpacing.lg),

          for (final choice in widget.choices) ...[
            _sectionLabel(choice.label),
            const SizedBox(height: AppSpacing.sm),
            _buildChoiceChips(choice),
            const SizedBox(height: AppSpacing.lg),
          ],

          for (final field in widget.fields) ...[
            _buildField(field),
            const SizedBox(height: AppSpacing.md),
          ],

          if (state.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xs),
            _ErrorBanner(message: state.errorMessage!),
          ],

          const SizedBox(height: AppSpacing.md),
          _buildSubmit(state.isLoading),
          if (_isEditing) ...[
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: state.isLoading ? null : _delete,
              style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
              child: Text('Delete ${widget.kind.label.toLowerCase()}'),
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

  Widget _buildChoiceChips(FormChoiceSpec choice) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: choice.options.entries.map((entry) {
        final isSelected = _choiceValues[choice.key] == entry.key;
        return GestureDetector(
          onTap: () => setState(() => _choiceValues[choice.key] = entry.key),
          child: AnimatedContainer(
            duration: 180.ms,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm + 2,
            ),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppColors.neonGreen.withValues(alpha: 0.14)
                  : AppColors.obsidian,
              borderRadius: AppRadius.pillAll,
              border: Border.all(
                color: isSelected
                    ? AppColors.neonGreen.withValues(alpha: 0.55)
                    : AppColors.subtleBorder,
              ),
            ),
            child: Text(
              entry.value,
              style: AppTypography.labelMedium.copyWith(
                color: isSelected
                    ? AppColors.neonGreen
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildField(FormFieldSpec field) {
    return TextFormField(
      controller: field.controller,
      style: AppTypography.bodyLarge,
      cursorColor: AppColors.neonGreen,
      keyboardType: field.numeric || field.integer || field.digitsOnly
          ? TextInputType.numberWithOptions(decimal: field.numeric)
          : TextInputType.text,
      inputFormatters: [
        if (field.integer || field.digitsOnly)
          FilteringTextInputFormatter.digitsOnly,
        if (field.numeric)
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
      ],
      textCapitalization:
          field.numeric || field.integer || field.digitsOnly
              ? TextCapitalization.none
              : TextCapitalization.words,
      decoration: InputDecoration(
        labelText: field.label,
        hintText: field.hint,
        helperText: field.helper,
        helperStyle: AppTypography.bodySmall.copyWith(fontSize: 11),
        helperMaxLines: 2,
        prefixIcon: Icon(field.icon, color: AppColors.textTertiary, size: 18),
      ),
      onChanged: (_) => ref.read(manageControllerProvider.notifier).clearError(),
      validator: (value) => _validate(field, value),
    );
  }

  String? _validate(FormFieldSpec field, String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) {
      return field.required ? 'Enter ${field.label.toLowerCase()}' : null;
    }
    if (field.numeric || field.integer || field.digitsOnly) {
      final parsed = num.tryParse(text);
      if (parsed == null) return 'Enter a number';
      if (parsed < 0) return 'Cannot be negative';
    }
    // Mirror the server's bounds so the user finds out before a round trip.
    if (field.key == 'statement_day' || field.key == 'due_day') {
      final day = int.tryParse(text) ?? 0;
      if (day < 1 || day > 31) return 'Must be between 1 and 31';
    }
    if (field.key == 'tenure_months') {
      final months = int.tryParse(text) ?? 0;
      if (months < 1 || months > 600) return 'Must be between 1 and 600';
    }
    if (field.key == 'last_four' && text.length != 4) {
      return 'Enter exactly 4 digits';
    }
    return null;
  }

  Widget _buildSubmit(bool isLoading) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.neonGreen,
          foregroundColor: AppColors.trueBlack,
          disabledBackgroundColor: AppColors.elevatedSurface,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
        onPressed: isLoading ? null : _save,
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
                _isEditing ? 'SAVE CHANGES' : 'ADD ${widget.kind.label.toUpperCase()}',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.trueBlack,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
