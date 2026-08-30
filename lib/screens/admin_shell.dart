import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import 'admin_dashboard.dart';
import 'admin_attendance_screen.dart';
import 'reports_screen.dart';
import 'profile_screen.dart';

class AdminShell extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final bool isSuperAdmin;

  const AdminShell({super.key, required this.employeeId, this.employeeName, this.isSuperAdmin = false});

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  int currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final adminName = widget.employeeName ?? widget.employeeId;

    final List<Widget> tabs = [
      AdminDashboard(employeeId: widget.employeeId, employeeName: widget.employeeName, isSuperAdmin: widget.isSuperAdmin),
      AdminAttendanceScreen(adminId: widget.employeeId, adminName: adminName),
      const ReportsScreen(),
      ProfileScreen(employeeId: widget.employeeId, isAdmin: true, isSuperAdmin: widget.isSuperAdmin),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => setState(() => currentIndex = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: "Home"),
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary), label: "Attendance"),
          const NavigationDestination(icon: Icon(Icons.analytics_outlined), selectedIcon: Icon(Icons.analytics, color: AppColors.primary), label: "Reports"),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: "Profile"),
        ],
      ),
    );
  }
}
