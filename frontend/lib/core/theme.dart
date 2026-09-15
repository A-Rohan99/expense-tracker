/// CRED-inspired premium dark theme.
///
/// Design tokens:
/// - Backgrounds: True black (#000000), obsidian (#121212)
/// - Surfaces: Charcoal (#1E1E1E) with 5% white border
/// - Accents: Neon Green (#00FF66), Neon Pink (#FF0055), Neon Cyan (#00E5FF)
/// - Typography: Space Grotesk (headings), Inter (body)
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

// ═══════════════════════════════════════════════════════════════════════════
// Color Palette
// ═══════════════════════════════════════════════════════════════════════════

class AppColors {
  AppColors._();

  // ── Backgrounds ──────────────────────────────────────────────────────
  static const Color trueBlack       = Color(0xFF000000);
  static const Color obsidian        = Color(0xFF121212);
  static const Color charcoal        = Color(0xFF1E1E1E);
  static const Color elevatedSurface = Color(0xFF252525);
  static const Color subtleBorder    = Color(0x0DFFFFFF); // white @ 5%

  // ── Neon accents ─────────────────────────────────────────────────────
  static const Color neonGreen = Color(0xFF00FF66);
  static const Color neonPink  = Color(0xFFFF0055);
  static const Color neonCyan  = Color(0xFF00E5FF);
  static const Color neonAmber = Color(0xFFFFB300);
  static const Color neonRed   = Color(0xFFFF2A2A);

  // ── Semantic ─────────────────────────────────────────────────────────
  static const Color income  = neonGreen;
  static const Color expense = neonPink;
  static const Color transfer = neonCyan;

