import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/activity_logger.dart';

class ManageAdminsScreen extends StatefulWidget {
  final String superAdminId;
  final String superAdminName;

  const ManageAdminsScreen({
    super.key,
    required this.superAdminId,
    required this.superAdminName,
  });

  @override
  State<ManageAdminsScreen> createState() => _ManageAdminsScreenState();
}

class _ManageAdminsScreenState extends State<ManageAdminsScreen> {
  late DatabaseReference dbRef;
  String searchQuery = "";

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  Future<void> _toggleAdminAccess(String employeeId, String name, bool newValue) async {
    await dbRef.child("users").child(employeeId).update({"adminAccess": newValue});

    await ActivityLogger.log(
      adminId: widget.superAdminId,
      adminName: widget.superAdminName,
      action: newValue ? "Granted Admin Access" : "Revoked Admin Access",
      details: "$name ($employeeId)",
    );
  }

  Future<void> _confirmToggle(String employeeId, String name, bool newValue) async {
    if (!newValue) {
      // Revoking is destructive to their current admin session, confirm first.
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text("Revoke Admin Access"),
          content: Text("$name will no longer be able to switch into the Admin Panel."),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text("Revoke"),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    await _toggleAdminAccess(employeeId, name, newValue);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Grant Admin Access", style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: InputDecoration(
                hintText: "Search employee by name or ID",
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: AppColors.surface,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              ),
              onChanged: (v) => setState(() => searchQuery = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: dbRef.child("users").onValue,
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                  return const Center(child: CircularProgressIndicator());
                }

                final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
                final employees = <MapEntry<String, Map<dynamic, dynamic>>>[];

                data.forEach((id, value) {
                  final user = Map<dynamic, dynamic>.from(value as Map);
                  final role = user["role"]?.toString().toLowerCase();
                  // Only real employee accounts can be granted admin
                  // access \u2014 super admin itself is a separate fixed role.
                  if (role != "employee") return;

                  final name = (user["name"]?.toString() ?? "").toLowerCase();
                  final idLower = id.toString().toLowerCase();
                  if (searchQuery.isNotEmpty &&
                      !name.contains(searchQuery) &&
                      !idLower.contains(searchQuery)) {
                    return;
                  }

                  employees.add(MapEntry(id.toString(), user));
                });

                employees.sort((a, b) =>
                    (a.value["name"]?.toString() ?? a.key).compareTo(b.value["name"]?.toString() ?? b.key));

                if (employees.isEmpty) {
                  return const Center(child: Text("No matching employees"));
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: employees.length,
                  itemBuilder: (context, index) {
                    final id = employees[index].key;
                    final user = employees[index].value;
                    final name = user["name"]?.toString() ?? id;
                    final department = user["department"]?.toString();
                    final hasAccess = user["adminAccess"] == true;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: AppShadows.card,
                        border: hasAccess ? Border.all(color: AppColors.success.withOpacity(0.4)) : null,
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: (hasAccess ? AppColors.success : AppColors.primary).withOpacity(0.15),
                            child: Icon(
                              hasAccess ? Icons.admin_panel_settings : Icons.person,
                              color: hasAccess ? AppColors.success : AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text(id, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                if (department != null && department.isNotEmpty)
                                  Text(department, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                if (hasAccess)
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2),
                                    child: Text(
                                      "Has Admin Access",
                                      style: TextStyle(color: AppColors.success, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Switch(
                            value: hasAccess,
                            activeColor: AppColors.success,
                            onChanged: (value) => _confirmToggle(id, name, value),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}