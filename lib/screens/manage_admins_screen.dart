import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';

/// CEO-only screen for granting/revoking Admin Panel access.
///
/// Super Admin accounts are never included in this list.
///
/// Grant Admin:
///   adminAccess: true
///   role: "admin"
///
/// Remove Admin:
///   adminAccess: false
///   role: "employee"
///
/// This screen can NEVER grant Super Admin access.
class ManageAdminsScreen extends StatefulWidget {
  final String superAdminId;
  final String superAdminName;

  const ManageAdminsScreen({
    super.key,
    required this.superAdminId,
    required this.superAdminName,
  });

  @override
  State<ManageAdminsScreen> createState() =>
      _ManageAdminsScreenState();
}

class _ManageAdminsScreenState
    extends State<ManageAdminsScreen> {
  late final DatabaseReference dbRef;

  bool loading = true;

  String? savingEmployeeId;

  final employees = <_EmployeeAccess>[];

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _load();
  }

  // ============================================================
  // LOAD EMPLOYEES
  // ============================================================

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final snap = await dbRef
          .child('users')
          .get();

      employees.clear();

      if (snap.exists && snap.value is Map) {
        final users =
            Map<dynamic, dynamic>.from(
          snap.value as Map,
        );

        for (final entry in users.entries) {
          if (entry.value is! Map) {
            continue;
          }

          final data =
              Map<dynamic, dynamic>.from(
            entry.value as Map,
          );

          final keyId =
              entry.key.toString();

          final storedId =
              data['employeeId']
                  ?.toString()
                  .trim();

          final employeeId =
              storedId == null ||
                      storedId.isEmpty
                  ? keyId
                  : storedId;

          final role =
              data['role']
                      ?.toString()
                      .trim()
                      .toLowerCase() ??
                  'employee';

          // ----------------------------------------------------
          // NEVER SHOW SUPER ADMIN / CEO
          // ----------------------------------------------------

          if (role == 'superadmin') {
            continue;
          }

          // ----------------------------------------------------
          // ADMIN ACCESS
          // ----------------------------------------------------

          final adminAccess =
              data['adminAccess'] == true ||
              role == 'admin';

          // ----------------------------------------------------
          // ACCOUNT STATUS
          // ----------------------------------------------------

          final status =
              data['status']
                      ?.toString()
                      .trim()
                      .toLowerCase() ??
                  'active';

          final active =
              status != 'inactive';

          final rawName =
              data['name']
                      ?.toString()
                      .trim() ??
                  '';

          final name =
              rawName.isEmpty
                  ? employeeId
                  : rawName;

          final designation =
              data['designation']
                      ?.toString()
                      .trim() ??
                  '';

          employees.add(
            _EmployeeAccess(
              employeeId: employeeId,
              name: name,
              designation: designation,
              adminAccess: adminAccess,
              active: active,
            ),
          );
        }
      }

      // --------------------------------------------------------
      // SORT BY EMPLOYEE ID
      // --------------------------------------------------------

      employees.sort(
        (a, b) => a.employeeId.compareTo(
          b.employeeId,
        ),
      );

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _message(
        'Could not load employees: $e',
      );
    }
  }

  // ============================================================
  // TOGGLE ADMIN ACCESS
  // ============================================================

  Future<void> _toggle(
    _EmployeeAccess employee,
    bool value,
  ) async {
    if (savingEmployeeId != null) {
      return;
    }

    setState(() {
      savingEmployeeId =
          employee.employeeId;
    });

    try {
      final employeeRef = dbRef
          .child('users')
          .child(employee.employeeId);

      // --------------------------------------------------------
      // GRANT ADMIN ACCESS
      // --------------------------------------------------------

      if (value) {
        await employeeRef.update({
          'adminAccess': true,
          'role': 'admin',
        });
      }

      // --------------------------------------------------------
      // REMOVE ADMIN ACCESS
      // --------------------------------------------------------

      else {
        await employeeRef.update({
          'adminAccess': false,
          'role': 'employee',
        });
      }

      employee.adminAccess = value;

      if (!mounted) return;

      setState(() {
        savingEmployeeId = null;
      });

      if (value) {
        _message(
          '${employee.name} can access the Admin Panel now.',
        );
      } else {
        _message(
          '${employee.name} no longer has Admin Panel access.',
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        savingEmployeeId = null;
      });

      _message(
        'Could not change admin access: $e',
      );
    }
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Manage Admin Access',
        ),
      ),

      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,

              child: employees.isEmpty
                  ? ListView(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      children: const [
                        SizedBox(height: 160),
                        Center(
                          child: Text(
                            'No employee accounts found.',
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      physics:
                          const AlwaysScrollableScrollPhysics(),
                      padding:
                          const EdgeInsets.all(16),
                      itemCount:
                          employees.length,

                      separatorBuilder:
                          (_, _) =>
                              const SizedBox(
                        height: 10,
                      ),

                      itemBuilder:
                          (_, index) {
                        final employee =
                            employees[index];

                        final busy =
                            savingEmployeeId ==
                                employee.employeeId;

                        return Container(
                          padding:
                              const EdgeInsets.all(16),

                          decoration:
                              BoxDecoration(
                            color:
                                AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(
                              16,
                            ),
                            boxShadow:
                                AppShadows.card,
                          ),

                          child: Row(
                            children: [
                              // --------------------------------
                              // AVATAR
                              // --------------------------------

                              CircleAvatar(
                                backgroundColor:
                                    AppColors
                                        .primary
                                        .withValues(
                                  alpha: .10,
                                ),

                                child: Text(
                                  employee.name
                                          .isEmpty
                                      ? '?'
                                      : employee
                                          .name[0]
                                          .toUpperCase(),

                                  style:
                                      const TextStyle(
                                    color:
                                        AppColors
                                            .primary,
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                  ),
                                ),
                              ),

                              const SizedBox(
                                width: 12,
                              ),

                              // --------------------------------
                              // EMPLOYEE DETAILS
                              // --------------------------------

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    Text(
                                      employee.name,

                                      style:
                                          const TextStyle(
                                        fontWeight:
                                            FontWeight
                                                .w800,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 3,
                                    ),

                                    Text(
                                      employee
                                              .designation
                                              .isEmpty
                                          ? employee
                                              .employeeId
                                          : '${employee.employeeId} • ${employee.designation}',

                                      style:
                                          const TextStyle(
                                        color:
                                            AppColors
                                                .textSecondary,
                                        fontSize: 12,
                                      ),
                                    ),

                                    const SizedBox(
                                      height: 5,
                                    ),

                                    Text(
                                      employee
                                              .adminAccess
                                          ? 'Admin Panel access enabled'
                                          : 'Employee access only',

                                      style:
                                          TextStyle(
                                        color: employee
                                                .adminAccess
                                            ? AppColors
                                                .primary
                                            : AppColors
                                                .textSecondary,
                                        fontSize: 11,
                                        fontWeight:
                                            FontWeight
                                                .w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              // --------------------------------
                              // SWITCH / LOADING
                              // --------------------------------

                              if (busy)
                                const SizedBox(
                                  width: 24,
                                  height: 24,

                                  child:
                                      CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              else
                                Switch(
                                  value:
                                      employee
                                          .adminAccess,

                                  onChanged:
                                      employee.active
                                          ? (value) =>
                                              _toggle(
                                                employee,
                                                value,
                                              )
                                          : null,
                                ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

// ================================================================
// EMPLOYEE ACCESS MODEL
// ================================================================

class _EmployeeAccess {
  final String employeeId;
  final String name;
  final String designation;

  bool adminAccess;

  final bool active;

  _EmployeeAccess({
    required this.employeeId,
    required this.name,
    required this.designation,
    required this.adminAccess,
    required this.active,
  });
}