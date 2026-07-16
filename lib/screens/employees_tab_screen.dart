import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/activity_logger.dart';
import 'add_employee_screen.dart';
import 'profile_screen.dart';
import 'history_screen.dart';

class EmployeesTabScreen extends StatefulWidget {
  final String adminId;
  final String adminName;

  const EmployeesTabScreen({
    super.key,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<EmployeesTabScreen> createState() => _EmployeesTabScreenState();
}

class _EmployeesTabScreenState extends State<EmployeesTabScreen> {
  late DatabaseReference dbRef;
  bool showToday = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  String _todayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  String _normalizedRole(dynamic rawRole) {
    final role = rawRole?.toString().toLowerCase();
    if (role == "superadmin") return "Super Admin";
    return "Employee";
  }

  Future<void> _confirmDelete(String id, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Employee"),
        content: Text("Remove $name ($id)? Attendance history will be kept."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await dbRef.child("users").child(id).remove();

      await ActivityLogger.log(
        adminId: widget.adminId,
        adminName: widget.adminName,
        action: "Deleted Employee",
        details: "$name ($id)",
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name removed")));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error : $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Employees",
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: AppShadows.card,
                      ),
                      child: Row(
                        children: [
                          _toggleChip("List", !showToday, () => setState(() => showToday = false)),
                          _toggleChip("Today", showToday, () => setState(() => showToday = true)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: showToday ? _buildTodayOverview() : _buildEmployeeList()),
            ],
          ),
        ),
      ),
      floatingActionButton: showToday
          ? null
          : FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.person_add, color: Colors.white),
              label: const Text("Add", style: TextStyle(color: Colors.white)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
              ),
            ),
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.textSecondary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmployeeList() {
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child("users").onValue,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("No Employees Found"));
        }

        final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final ids = data.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final id = ids[index];
            final employee = Map<dynamic, dynamic>.from(data[id]);
            if (employee["role"]?.toString().toLowerCase() == "superadmin") {
  return const SizedBox.shrink();
}
            final name = employee["name"]?.toString() ?? "No Name";
            final hasAdminAccess = employee["adminAccess"] == true;

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.card,
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: AppColors.primary,
                  child: Icon(
                    hasAdminAccess ? Icons.admin_panel_settings : Icons.person,
                    color: Colors.white,
                  ),
                ),
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  "$id \u00b7 ${_normalizedRole(employee["role"])}"
                  "${hasAdminAccess ? ' \u00b7 Admin Access' : ''}",
                ),
                trailing: PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {
                    if (value == "profile") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(employeeId: id, viewOnly: true),
                        ),
                      );
                    } else if (value == "history") {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(employeeId: id, employeeName: name),
                        ),
                      );
                    } else if (value == "delete") {
                      _confirmDelete(id, name);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: "profile",
                      child: Row(children: [Icon(Icons.person, size: 18), SizedBox(width: 8), Text("View Profile")]),
                    ),
                    PopupMenuItem(
                      value: "history",
                      child: Row(children: [Icon(Icons.history, size: 18), SizedBox(width: 8), Text("History")]),
                    ),
                    PopupMenuItem(
                      value: "delete",
                      child: Row(children: [
                        Icon(Icons.delete, size: 18, color: AppColors.danger),
                        SizedBox(width: 8),
                        Text("Delete", style: TextStyle(color: AppColors.danger)),
                      ]),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildTodayOverview() {
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child("users").onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: CircularProgressIndicator());
        }
        final users = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final ids = users.keys.toList();

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          itemCount: ids.length,
          itemBuilder: (context, index) {
            final id = ids[index];
            final user = Map<dynamic, dynamic>.from(users[id]);
            if (user["role"]?.toString().toLowerCase() == "superadmin") {
  return const SizedBox.shrink();
}

            return StreamBuilder<DatabaseEvent>(
              stream: dbRef.child("Attendance").child(id).child(_todayKey()).onValue,
              builder: (context, attendanceSnapshot) {
                String status = "Not Checked In";
                String inTime = "--", outTime = "--";

                if (attendanceSnapshot.hasData && attendanceSnapshot.data!.snapshot.value != null) {
                  final att = Map<dynamic, dynamic>.from(attendanceSnapshot.data!.snapshot.value as Map);
                  status = att["status"] ?? "Not Checked In";
                  inTime = att["punchIn"] ?? "--";
                  outTime = att["punchOut"] ?? "--";
                }

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: AppShadows.card,
                  ),
                  child: Row(
                    children: [
                      const CircleAvatar(
                        backgroundColor: AppColors.primary,
                        child: Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text("${user["name"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text("In: $inTime  Out: $outTime", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (status == "Checked Out" ? AppColors.success : AppColors.warning).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status,
                          style: TextStyle(
                            color: status == "Checked Out" ? AppColors.success : AppColors.warning,
                            fontWeight: FontWeight.bold,
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}