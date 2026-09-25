import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'superadmin_dashboard.dart';
import 'admin_attendance_screen.dart';
import 'reports_screen.dart';
import 'superadmin_profile_screen.dart';

/// Dedicated shell for the CEO / Super Admin.
///
/// The CEO is NOT treated as an employee and does not use
/// EmployeeShell or AdminShell.
class SuperAdminShell extends StatefulWidget {
  final String superAdminId;
  final String? superAdminName;

  const SuperAdminShell({
    super.key,
    required this.superAdminId,
    this.superAdminName,
  });

  @override
  State<SuperAdminShell> createState() =>
      _SuperAdminShellState();
}

class _SuperAdminShellState
    extends State<SuperAdminShell> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final displayName =
        widget.superAdminName ??
        widget.superAdminId;

    final tabs = <Widget>[
      // --------------------------------------------------------
      // CEO HOME
      // --------------------------------------------------------

      SuperAdminDashboard(
        superAdminId:
            widget.superAdminId,
        superAdminName:
            widget.superAdminName,
      ),

      // --------------------------------------------------------
      // ALL EMPLOYEE ATTENDANCE
      // --------------------------------------------------------

      AdminAttendanceScreen(
        adminId:
            widget.superAdminId,
        adminName:
            displayName,
      ),

      // --------------------------------------------------------
      // REPORTS
      // --------------------------------------------------------

      const ReportsScreen(),

      // --------------------------------------------------------
      // CEO PROFILE
      // --------------------------------------------------------

      SuperAdminProfileScreen(
        superAdminId:
            widget.superAdminId,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: currentIndex,
        children: tabs,
      ),

      // ========================================================
      // CEO BOTTOM NAVIGATION
      // ========================================================

      bottomNavigationBar:
          NavigationBar(
        selectedIndex: currentIndex,

        onDestinationSelected:
            (index) {
          setState(() {
            currentIndex = index;
          });
        },

        backgroundColor:
            AppColors.surface,

        indicatorColor:
            AppColors.primary
                .withValues(alpha: 0.15),

        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.dashboard_outlined,
            ),
            selectedIcon: Icon(
              Icons.dashboard,
              color:
                  AppColors.primary,
            ),
            label: 'CEO Home',
          ),

          NavigationDestination(
            icon: Icon(
              Icons.calendar_month_outlined,
            ),
            selectedIcon: Icon(
              Icons.calendar_month,
              color:
                  AppColors.primary,
            ),
            label: 'Attendance',
          ),

          NavigationDestination(
            icon: Icon(
              Icons.analytics_outlined,
            ),
            selectedIcon: Icon(
              Icons.analytics,
              color:
                  AppColors.primary,
            ),
            label: 'Reports',
          ),

          NavigationDestination(
            icon: Icon(
              Icons.verified_user_outlined,
            ),
            selectedIcon: Icon(
              Icons.verified_user,
              color:
                  AppColors.primary,
            ),
            label: 'My Profile',
          ),
        ],
      ),
    );
  }
}