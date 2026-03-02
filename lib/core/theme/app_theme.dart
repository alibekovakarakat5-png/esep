import 'package:flutter/material.dart';

/// Цвета флага Казахстана — голубой + золотой
class EsepColors {
  EsepColors._();

  // Primary — KZ sky blue
  static const Color primary = Color(0xFF0099CC);
  static const Color primaryDark = Color(0xFF0077A8);
  static const Color primaryLight = Color(0xFF33B5D9);

  // Accent — KZ gold
  static const Color gold = Color(0xFFF5A623);
  static const Color goldLight = Color(0xFFFFBF4D);

  // Semantic
  static const Color income = Color(0xFF27AE60);   // зелёный — доход
  static const Color expense = Color(0xFFE74C3C);  // красный — расход
  static const Color warning = Color(0xFFF39C12);  // жёлтый — предупреждение
  static const Color info = Color(0xFF2980B9);

  // Neutral
  static const Color surface = Color(0xFFF8F9FA);
  static const Color surfaceDark = Color(0xFF1A1D23);
  static const Color cardLight = Color(0xFFFFFFFF);
  static const Color cardDark = Color(0xFF242830);
  static const Color divider = Color(0xFFE8ECEF);
  static const Color textPrimary = Color(0xFF1A1D23);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textDisabled = Color(0xFFB0B7C3);
}

class AppTheme {
  AppTheme._();

  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EsepColors.primary,
          primary: EsepColors.primary,
          secondary: EsepColors.gold,
          surface: EsepColors.surface,
          brightness: Brightness.light,
        ),
        // fontFamily: 'Inter', // добавить после загрузки шрифтов
        scaffoldBackgroundColor: EsepColors.surface,
        cardTheme: CardThemeData(
          color: EsepColors.cardLight,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: EsepColors.divider, width: 1),
          ),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: EsepColors.cardLight,
          foregroundColor: EsepColors.textPrimary,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            // fontFamily: 'Inter', // добавить после загрузки шрифтов
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: EsepColors.textPrimary,
          ),
        ),
        bottomNavigationBarTheme: const BottomNavigationBarThemeData(
          backgroundColor: EsepColors.cardLight,
          selectedItemColor: EsepColors.primary,
          unselectedItemColor: EsepColors.textSecondary,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: EsepColors.primary,
            foregroundColor: Colors.white,
            minimumSize: const Size(double.infinity, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: const TextStyle(
              // fontFamily: 'Inter', // добавить после загрузки шрифтов
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: EsepColors.surface,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EsepColors.divider),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EsepColors.divider),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: EsepColors.primary, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          labelStyle: const TextStyle(color: EsepColors.textSecondary),
        ),
        textTheme: const TextTheme(
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: EsepColors.textPrimary),
          displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: EsepColors.textPrimary),
          headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
          headlineMedium: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: EsepColors.textPrimary),
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, color: EsepColors.textPrimary),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, color: EsepColors.textSecondary),
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: EsepColors.textPrimary),
        ),
      );

  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: EsepColors.primary,
          primary: EsepColors.primaryLight,
          secondary: EsepColors.goldLight,
          surface: EsepColors.surfaceDark,
          brightness: Brightness.dark,
        ),
        // fontFamily: 'Inter', // добавить после загрузки шрифтов
        scaffoldBackgroundColor: EsepColors.surfaceDark,
        cardTheme: CardThemeData(
          color: EsepColors.cardDark,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2E3340), width: 1),
          ),
        ),
      );
}
