import 'package:flutter/material.dart';

class AppColors {
  static const Color navy = Color(0xFF123A8F);
  static const Color primary = Color(0xFF2563EB);
  static const Color brightBlue = Color(0xFF3B82F6);
  static const Color indigo = Color(0xFF5B5FEF);
  static const Color violet = Color(0xFF7C3AED);
  static const Color primaryDark = navy;
  static const Color background = Color(0xFFF5F7FF);
  static const Color surface = Colors.white;
  static const Color textPrimary = Color(0xFF1B2430);
  static const Color textSecondary = Color(0xFF7C8698);
  static const Color divider = Color(0xFFE7ECF5);

  static const Color success = Color(0xFF1F9254);
  static const Color successLight = Color(0xFFE7F7EE);
  static const Color warning = Color(0xFFE2A73B);
  static const Color warningLight = Color(0xFFFCF3E1);
  static const Color danger = Color(0xFFE0554A);
  static const Color dangerLight = Color(0xFFFBEBEA);
  static const Color info = Color(0xFF2F6FED);
}

class AppShadows {
  static List<BoxShadow> card = [
    BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 14, offset: const Offset(0, 4)),
  ];
  static List<BoxShadow> hero = [
    BoxShadow(color: AppColors.primary.withOpacity(0.25), blurRadius: 20, offset: const Offset(0, 8)),
  ];
}

class AppGradients {
  static const LinearGradient background = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFEFF4FE), Color(0xFFF3F6FC), Color(0xFFF3F6FC)],
    stops: [0.0, 0.4, 1.0],
  );

  static const LinearGradient punchCard = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [AppColors.primary, AppColors.indigo, AppColors.violet],
  );

  static const LinearGradient brand = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [AppColors.primary, AppColors.indigo, AppColors.violet],
  );
}
