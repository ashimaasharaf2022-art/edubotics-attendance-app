import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import 'dashboard_screen.dart';
import 'attendance_tab_screen.dart';
import 'services_screen.dart';
import 'profile_screen.dart';
import 'admin_shell.dart';

class EmployeeShell extends StatefulWidget {
  final String employeeId;

  const EmployeeShell({
    super.key,
    required this.employeeId,
  });

  @override
  State<EmployeeShell> createState() =>
      _EmployeeShellState();
}

class _EmployeeShellState extends State<EmployeeShell> {
  int currentIndex = 0;

  String employeeName = "";
  bool hasAdminAccess = false;

  @override
  void initState() {
    super.initState();
    _loadAdminAccess();
  }

  // ============================================================
  // LOAD EMPLOYEE ADMIN ACCESS
  // ============================================================

  Future<void> _loadAdminAccess() async {
    try {
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL:
            "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
      ).ref();

      final snapshot = await dbRef
          .child("users")
          .child(widget.employeeId)
          .get();

      if (!snapshot.exists || snapshot.value is! Map) {
        return;
      }

      final user =
          Map<dynamic, dynamic>.from(
        snapshot.value as Map,
      );

      final role =
          user["role"]
                  ?.toString()
                  .trim()
                  .toLowerCase() ??
              "employee";

      final adminAccess =
          user["adminAccess"] == true;

      final nameValue =
          user["name"]?.toString().trim();

      if (!mounted) return;

      setState(() {
        hasAdminAccess =
            adminAccess || role == "admin";

        if (nameValue != null &&
            nameValue.isNotEmpty) {
          employeeName = nameValue;
        }
      });
    } catch (_) {
      // Keep employee mode if adminAccess
      // cannot be loaded.
    }
  }

  // ============================================================
  // UPDATE EMPLOYEE NAME
  // ============================================================

  void _updateName(String name) {
    if (employeeName != name) {
      setState(() {
        employeeName = name;
      });
    }
  }

  // ============================================================
  // SWITCH TO ADMIN PANEL
  // ============================================================

  void _switchToAdminPanel() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => AdminShell(
          employeeId: widget.employeeId,
          employeeName: employeeName.isEmpty
              ? widget.employeeId
              : employeeName,
          isSuperAdmin: false,
        ),
      ),
    );
  }

  // ============================================================
  // ACTIVE EMPLOYEE TAB
  // ============================================================

  Widget _buildActiveTab(List<Widget> tabs) {
    // Only mount the visible employee screen. This is intentional: hidden
    // screens are not simultaneously inserted into the widget tree, so a
    // GlobalKey owned by a child screen cannot collide with another hidden
    // instance. Flutter requires GlobalKeys to be unique across the tree.
    return tabs[currentIndex];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final displayName = employeeName.isEmpty
        ? widget.employeeId
        : employeeName;

    final tabs = [
      // --------------------------------------------------------
      // HOME / DASHBOARD
      // --------------------------------------------------------

      DashboardScreen(
        employeeId: widget.employeeId,
        onNameLoaded: _updateName,
      ),

      // --------------------------------------------------------
      // ATTENDANCE
      // --------------------------------------------------------

      AttendanceTabScreen(
        employeeId: widget.employeeId,
      ),

      // --------------------------------------------------------
      // SERVICES
      // --------------------------------------------------------

      ServicesScreen(
        employeeId: widget.employeeId,
        employeeName: displayName,
      ),

      // --------------------------------------------------------
      // PROFILE
      // --------------------------------------------------------

      ProfileScreen(
        employeeId: widget.employeeId,
        hasAdminAccess: hasAdminAccess,
        onSwitchToAdminPanel:
            hasAdminAccess
                ? _switchToAdminPanel
                : null,
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
            content: Text("You are on the main dashboard."),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        body: _buildActiveTab(tabs),

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
                .withValues(alpha: 0.15),

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
            label: "Home",
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
            label: "Attendance",
          ),

          NavigationDestination(
            icon: Icon(
              Icons.grid_view_rounded,
            ),
            selectedIcon: Icon(
              Icons.grid_view_rounded,
              color:
                  AppColors.primary,
            ),
            label: "Services",
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
            label: "Profile",
          ),
        ],
        ),
      ),
    );
  }
}