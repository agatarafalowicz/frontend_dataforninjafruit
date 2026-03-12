import 'package:flutter/material.dart';

class AppColors {
  // Brand and interactive colors derived from the Home screen.
  static const Color primary = Color(0xFF3B82F6);
  static const Color primaryHover = Color(0xFF2563EB);
  static const Color primarySoft = Color(0xFFDBEAFE);
  static const Color primarySoftBorder = Color(0xFFBFDBFE);
  static const Color primaryText = Color(0xFF1D4ED8);

  static const Color gradientStart = Color(0xFFE0E7FF);
  static const Color gradientEnd = Color(0xFFEDE9FE);

  static const Color surface = Colors.white;
  static const Color surfaceMuted = Color(0xFFF3F4F6);
  static const Color border = Color(0xFFE5E7EB);

  static const Color textPrimary = Color(0xFF111827);
  static const Color textSecondary = Color(0xFF374151);
  static const Color textMuted = Color(0xFF6B7280);
  static const Color textSubtle = Color(0xFF9CA3AF);

  static const Color success = Color(0xFF22C55E);
  static const Color danger = Color(0xFFDC2626);
  static const Color dangerSoft = Color(0xFFFEE2E2);
  static const Color dangerText = Color(0xFFB91C1C);

  static const Color sensorAcc = Color(0xFF0EA5E9);
  static const Color sensorGyro = Color(0xFFF97316);
  static const Color warning = Color(0xFFF59E0B);

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [gradientStart, gradientEnd],
  );
}

class AppTheme {
  static const Color primary = AppColors.primary;
  static const Color surface = AppColors.surface;
  static const Color background = Color(0xFFF6F7FB);
  static const Color text = AppColors.textPrimary;
  static const Color muted = AppColors.textMuted;

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: const ColorScheme.light(
        primary: AppColors.primary,
        onPrimary: Colors.white,
        secondary: AppColors.primary,
        onSecondary: Colors.white,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.danger,
        onError: Colors.white,
      ),
    );

    return base.copyWith(
      scaffoldBackgroundColor: background,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        foregroundColor: text,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceMuted,
        hintStyle: const TextStyle(color: muted),
        labelStyle: const TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.2),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.5),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.textPrimary,
        unselectedLabelColor: AppColors.textMuted,
      ),
    );
  }
}
