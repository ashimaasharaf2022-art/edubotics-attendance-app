import 'package:flutter/material.dart';

class AppColors {
  // ============================================================
  // WORKORA BRAND
  // ============================================================

  // Dark green used for Reports and main HRMS sections
  static const Color primary = Color(0xFF0F5B3F);

  // Bright green used for buttons/highlights
  static const Color brightGreen = Color(0xFF84E200);

  // Main Workora green
  static const Color green = Color(0xFF0BA66B);

  // Darker green
  static const Color primaryDark = Color(0xFF08452F);

  // ============================================================
  // BACKGROUND
  // ============================================================

  static const Color background = Color(0xFFF7F9F7);

  static const Color surface = Colors.white;

  // ============================================================
  // TEXT
  // ============================================================

  static const Color textPrimary = Color(0xFF16211D);

  static const Color textSecondary = Color(0xFF66736D);

  static const Color mutedText = Color(0xFF8A9690);

  static const Color darkText = Color(0xFF16211D);

  // ============================================================
  // DIVIDERS / GREY
  // ============================================================

  static const Color divider = Color(0xFFE3E9E5);

  static const Color grey = Color(0xFF8A9690);

  static const Color lightGrey = Color(0xFFF1F4F2);

  // ============================================================
  // SUCCESS / FULL DAY
  // ============================================================

  static const Color success = Color(0xFF0BA66B);

  static const Color successLight = Color(0xFFE7F6E9);

  // ============================================================
  // CALENDAR STATUS COLORS
  // ============================================================

  // Present — soft green like the attendance calendar
  static const Color calendarPresent = Color(0xFFE7F6EA);
  static const Color calendarPresentText = Color(0xFF138A5B);

  // Leave — soft warm amber
  static const Color calendarLeave = Color(0xFFFFF2D9);
  static const Color calendarLeaveText = Color(0xFFC48A19);

  // Absent — soft red
  static const Color calendarAbsent = Color(0xFFFDE9E9);
  static const Color calendarAbsentText = Color(0xFFD95757);

  // Pending — soft yellow
  static const Color calendarPending = Color(0xFFFFF7DF);
  static const Color calendarPendingText = Color(0xFFC49A2C);

  // Neutral day / no attendance
  static const Color calendarNeutral = Color(0xFFF0F3F1);
  static const Color calendarNeutralText = Color(0xFF66736D);

  // Today's highlighted circle
  static const Color calendarTodayFill = Color(0xFFE7F6EA);
  static const Color calendarTodayBorder = Color(0xFF0BA66B);
  static const Color calendarTodayText = Color(0xFF0F5B3F);

  // Calendar tile border and subtle shadow
  static const Color calendarTileBorder = Color(0xFFE8EEEA);
  static const Color calendarTileShadow = Color(0x12000000);

  // ============================================================
  // WARNING / WORK-PENDING / MIS-PUNCH
  // ============================================================

  static const Color warning = Color(0xFFE5B23C);

  static const Color warningLight = Color(0xFFFFF7DF);

  // ============================================================
  // DANGER / ABSENT
  // ============================================================

  static const Color danger = Color(0xFFD95757);

  static const Color dangerLight = Color(0xFFFDECEC);

  // ============================================================
  // INFORMATION
  // ============================================================

  static const Color info = Color(0xFF2F8F6B);

  static const Color infoLight = Color(0xFFEAF6F0);

  // ============================================================
  // LIGHT GREEN UI
  // ============================================================

  static const Color lightGreen = Color(0xFFE7F6E9);

  static const Color veryLightGreen = Color(0xFFF1FAF3);

  static const Color greenBorder = Color(0xFFCFE9D7);

  // ============================================================
  // BASIC
  // ============================================================

  static const Color black = Color(0xFF101512);
}


// ================================================================
// WORKORA SHADOWS
// ================================================================

class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.035),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];

  static List<BoxShadow> hero = [
    BoxShadow(
      color: AppColors.primary.withValues(alpha: 0.16),
      blurRadius: 18,
      offset: const Offset(0, 7),
    ),
  ];

  static List<BoxShadow> floating = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.14),
      blurRadius: 16,
      offset: const Offset(0, 7),
    ),
  ];
}


// ================================================================
// WORKORA GRADIENTS
// ================================================================

class AppGradients {
  // Application background
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color(0xFFF7F9F7),
      Color(0xFFF7F9F7),
    ],
  );

  // Dark green punch card — keeps the Workora primary green,
  // with a subtle transition into the main brand green.
  static const LinearGradient punchCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      AppColors.primaryDark,
      AppColors.primary,
      Color(0xFF0B7950),
      AppColors.green,
    ],
    stops: [0.0, 0.35, 0.72, 1.0],
  );

  // Workora branding
  static const LinearGradient brand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [
      Color(0xFF0F5B3F),
      Color(0xFF0BA66B),
    ],
  );

  // Bright green actions
  static const LinearGradient brightGreen = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF84E200),
      Color(0xFF6FD000),
    ],
  );
}