import 'package:flutter/material.dart';

import 'admin_dashboard.dart';

/// Separate dashboard screen/route for the CEO / Super Admin.
///
/// The CEO is not treated as an employee.
/// Existing admin dashboard functionality is reused,
/// while `isSuperAdmin: true` tells AdminDashboard that
/// the current user has Super Admin permissions.
class SuperAdminDashboard extends StatelessWidget {
  final String superAdminId;
  final String? superAdminName;

  const SuperAdminDashboard({
    super.key,
    required this.superAdminId,
    this.superAdminName,
  });

  @override
  Widget build(BuildContext context) {
    return AdminDashboard(
      employeeId: superAdminId,
      employeeName: superAdminName,
      isSuperAdmin: true,
    );
  }
}