  // ── Text ─────────────────────────────────────────────────────────────
  static const Color textPrimary   = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF); // white @ 70%
  static const Color textTertiary  = Color(0x80FFFFFF); // white @ 50%
  static const Color textDisabled  = Color(0x4DFFFFFF); // white @ 30%

  // ── Gradients ────────────────────────────────────────────────────────
  static const LinearGradient neonGreenGradient = LinearGradient(
    colors: [Color(0xFF00FF66), Color(0xFF00CC52)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient neonCyanGradient = LinearGradient(
    colors: [Color(0xFF00E5FF), Color(0xFF00B8D4)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient cardGradient = LinearGradient(
    colors: [Color(0xFF1E1E1E), Color(0xFF161616)],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Spacing & Radius
// ═══════════════════════════════════════════════════════════════════════════

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

class AppRadius {
  AppRadius._();

  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 100;

  static BorderRadius get smAll => BorderRadius.circular(sm);
  static BorderRadius get mdAll => BorderRadius.circular(md);
  static BorderRadius get lgAll => BorderRadius.circular(lg);
  static BorderRadius get xlAll => BorderRadius.circular(xl);
  static BorderRadius get pillAll => BorderRadius.circular(pill);
}

// ═══════════════════════════════════════════════════════════════════════════
// Card Decoration (reusable)
// ═══════════════════════════════════════════════════════════════════════════

class AppDecorations {
  AppDecorations._();

  /// Standard card: charcoal fill + subtle white border + rounded corners.
  static BoxDecoration get card => BoxDecoration(
    color: AppColors.charcoal,
    borderRadius: AppRadius.lgAll,
    border: Border.all(color: AppColors.subtleBorder),
  );

  /// Elevated card with a faint glow for emphasis.
  static BoxDecoration elevatedCard({Color glowColor = AppColors.neonGreen}) =>
      BoxDecoration(
        color: AppColors.elevatedSurface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.subtleBorder),
        boxShadow: [
          BoxShadow(
            color: glowColor.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      );

  /// Gradient card for hero sections.
  static BoxDecoration get gradientCard => BoxDecoration(
    gradient: AppColors.cardGradient,
    borderRadius: AppRadius.lgAll,
    border: Border.all(color: AppColors.subtleBorder),
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// Typography
// ═══════════════════════════════════════════════════════════════════════════

class AppTypography {
  AppTypography._();

  // ── Space Grotesk — geometric, modern headings ──────────────────────
  static TextStyle get displayLarge => GoogleFonts.spaceGrotesk(
    fontSize: 40,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get displayMedium => GoogleFonts.spaceGrotesk(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    letterSpacing: -1.0,
    color: AppColors.textPrimary,
  );

  static TextStyle get displaySmall => GoogleFonts.spaceGrotesk(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineLarge => GoogleFonts.spaceGrotesk(
    fontSize: 24,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.25,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineMedium => GoogleFonts.spaceGrotesk(
    fontSize: 20,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get headlineSmall => GoogleFonts.spaceGrotesk(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    color: AppColors.textPrimary,
  );

  // ── Inter — clean, legible body text ────────────────────────────────
  static TextStyle get bodyLarge => GoogleFonts.inter(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    color: AppColors.textPrimary,
    height: 1.5,
  );

  static TextStyle get bodyMedium => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: AppColors.textSecondary,
    height: 1.5,
  );

  static TextStyle get bodySmall => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: AppColors.textTertiary,
    height: 1.4,
  );

  static TextStyle get labelLarge => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
    color: AppColors.textPrimary,
  );

  static TextStyle get labelMedium => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.textSecondary,
  );

  static TextStyle get labelSmall => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.5,
    color: AppColors.textTertiary,
  );

  // ── Monospace — for currency amounts ────────────────────────────────
  static TextStyle amountLarge({Color color = AppColors.textPrimary}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        color: color,
      );

  static TextStyle amountMedium({Color color = AppColors.textPrimary}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle amountSmall({Color color = AppColors.textSecondary}) =>
      GoogleFonts.spaceGrotesk(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: color,
      );
}

// ═══════════════════════════════════════════════════════════════════════════
// ThemeData builder
// ═══════════════════════════════════════════════════════════════════════════

ThemeData buildAppTheme() {
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,

    // ── Colors ──────────────────────────────────────────────────────
    scaffoldBackgroundColor: AppColors.trueBlack,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.obsidian,
      primary: AppColors.neonGreen,
      secondary: AppColors.neonCyan,
      error: AppColors.neonPink,
      onPrimary: AppColors.trueBlack,
      onSecondary: AppColors.trueBlack,
      onSurface: AppColors.textPrimary,
      onError: AppColors.textPrimary,
      outline: AppColors.subtleBorder,
    ),

    // ── Typography ─────────────────────────────────────────────────
    textTheme: TextTheme(
      displayLarge: AppTypography.displayLarge,
      displayMedium: AppTypography.displayMedium,
      displaySmall: AppTypography.displaySmall,
      headlineLarge: AppTypography.headlineLarge,
      headlineMedium: AppTypography.headlineMedium,
      headlineSmall: AppTypography.headlineSmall,
      bodyLarge: AppTypography.bodyLarge,
      bodyMedium: AppTypography.bodyMedium,
      bodySmall: AppTypography.bodySmall,
      labelLarge: AppTypography.labelLarge,
      labelMedium: AppTypography.labelMedium,
      labelSmall: AppTypography.labelSmall,
    ),

    // ── AppBar ─────────────────────────────────────────────────────
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.trueBlack,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: AppTypography.headlineMedium,
      systemOverlayStyle: SystemUiOverlayStyle.light,
    ),

    // ── Bottom Nav ─────────────────────────────────────────────────
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.obsidian,
      selectedItemColor: AppColors.neonGreen,
      unselectedItemColor: AppColors.textTertiary,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),

    // ── Cards ──────────────────────────────────────────────────────
    cardTheme: CardThemeData(
      color: AppColors.charcoal,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.lgAll,
        side: const BorderSide(color: AppColors.subtleBorder),
      ),
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
    ),

    // ── Elevated Button (neon green) ──────────────────────────────
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.neonGreen,
        foregroundColor: AppColors.trueBlack,
        elevation: 0,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: AppTypography.labelLarge.copyWith(
          color: AppColors.trueBlack,
        ),
      ),
    ),

    // ── Outlined Button ───────────────────────────────────────────
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.subtleBorder),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        textStyle: AppTypography.labelLarge,
      ),
    ),

    // ── Text Button ───────────────────────────────────────────────
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.neonCyan,
        textStyle: AppTypography.labelLarge,
      ),
    ),

    // ── Input fields ──────────────────────────────────────────────
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.charcoal,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      border: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: const BorderSide(color: AppColors.subtleBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: const BorderSide(color: AppColors.subtleBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: const BorderSide(color: AppColors.neonGreen, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: const BorderSide(color: AppColors.neonPink),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: AppRadius.mdAll,
        borderSide: const BorderSide(color: AppColors.neonPink, width: 1.5),
      ),
      labelStyle: AppTypography.bodyMedium,
      hintStyle: AppTypography.bodyMedium.copyWith(
        color: AppColors.textDisabled,
      ),
      errorStyle: AppTypography.bodySmall.copyWith(
        color: AppColors.neonPink,
      ),
    ),

    // ── Floating Action Button ────────────────────────────────────
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.neonGreen,
      foregroundColor: AppColors.trueBlack,
      elevation: 4,
      shape: CircleBorder(),
    ),

    // ── Chips ─────────────────────────────────────────────────────
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.charcoal,
      selectedColor: AppColors.neonGreen.withValues(alpha: 0.15),
      side: const BorderSide(color: AppColors.subtleBorder),
      labelStyle: AppTypography.labelMedium,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.pillAll),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
    ),

    // ── Divider ───────────────────────────────────────────────────
    dividerTheme: const DividerThemeData(
      color: AppColors.subtleBorder,
      thickness: 1,
      space: 0,
    ),

    // ── Bottom Sheet ──────────────────────────────────────────────
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.obsidian,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(AppRadius.xl),
          topRight: Radius.circular(AppRadius.xl),
        ),
      ),
      dragHandleColor: AppColors.textTertiary,
      showDragHandle: true,
    ),

    // ── Snackbar ──────────────────────────────────────────────────
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.elevatedSurface,
      contentTextStyle: AppTypography.bodyMedium,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      behavior: SnackBarBehavior.floating,
    ),

    // ── Dialog ────────────────────────────────────────────────────
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.obsidian,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      titleTextStyle: AppTypography.headlineMedium,
      contentTextStyle: AppTypography.bodyLarge,
    ),

    // ── Splash / ripple ───────────────────────────────────────────
    splashColor: AppColors.neonGreen.withValues(alpha: 0.08),
    highlightColor: AppColors.neonGreen.withValues(alpha: 0.04),
  );
}
