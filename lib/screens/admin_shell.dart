import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/leave_badge_icon.dart';
import 'admin_dashboard.dart';
import 'employees_tab_screen.dart';
import 'admin_leave_screen.dart';
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

    final tabs = [
      AdminDashboard(employeeId: widget.employeeId, employeeName: widget.employeeName, isSuperAdmin: widget.isSuperAdmin),
      EmployeesTabScreen(adminId: widget.employeeId, adminName: adminName),
      AdminLeaveScreen(adminId: widget.employeeId, adminName: adminName),
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
          const NavigationDestination(icon: Icon(Icons.people_outline), selectedIcon: Icon(Icons.people, color: AppColors.primary), label: "Employees"),
          NavigationDestination(
            icon: const LeaveBadgeIcon(icon: Icon(Icons.event_note_outlined)),
            selectedIcon: const LeaveBadgeIcon(icon: Icon(Icons.event_note, color: AppColors.primary)),
            label: "Leave",
          ),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: "Profile"),
        ],
      ),
    );
  }
}