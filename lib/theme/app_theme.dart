import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../utils/app_colors.dart';

class AppTheme {
  static final TextTheme _interTextTheme = GoogleFonts.interTextTheme(
    const TextTheme(),
  ).copyWith(
    displayLarge: GoogleFonts.inter(fontSize: 32, fontWeight: FontWeight.w800, height: 1.15, letterSpacing: -0.7, color: AppColors.textPrimary),
    displayMedium: GoogleFonts.inter(fontSize: 28, fontWeight: FontWeight.w800, height: 1.18, letterSpacing: -0.6, color: AppColors.textPrimary),
    displaySmall: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.45, color: AppColors.textPrimary),
    headlineLarge: GoogleFonts.inter(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2, letterSpacing: -0.45, color: AppColors.textPrimary),
    headlineMedium: GoogleFonts.inter(fontSize: 21, fontWeight: FontWeight.w800, height: 1.22, letterSpacing: -0.25, color: AppColors.textPrimary),
    headlineSmall: GoogleFonts.inter(fontSize: 19, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.15, color: AppColors.textPrimary),
    titleLarge: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w700, height: 1.25, letterSpacing: -0.1, color: AppColors.textPrimary),
    titleMedium: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    titleSmall: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700, height: 1.3, color: AppColors.textPrimary),
    bodyLarge: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w500, height: 1.4, color: AppColors.textPrimary),
    bodyMedium: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w500, height: 1.4, color: AppColors.textSecondary),
    bodySmall: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w500, height: 1.35, color: AppColors.textSecondary),
    labelLarge: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.textPrimary),
    labelMedium: GoogleFonts.inter(fontSize: 11, fontWeight: FontWeight.w600, height: 1.2, color: AppColors.textSecondary),
    labelSmall: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.w600, height: 1.2, color: AppColors.textSecondary),
  );

  static ThemeData lightTheme = ThemeData(
    useMaterial3: true,

    // ------------------------------------------------------------
    // COLORS
    // ------------------------------------------------------------
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.green,
      onSecondary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      error: AppColors.danger,
      onError: Colors.white,
    ),

    scaffoldBackgroundColor: AppColors.background,

    // ------------------------------------------------------------
    // APP BAR
    // ------------------------------------------------------------
    appBarTheme: AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w800,
      ),
    ),

    // ------------------------------------------------------------
    // TEXT
    // ------------------------------------------------------------
    fontFamily: GoogleFonts.inter().fontFamily,
    textTheme: _interTextTheme,

    // ------------------------------------------------------------
    // CARD
    // ------------------------------------------------------------
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(
          color: AppColors.divider,
          width: 1,
        ),
      ),
    ),

    // ------------------------------------------------------------
    // ELEVATED BUTTON
    // ------------------------------------------------------------
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // ------------------------------------------------------------
    // FILLED BUTTON
    // ------------------------------------------------------------
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 14,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // ------------------------------------------------------------
    // OUTLINED BUTTON
    // ------------------------------------------------------------
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        minimumSize: const Size(0, 50),
        padding: const EdgeInsets.symmetric(
          horizontal: 22,
          vertical: 14,
        ),
        side: const BorderSide(
          color: AppColors.green,
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // ------------------------------------------------------------
    // TEXT BUTTON
    // ------------------------------------------------------------
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.primary,
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),

    // ------------------------------------------------------------
    // INPUT FIELDS
    // ------------------------------------------------------------
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 15,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.green,
          width: 1.5,
        ),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.danger,
        ),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(
          color: AppColors.danger,
          width: 1.5,
        ),
      ),
      hintStyle: GoogleFonts.inter(
        color: AppColors.mutedText,
        fontSize: 14,
      ),
      labelStyle: GoogleFonts.inter(
        color: AppColors.textSecondary,
        fontSize: 14,
      ),
    ),

    // ------------------------------------------------------------
    // CHIP
    // ------------------------------------------------------------
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.lightGreen,
      selectedColor: AppColors.green,
      disabledColor: AppColors.lightGrey,
      side: BorderSide.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      labelStyle: GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 5,
      ),
    ),

    // ------------------------------------------------------------
    // NAVIGATION BAR
    // ------------------------------------------------------------
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AppColors.lightGreen,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith<TextStyle?>(
        (states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            );
          }

          return GoogleFonts.inter(
            color: AppColors.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          );
        },
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData?>(
        (states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(
              color: AppColors.primary,
              size: 23,
            );
          }

          return const IconThemeData(
            color: AppColors.textSecondary,
            size: 22,
          );
        },
      ),
    ),

    // ------------------------------------------------------------
    // DIVIDER
    // ------------------------------------------------------------
    dividerTheme: const DividerThemeData(
      color: AppColors.divider,
      thickness: 1,
      space: 1,
    ),

    // ------------------------------------------------------------
    // DIALOG
    // ------------------------------------------------------------
    dialogTheme: DialogThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
      ),
      titleTextStyle: GoogleFonts.inter(
        color: AppColors.textPrimary,
        fontSize: 20,
        fontWeight: FontWeight.w800,
      ),
      contentTextStyle: GoogleFonts.inter(
        color: AppColors.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
    ),

    // ------------------------------------------------------------
    // SNACKBAR
    // ------------------------------------------------------------
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.primary,
      contentTextStyle: GoogleFonts.inter(
        color: Colors.white,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
    ),

    // ------------------------------------------------------------
    // PROGRESS INDICATOR
    // ------------------------------------------------------------
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.green,
    ),

    // ------------------------------------------------------------
    // ICON
    // ------------------------------------------------------------
    iconTheme: const IconThemeData(
      color: AppColors.textPrimary,
      size: 22,
    ),
  );
}