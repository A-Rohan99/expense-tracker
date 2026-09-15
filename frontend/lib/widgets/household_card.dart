/// Household membership: create one, join one with an invite code, or leave.
///
/// Lives on the Manage screen. Without it the dashboard's Private/Household
/// toggle had nothing to switch between.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/household_providers.dart';

class HouseholdCard extends ConsumerWidget {
  const HouseholdCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final household = ref.watch(householdProvider);

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
              const Icon(Icons.people_outline,
                  size: 16, color: AppColors.neonCyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'HOUSEHOLD',
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
          household.when(
            loading: () => const SizedBox(
              height: 44,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.neonCyan,
                  ),
                ),
              ),
            ),
            error: (_, _) => Text(
              'Could not load your household.',
              style:
                  AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
            ),
            data: (data) => data == null
                ? const _NotInHousehold()
                : _InHousehold(household: data),
          ),
        ],
      ),
    );
  }
}

class _NotInHousehold extends ConsumerWidget {
  const _NotInHousehold();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Share spending with family. Anyone in the household sees the '
          'transactions you mark as shared — nothing else.',
          style: AppTypography.bodySmall,
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 44,
          child: OutlinedButton.icon(
            onPressed: () => HouseholdSheet.show(context, joining: false),
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: Text('Create a household',
                style: AppTypography.labelMedium),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 44,
          child: TextButton(
            onPressed: () => HouseholdSheet.show(context, joining: true),
            child: Text('I have an invite code',
                style: AppTypography.labelMedium
                    .copyWith(color: AppColors.neonCyan)),
          ),
        ),
      ],
    );
  }
}

class _InHousehold extends ConsumerWidget {
  const _InHousehold({required this.household});

  final Household household;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(householdMembersProvider);
    final state = ref.watch(householdControllerProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          household.name,
          style: AppTypography.headlineSmall.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _sectionLabel('INVITE CODE'),
        const SizedBox(height: AppSpacing.sm),
        _InviteCode(code: household.inviteCode),

        const SizedBox(height: AppSpacing.md),
        _sectionLabel('MEMBERS'),
        const SizedBox(height: AppSpacing.sm),
        members.when(
          loading: () => Text('Loading…', style: AppTypography.bodySmall),
          error: (_, _) => Text(
            'Could not load members.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.neonPink),
          ),
          data: (list) => Column(
            children: [
              for (final member in list)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline,
                          size: 16, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpacing.sm),
                      // Expanded so a long name or email cannot overflow.
                      Expanded(
                        child: Text(
                          member.name.isEmpty ? member.email : member.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: AppSpacing.sm),
        SizedBox(
          height: 44,
          child: TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: AppColors.neonPink),
            onPressed: state.isLoading
                ? null
                : () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Leave this household?'),
                        content: const Text(
                          'Your own transactions stay yours. You just stop '
                          'seeing what others shared.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Stay'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(true),
                            style: TextButton.styleFrom(
                                foregroundColor: AppColors.neonPink),
                            child: const Text('Leave'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await ref
                        .read(householdControllerProvider.notifier)
                        .leave();
                  },
            icon: const Icon(Icons.logout_rounded, size: 16),
            label: Text('Leave household', style: AppTypography.labelMedium),
          ),
        ),
      ],
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
}

/// The invite code with a copy button — it is the only way anyone else gets in.
class _InviteCode extends StatefulWidget {
  const _InviteCode({required this.code});

  final String code;

  @override
  State<_InviteCode> createState() => _InviteCodeState();
}

class _InviteCodeState extends State<_InviteCode> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.obsidian,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.code,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySmall.copyWith(
                fontFamily: 'monospace',
                color: AppColors.textPrimary,
              ),
            ),
          ),
          IconButton(
            tooltip: _copied ? 'Copied' : 'Copy invite code',
            icon: Icon(
              _copied ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: _copied ? AppColors.neonGreen : AppColors.textTertiary,
            ),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.code));
              if (!mounted) return;
              setState(() => _copied = true);
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) setState(() => _copied = false);
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Create / join sheet
// ═══════════════════════════════════════════════════════════════════════════

class HouseholdSheet extends ConsumerStatefulWidget {
  const HouseholdSheet({super.key, required this.joining});

  final bool joining;

  static Future<bool?> show(BuildContext context, {required bool joining}) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => HouseholdSheet(joining: joining),
    );
  }

  @override
  ConsumerState<HouseholdSheet> createState() => _HouseholdSheetState();
}

class _HouseholdSheetState extends ConsumerState<HouseholdSheet> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    final value = _controller.text.trim();
    if (value.isEmpty) {
      setState(() => _error = widget.joining
          ? 'Paste the invite code you were sent'
          : 'Give your household a name');
      return;
    }
    setState(() => _error = null);

    final controller = ref.read(householdControllerProvider.notifier);
    final ok = widget.joining
        ? await controller.join(value)
        : await controller.create(value);

    if (ok && mounted) {
      HapticFeedback.lightImpact();
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(householdControllerProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          color: AppColors.charcoal,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
          border: Border(top: BorderSide(color: AppColors.subtleBorder)),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  widget.joining ? 'JOIN A HOUSEHOLD' : 'CREATE A HOUSEHOLD',
                  style: AppTypography.labelSmall.copyWith(
                    color: AppColors.textTertiary,
                    letterSpacing: 2.0,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  widget.joining
                      ? 'Paste the code from whoever set the household up.'
                      : 'You will get an invite code to share with family.',
                  style: AppTypography.bodySmall,
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _controller,
                  focusNode: _focus,
                  style: AppTypography.bodyLarge,
                  cursorColor: AppColors.neonCyan,
                  textCapitalization: widget.joining
                      ? TextCapitalization.none
                      : TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: widget.joining ? 'Invite code' : 'Household name',
                    hintText: widget.joining ? 'Paste it here' : 'e.g. Malik family',
                    prefixIcon: Icon(
                      widget.joining ? Icons.vpn_key_outlined : Icons.home_outlined,
                      color: AppColors.textTertiary,
                      size: 18,
                    ),
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                    ref.read(householdControllerProvider.notifier).clearError();
                  },
                  onSubmitted: (_) => _submit(),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(_error!,
                      style: AppTypography.bodySmall
                          .copyWith(color: AppColors.neonPink)),
                ],
                if (state.errorMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.neonPink.withValues(alpha: 0.08),
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(
                          color: AppColors.neonPink.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            color: AppColors.neonPink, size: 18),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            state.errorMessage!,
                            style: AppTypography.bodySmall
                                .copyWith(color: AppColors.neonPink),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 200.ms),
                ],
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  height: 54,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.neonCyan,
                      foregroundColor: AppColors.trueBlack,
                      shape:
                          RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                    ),
                    onPressed: state.isLoading ? null : _submit,
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
                            widget.joining ? 'JOIN' : 'CREATE',
                            style: AppTypography.labelLarge.copyWith(
                              color: AppColors.trueBlack,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
