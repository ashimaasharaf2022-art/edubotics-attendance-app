import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import 'dashboard_screen.dart';
import 'history_screen.dart';
import 'personal_report_screen.dart';
import 'profile_screen.dart';

class EmployeeShell extends StatefulWidget {
  final String employeeId;

  const EmployeeShell({super.key, required this.employeeId});

  @override
  State<EmployeeShell> createState() => _EmployeeShellState();
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

  Future<void> _loadAdminAccess() async {
    try {
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
      ).ref();
      final snapshot = await dbRef.child("users").child(widget.employeeId).child("adminAccess").get();
      if (!mounted) return;
      setState(() => hasAdminAccess = snapshot.exists && snapshot.value == true);
    } catch (_) {}
  }

  void _updateName(String name) {
    if (employeeName != name) setState(() => employeeName = name);
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      DashboardScreen(employeeId: widget.employeeId, onNameLoaded: _updateName),
      HistoryScreen(employeeId: widget.employeeId, employeeName: employeeName.isEmpty ? widget.employeeId : employeeName),
      PersonalReportScreen(employeeId: widget.employeeId),
      ProfileScreen(employeeId: widget.employeeId, hasAdminAccess: hasAdminAccess),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: tabs),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentIndex,
        onDestinationSelected: (i) => setState(() => currentIndex = i),
        backgroundColor: AppColors.surface,
        indicatorColor: AppColors.primary.withOpacity(0.15),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home, color: AppColors.primary), label: "Home"),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month, color: AppColors.primary), label: "Attendance"),
          NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description, color: AppColors.primary), label: "Reports"),
          NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person, color: AppColors.primary), label: "Profile"),
        ],
      ),
    );
  }
}