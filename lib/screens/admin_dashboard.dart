import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import 'admin_approvals_screen.dart';
import 'reports_screen.dart';

class AdminDashboard extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final bool isSuperAdmin;

  const AdminDashboard({super.key, required this.employeeId, this.employeeName, this.isSuperAdmin = false});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late DatabaseReference dbRef;

  bool loading = true;
  int totalEmployees = 0;
  int checkedInToday = 0;
  int pendingApprovals = 0;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadQuickStats();
    _loadPendingApprovals();
  }

  String _todayKey() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  Future<void> _loadPendingApprovals() async {
    int count = 0;
    final deviceSnap = await dbRef.child("DeviceApprovalRequests").get();
    if (deviceSnap.exists) {
      final empMap = Map<dynamic, dynamic>.from(deviceSnap.value as Map);
      empMap.forEach((_, requestsMap) {
        final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
        requests.forEach((_, v) {
          final req = Map<dynamic, dynamic>.from(v as Map);
          if (req["status"] == "pending" || req["status"] == "otp_ready") count++;
        });
      });
    }
    final wfhSnap = await dbRef.child("WorkFromHomeRequests").get();
    if (wfhSnap.exists) {
      final empMap = Map<dynamic, dynamic>.from(wfhSnap.value as Map);
      empMap.forEach((_, datesMap) {
        final dates = Map<dynamic, dynamic>.from(datesMap as Map);
        dates.forEach((_, v) {
          final req = Map<dynamic, dynamic>.from(v as Map);
          if (req["status"] == "pending") count++;
        });
      });
    }
    if (!mounted) return;
    setState(() => pendingApprovals = count);
  }

  Future<void> _loadQuickStats() async {
    setState(() => loading = true);
    try {
      final usersSnap = await dbRef.child("users").get();
      final attendanceSnap = await dbRef.child("Attendance").get();

      int employeeCount = 0;
      if (usersSnap.exists) {
        employeeCount = Map<dynamic, dynamic>.from(usersSnap.value as Map).length;
      }

      int checkedIn = 0;
      if (attendanceSnap.exists) {
        final today = _todayKey();
        final empMap = Map<dynamic, dynamic>.from(attendanceSnap.value as Map);
        empMap.forEach((empId, dateMap) {
          final dates = Map<dynamic, dynamic>.from(dateMap as Map);
          if (dates.containsKey(today)) {
            final record = Map<dynamic, dynamic>.from(dates[today] as Map);
            if (record["punchIn"] != null) checkedIn++;
          }
        });
      }

      if (!mounted) return;
      setState(() {
        totalEmployees = employeeCount;
        checkedInToday = checkedIn;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _refreshAll() async {
    await _loadQuickStats();
    await _loadPendingApprovals();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: Colors.white24,
                    child: Icon(widget.isSuperAdmin ? Icons.shield : Icons.admin_panel_settings, color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Text(
                    widget.isSuperAdmin ? "Welcome, Super Admin" : "Welcome, Admin",
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        Expanded(child: _statCard(Icons.people, loading ? "--" : "$totalEmployees", "Total Employees", AppColors.info)),
                        const SizedBox(width: 12),
                        Expanded(child: _statCard(Icons.check_circle, loading ? "--" : "$checkedInToday", "Checked In Today", AppColors.success)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _linkTile(
                      Icons.verified_user,
                      "Pending Approvals",
                      pendingApprovals > 0 ? "$pendingApprovals" : null,
                      AppColors.danger,
                      () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AdminApprovalsScreen(adminId: widget.employeeId, adminName: widget.employeeName ?? widget.employeeId),
                          ),
                        );
                        _loadPendingApprovals();
                      },
                    ),
                    const SizedBox(height: 12),
                    _linkTile(Icons.bar_chart, "Company Reports", null, AppColors.primary, () {
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen()));
                    }),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCard(IconData icon, String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(height: 10),
          Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _linkTile(IconData icon, String title, String? badge, Color badgeColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
        child: Row(
          children: [
            Icon(icon, color: badge != null ? badgeColor : AppColors.textSecondary),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold))),
            if (badge != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: badgeColor, borderRadius: BorderRadius.circular(20)),
                child: Text(badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, color: AppColors.textSecondary),
          ],
        ),
      ),
    );
  }
}