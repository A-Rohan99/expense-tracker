/// CRED-inspired sign-in / sign-up screen.
///
/// One form, two modes: [AuthMode.signIn] asks for email + password,
/// [AuthMode.signUp] adds a full-name field and registers before signing in.
/// On success [AuthNotifier] flips to authenticated and GoRouter redirects
/// to `/home`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme.dart';
import '../providers/auth_providers.dart';

/// Backend enforces `min_length=8` on password — mirror it client-side so the
/// user finds out before the round trip.
const int _kMinPasswordLength = 8;

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final controller = ref.read(authControllerProvider.notifier);
    final isSignUp = ref.read(authControllerProvider).isSignUp;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    // No navigation here — GoRouter's redirect reacts to the auth state.
    if (isSignUp) {
      await controller.signUp(
        email: email,
        password: password,
        fullName: _nameController.text.trim(),
      );
    } else {
      await controller.signIn(email: email, password: password);
    }
  }

  void _switchMode(AuthMode mode) {
    ref.read(authControllerProvider.notifier).setMode(mode);
    _formKey.currentState?.reset();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(authControllerProvider);
    final isSignUp = formState.isSignUp;

    return Scaffold(
      backgroundColor: AppColors.trueBlack,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.xl,
            ),
            child: ConstrainedBox(
              // Keeps the form phone-width even on a wide browser window.
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                // Without this, a field's error text stays on screen while the
                // user is already typing the fix — it would only refresh on the
                // next submit.
                autovalidateMode: AutovalidateMode.onUserInteraction,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildBrandMark(),
                    const SizedBox(height: AppSpacing.xl),
                    _ModeSwitch(
                      mode: formState.mode,
                      enabled: !formState.isLoading,
                      onChanged: _switchMode,
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // ── Full name (sign-up only) ──────────────────────────
                    if (isSignUp) ...[
                      _buildField(
                        controller: _nameController,
                        label: 'Full name',
                        hint: 'Jordan Rivera',
                        icon: Icons.person_outline,
                        textInputAction: TextInputAction.next,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Enter your name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    // ── Email ─────────────────────────────────────────────
                    _buildField(
                      controller: _emailController,
                      label: 'Email',
                      hint: 'you@example.com',
                      icon: Icons.alternate_email,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      validator: (value) {
                        final email = value?.trim() ?? '';
                        if (email.isEmpty) return 'Enter your email';
                        if (!email.contains('@') || !email.contains('.')) {
                          return 'Enter a valid email address';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),

                    // ── Password ──────────────────────────────────────────
                    _buildField(
                      controller: _passwordController,
                      label: 'Password',
                      hint: 'At least $_kMinPasswordLength characters',
                      icon: Icons.lock_outline,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _submit(),
                      suffix: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppColors.textTertiary,
                          size: 20,
                        ),
                        tooltip:
                            _obscurePassword ? 'Show password' : 'Hide password',
                        onPressed: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                      ),
                      validator: (value) {
                        final password = value ?? '';
                        if (password.isEmpty) return 'Enter your password';
                        if (password.length < _kMinPasswordLength) {
                          return 'Must be at least $_kMinPasswordLength characters';
                        }
                        return null;
                      },
                    ),

                    // ── Server error ──────────────────────────────────────
                    if (formState.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _ErrorBanner(message: formState.errorMessage!),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    _buildSubmitButton(formState.isLoading, isSignUp),
                    const SizedBox(height: AppSpacing.md),
                    _buildFooterHint(isSignUp, formState.isLoading),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Brand mark ───────────────────────────────────────────────────────────

  Widget _buildBrandMark() {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            gradient: AppColors.neonGreenGradient,
            borderRadius: AppRadius.lgAll,
            boxShadow: [
              BoxShadow(
                color: AppColors.neonGreen.withValues(alpha: 0.24),
                blurRadius: 32,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Icon(
            Icons.account_balance_wallet,
            size: 32,
            color: AppColors.trueBlack,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'EXPENSE TRACKER',
          textAlign: TextAlign.center,
          style: AppTypography.labelSmall.copyWith(
            color: AppColors.textTertiary,
            letterSpacing: 2.0,
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Your money,\nunder control.',
          textAlign: TextAlign.center,
          style: AppTypography.displaySmall.copyWith(
            fontWeight: FontWeight.w800,
            height: 1.15,
          ),
        ),
      ],
    )
        .animate()
        .fadeIn(duration: 500.ms)
        .slideY(begin: 0.12, end: 0, curve: Curves.easeOutCubic);
  }

  // ── Text field ───────────────────────────────────────────────────────────

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
    bool obscureText = false,
    Widget? suffix,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      obscureText: obscureText,
      style: AppTypography.bodyLarge,
      cursorColor: AppColors.neonGreen,
      // Clear a stale server error as soon as the user starts fixing things.
      onChanged: (_) => ref.read(authControllerProvider.notifier).clearError(),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: AppColors.textTertiary, size: 20),
        suffixIcon: suffix,
      ),
    );
  }

  // ── Submit ───────────────────────────────────────────────────────────────

  Widget _buildSubmitButton(bool isLoading, bool isSignUp) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: isLoading ? null : _submit,
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
                isSignUp ? 'CREATE ACCOUNT' : 'SIGN IN',
                style: AppTypography.labelLarge.copyWith(
                  color: AppColors.trueBlack,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }

  Widget _buildFooterHint(bool isSignUp, bool isLoading) {
    // Wrap, not Row: on a narrow phone the label + button are wider than the
    // form and would overflow. This lets the button drop to its own line.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          isSignUp ? 'Already have an account?' : 'New to Expense Tracker?',
          style: AppTypography.bodySmall,
        ),
        TextButton(
          onPressed: isLoading
              ? null
              : () => _switchMode(isSignUp ? AuthMode.signIn : AuthMode.signUp),
          child: Text(isSignUp ? 'Sign in' : 'Create an account'),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// Mode switch — pill segmented control
// ═══════════════════════════════════════════════════════════════════════════

class _ModeSwitch extends StatelessWidget {
  const _ModeSwitch({
    required this.mode,
    required this.enabled,
    required this.onChanged,
  });

  final AuthMode mode;
  final bool enabled;
  final ValueChanged<AuthMode> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.charcoal,
        borderRadius: AppRadius.pillAll,
        border: Border.all(color: AppColors.subtleBorder),
      ),
      child: Row(
        children: [
          _segment('Sign in', AuthMode.signIn),
          _segment('Create account', AuthMode.signUp),
        ],
      ),
    );
  }

  Widget _segment(String label, AuthMode value) {
    final isSelected = mode == value;
    return Expanded(
      child: GestureDetector(
        onTap: enabled ? () => onChanged(value) : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: 220.ms,
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.neonGreen.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: AppRadius.pillAll,
            border: Border.all(
              color: isSelected
                  ? AppColors.neonGreen.withValues(alpha: 0.5)
                  : Colors.transparent,
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: AppTypography.labelMedium.copyWith(
              color: isSelected ? AppColors.neonGreen : AppColors.textTertiary,
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
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.neonPink,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms).shake(
          hz: 3,
          offset: const Offset(2, 0),
        );
  }
}
