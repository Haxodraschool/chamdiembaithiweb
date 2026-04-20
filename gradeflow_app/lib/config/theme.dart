import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design System — "The Academic Editorial"
/// Matching the web app's design tokens.
class GradeFlowTheme {
  // ── Primary (Teal) ──
  static const Color primary = Color(0xFF0F766E);
  static const Color primaryContainer = Color(0xFF0D9488);
  static const Color primaryFixed = Color(0xFFCCFBF1);
  static const Color onPrimary = Colors.white;

  // ── Surface Layers ──
  static const Color surface = Color(0xFFF8F9FA);
  static const Color surfaceContainerLowest = Colors.white;
  static const Color surfaceContainerLow = Color(0xFFF3F4F5);
  static const Color surfaceContainer = Color(0xFFEDEEEF);
  static const Color surfaceContainerHigh = Color(0xFFE7E8E9);

  // ── On-Surface ──
  static const Color onSurface = Color(0xFF191C1D);
  static const Color onSurfaceVariant = Color(0xFF414754);

  // ── Outline ──
  static const Color outline = Color(0xFF727785);
  static const Color outlineVariant = Color(0xFFC1C6D6);

  // ── Error ──
  static const Color error = Color(0xFFBA1A1A);
  static const Color errorContainer = Color(0xFFFFDAD6);

  // ── Success ──
  static const Color success = Color(0xFF1B7A3D);
  static const Color successContainer = Color(0xFFD4F5E0);

  // ── Tertiary (Orange) ──
  static const Color tertiary = Color(0xFF8F4D00);
  static const Color tertiaryContainer = Color(0xFFFFDCC2);

  // ── Grade Colors ──
  static const Color gradeExcellent = Color(0xFF1B7A3D);
  static const Color gradeGood = Color(0xFF005BBF);
  static const Color gradeAverage = Color(0xFF856404);
  static const Color gradePoor = Color(0xFFBA1A1A);

  static Color gradeColor(String label) {
    switch (label) {
      case 'excellent':
        return gradeExcellent;
      case 'good':
        return gradeGood;
      case 'average':
        return gradeAverage;
      case 'poor':
        return gradePoor;
      default:
        return onSurfaceVariant;
    }
  }

  static Color gradeBackground(String label) {
    switch (label) {
      case 'excellent':
        return successContainer;
      case 'good':
        return const Color(0xFFD0E4FF);
      case 'average':
        return const Color(0xFFFEF3CD);
      case 'poor':
        return errorContainer;
      default:
        return surfaceContainer;
    }
  }

  static ThemeData get lightTheme {
    final textTheme = GoogleFonts.dmSansTextTheme().copyWith(
      displayLarge: GoogleFonts.manrope(
        fontSize: 32, fontWeight: FontWeight.w700, color: onSurface,
      ),
      displayMedium: GoogleFonts.manrope(
        fontSize: 28, fontWeight: FontWeight.w700, color: onSurface,
      ),
      displaySmall: GoogleFonts.manrope(
        fontSize: 24, fontWeight: FontWeight.w600, color: onSurface,
      ),
      headlineLarge: GoogleFonts.manrope(
        fontSize: 22, fontWeight: FontWeight.w600, color: onSurface,
      ),
      headlineMedium: GoogleFonts.manrope(
        fontSize: 20, fontWeight: FontWeight.w600, color: onSurface,
      ),
      headlineSmall: GoogleFonts.manrope(
        fontSize: 18, fontWeight: FontWeight.w600, color: onSurface,
      ),
      titleLarge: GoogleFonts.dmSans(
        fontSize: 18, fontWeight: FontWeight.w600, color: onSurface,
      ),
      titleMedium: GoogleFonts.dmSans(
        fontSize: 16, fontWeight: FontWeight.w600, color: onSurface,
      ),
      titleSmall: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w600, color: onSurface,
      ),
      bodyLarge: GoogleFonts.dmSans(
        fontSize: 16, fontWeight: FontWeight.w400, color: onSurface,
      ),
      bodyMedium: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w400, color: onSurface,
      ),
      bodySmall: GoogleFonts.dmSans(
        fontSize: 13, fontWeight: FontWeight.w400, color: onSurfaceVariant,
      ),
      labelLarge: GoogleFonts.dmSans(
        fontSize: 14, fontWeight: FontWeight.w600, color: onSurface,
      ),
      labelMedium: GoogleFonts.dmSans(
        fontSize: 12, fontWeight: FontWeight.w600, color: onSurfaceVariant,
      ),
      labelSmall: GoogleFonts.dmSans(
        fontSize: 11, fontWeight: FontWeight.w500, color: onSurfaceVariant,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: const ColorScheme.light(
        primary: primary,
        primaryContainer: primaryContainer,
        onPrimary: onPrimary,
        secondary: Color(0xFF5C5F60),
        secondaryContainer: Color(0xFFDEE0E1),
        tertiary: tertiary,
        tertiaryContainer: tertiaryContainer,
        error: error,
        errorContainer: errorContainer,
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
        outlineVariant: outlineVariant,
      ),
      scaffoldBackgroundColor: surface,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceContainerLowest,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        titleTextStyle: GoogleFonts.manrope(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceContainerLowest,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: onPrimary,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          side: const BorderSide(color: outlineVariant),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.dmSans(
            fontSize: 15, fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLow,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: outlineVariant, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primary, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: GoogleFonts.dmSans(
          color: outline, fontSize: 15,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceContainer,
        labelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide.none,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceContainerLowest,
        selectedItemColor: primary,
        unselectedItemColor: onSurfaceVariant,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
        selectedLabelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w600),
        unselectedLabelStyle: GoogleFonts.dmSans(fontSize: 12, fontWeight: FontWeight.w400),
      ),
      dividerTheme: const DividerThemeData(
        color: outlineVariant,
        thickness: 1,
        space: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: const Color(0xFF2E3132),
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
