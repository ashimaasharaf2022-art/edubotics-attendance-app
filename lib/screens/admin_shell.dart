import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'admin_dashboard.dart';
import 'admin_attendance_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';
import 'employee_shell.dart';

/// Shell for an employee who has Admin access.
///
/// Super Admin/CEO normally uses SuperAdminShell instead.
/// This shell can still receive isSuperAdmin for compatibility,
/// but the normal Admin flow always passes false.
class AdminShell extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final bool isSuperAdmin;

  const AdminShell({
    super.key,
    required this.employeeId,
    this.employeeName,
    this.isSuperAdmin = false,
  });

  @override
  State<AdminShell> createState() =>
      _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int currentIndex = 0;

  // ============================================================
  // SWITCH BACK TO EMPLOYEE DASHBOARD
  // ============================================================

  void _switchToMyDashboard() {
    // Super Admin/CEO must not use the employee dashboard switch.
    if (widget.isSuperAdmin) {
      return;
    }

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EmployeeShell(
          employeeId: widget.employeeId,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final adminName =
        widget.employeeName ??
        widget.employeeId;

    final tabs = <Widget>[
      // --------------------------------------------------------
      // ADMIN HOME
      // --------------------------------------------------------

      AdminDashboard(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        isSuperAdmin:
            widget.isSuperAdmin,
      ),

      // --------------------------------------------------------
      // ATTENDANCE
      // --------------------------------------------------------

      AdminAttendanceScreen(
        adminId: widget.employeeId,
        adminName: adminName,
        onBackToHome: () {
          if (mounted) setState(() => currentIndex = 0);
        },
      ),

      // --------------------------------------------------------
      // REPORTS
      // --------------------------------------------------------

      const ReportsScreen(),

      // --------------------------------------------------------
      // ADMIN PROFILE
      // --------------------------------------------------------

      ProfileScreen(
        employeeId: widget.employeeId,
        isAdmin: true,
        isSuperAdmin:
            widget.isSuperAdmin,

        // Only normal Admin users receive the
        // "Switch to My Employee Dashboard" action.
        onSwitchToMyDashboard:
            widget.isSuperAdmin
                ? null
                : _switchToMyDashboard,
      ),
    ];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop || !mounted) return;

        if (currentIndex != 0) {
          setState(() => currentIndex = 0);
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You are on the Admin Home dashboard."),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        body: IndexedStack(
          index: currentIndex,
          children: tabs,
        ),

      // ========================================================
      // BOTTOM NAVIGATION
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
                .withOpacity(0.15),

        destinations: const [
          NavigationDestination(
            icon: Icon(
              Icons.home_outlined,
            ),
            selectedIcon: Icon(
              Icons.home,
              color:
                  AppColors.primary,
            ),
            label: 'Admin Home',
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
              Icons.person_outline,
            ),
            selectedIcon: Icon(
              Icons.person,
              color:
                  AppColors.primary,
            ),
            label: 'Profile',
          ),
        ],
        ),
      ),
    );
  }
}