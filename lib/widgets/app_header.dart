import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'workora_logo.dart';

class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.employeeName,
    this.onNotificationTap,
    this.onProfileTap,
    this.showGreeting = false,
    this.greeting = 'Good morning',
  });

  final String employeeName;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onProfileTap;
  final bool showGreeting;
  final String greeting;

  String get _initials {
    final name = employeeName.trim();

    if (name.isEmpty) {
      return 'U';
    }

    final parts = name.split(RegExp(r'\s+'));

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return '${parts.first.substring(0, 1)}'
        '${parts.last.substring(0, 1)}'
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // --------------------------------------------------
            // WORKORA LOGO
            // --------------------------------------------------
            const SizedBox(
              width: 58,
              height: 42,
              child: WorkoraLogo(
                fit: BoxFit.contain,
              ),
            ),

            const SizedBox(width: 12),

            // --------------------------------------------------
            // COMPANY TEXT
            // --------------------------------------------------
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A Product of EDUBOTICS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'A Division of Hindustan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // --------------------------------------------------
            // NOTIFICATION
            // --------------------------------------------------
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onNotificationTap,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.divider,
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.textPrimary,
                    size: 23,
                  ),
                ),
              ),
            ),

            const SizedBox(width: 10),

            // --------------------------------------------------
            // PROFILE INITIALS
            // --------------------------------------------------
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onProfileTap,
                borderRadius: BorderRadius.circular(24),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initials,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),

        // ----------------------------------------------------
        // OPTIONAL GREETING
        // ----------------------------------------------------
        if (showGreeting) ...[
          const SizedBox(height: 18),

          Align(
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  employeeName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}