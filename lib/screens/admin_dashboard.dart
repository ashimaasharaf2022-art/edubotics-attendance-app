import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import 'admin_approvals_screen.dart';
import 'admin_payslip_requests_screen.dart';
import 'admin_leave_screen.dart';
import 'announcement_detail_screen.dart';

// Dark palette used only for this screen's hero header, matching the
// employee dashboard, without changing the app's global light theme.
const Color _kAdminHeroDark1 = Color(0xFF0B0F1F);
const Color _kAdminHeroDark2 = Color(0xFF171B3D);

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
  int pendingPayslips = 0;

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

  // Uses the app's real logo asset (same one used on the native splash
  // screen). Falls back to a placeholder icon if the asset isn't bundled
  // yet, so the UI never breaks while the asset is being added.
  Widget _logoMark({double size = 22}) {
    return Image.asset(
      'assets/images/workora_logo.png',
      height: size,
      width: size,
      errorBuilder: (_, __, ___) => Icon(Icons.blur_circular_rounded, color: AppColors.brightBlue, size: size),
    );
  }

  bool _isSuperAdminRole(dynamic userData) {
    final data = Map<dynamic, dynamic>.from(userData as Map);
    return data["role"]?.toString().toLowerCase() == "superadmin";
  }

  Future<void> _loadPendingApprovals() async {
    int otherCount = 0;
    final deviceSnap = await dbRef.child("DeviceApprovalRequests").get();
    if (deviceSnap.exists) {
      final empMap = Map<dynamic, dynamic>.from(deviceSnap.value as Map);
      empMap.forEach((_, requestsMap) {
        final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
        requests.forEach((_, v) {
          final req = Map<dynamic, dynamic>.from(v as Map);
          if (req["status"] == "pending" || req["status"] == "otp_ready") otherCount++;
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
          if (req["status"] == "pending") otherCount++;
        });
      });
    }
    final msgSnap = await dbRef.child("AdminMessages").get();
    if (msgSnap.exists) {
      final msgs = Map<dynamic, dynamic>.from(msgSnap.value as Map);
      msgs.forEach((_, v) {
        final req = Map<dynamic, dynamic>.from(v as Map);
        if (req["status"] != "resolved") otherCount++;
      });
    }

    int payslipCount = 0;
    final paySnap = await dbRef.child("PayslipRequests").get();
    if (paySnap.exists) {
      final empMap = Map<dynamic, dynamic>.from(paySnap.value as Map);
      empMap.forEach((_, requestsMap) {
        final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
        requests.forEach((_, v) {
          final req = Map<dynamic, dynamic>.from(v as Map);
          if (req["status"] == "pending") payslipCount++;
        });
      });
    }
    if (!mounted) return;
    setState(() {
      pendingApprovals = otherCount;
      pendingPayslips = payslipCount;
    });
  }

  Future<void> _loadQuickStats() async {
    setState(() => loading = true);
    try {
      final usersSnap = await dbRef.child("users").get();
      final attendanceSnap = await dbRef.child("Attendance").get();

      int employeeCount = 0;
      final validEmployeeIds = <String>{};
      if (usersSnap.exists) {
        final usersMap = Map<dynamic, dynamic>.from(usersSnap.value as Map);
        usersMap.forEach((id, data) {
          // Super Admin is not an employee — exclude from all counts.
          if (_isSuperAdminRole(data)) return;
          employeeCount++;
          validEmployeeIds.add(id.toString());
        });
      }

      int checkedIn = 0;
      if (attendanceSnap.exists) {
        final today = _todayKey();
        final empMap = Map<dynamic, dynamic>.from(attendanceSnap.value as Map);
        empMap.forEach((empId, dateMap) {
          if (!validEmployeeIds.contains(empId.toString())) return;
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

  Future<void> _publishAnnouncement() async {
    final title = TextEditingController();
    final message = TextEditingController();
    final publish = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Company Announcement'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, decoration: const InputDecoration(labelText: 'Title')),
          const SizedBox(height: 10),
          TextField(controller: message, maxLines: 3, decoration: const InputDecoration(labelText: 'Message')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Publish')),
        ],
      ),
    );
    if (publish != true || title.text.trim().isEmpty || message.text.trim().isEmpty) return;

    await dbRef.child('Announcements').push().set({
      'title': title.text.trim(),
      'message': message.text.trim(),
      'createdBy': widget.employeeId,
      'createdAt': DateTime.now().toIso8601String(),
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement published successfully")));
    _refreshAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kAdminHeroDark1,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: RefreshIndicator(
                onRefresh: _refreshAll,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  children: [
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          Expanded(child: _statGradientCard(Icons.people_alt_rounded, loading ? "--" : "$totalEmployees", "Total Employees", const [AppColors.primary, AppColors.brightBlue])),
                          const SizedBox(width: 12),
                          Expanded(child: _statGradientCard(Icons.verified_rounded, loading ? "--" : "$checkedInToday", "Checked In Today", const [AppColors.indigo, AppColors.violet])),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    _buildQuickActions(),
                    const SizedBox(height: 18),
                    _buildAnnouncementCard(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kAdminHeroDark1, _kAdminHeroDark2])),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _logoMark(),
                  const SizedBox(width: 6),
                  const Text("workora", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppGradients.punchCard),
                    child: Icon(widget.isSuperAdmin ? Icons.shield_rounded : Icons.admin_panel_settings_rounded, color: Colors.white, size: 26),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Welcome,", style: TextStyle(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          "${widget.isSuperAdmin ? "Super Admin" : "Admin"} \u{1F44B}",
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statGradientCard(IconData icon, String value, String label, List<Color> colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.hero,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: Colors.white, size: 18)),
          const SizedBox(height: 18),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Quick Actions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _quickActionCard(
                  Icons.event_available_outlined,
                  "Leave Requests",
                  "Review and approve leave",
                  AppColors.violet,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLeaveScreen(adminId: widget.employeeId, adminName: widget.employeeName ?? widget.employeeId))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickActionCard(
                  Icons.receipt_long_outlined,
                  "Payslip Requests",
                  "Review and issue payslips",
                  AppColors.indigo,
                  () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminPayslipRequestsScreen(adminId: widget.employeeId, adminName: widget.employeeName ?? widget.employeeId)));
                    _loadPendingApprovals();
                  },
                  badge: pendingPayslips > 0 ? "$pendingPayslips" : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _quickActionCard(
                  Icons.mark_chat_unread_outlined,
                  "Other Messages",
                  "Employee messages & requests",
                  AppColors.success,
                  () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => AdminApprovalsScreen(adminId: widget.employeeId, adminName: widget.employeeName ?? widget.employeeId, initialTabIndex: 0)));
                    _loadPendingApprovals();
                  },
                  badge: pendingApprovals > 0 ? "$pendingApprovals" : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickActionCard(
                  Icons.campaign_outlined,
                  "Publish Announcements",
                  "Create and publish updates",
                  AppColors.primary,
                  _publishAnnouncement,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _quickActionCard(IconData icon, String title, String subtitle, Color color, VoidCallback onTap, {String? badge}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(14)), child: Icon(icon, color: color, size: 26)),
                if (badge != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(color: AppColors.danger, borderRadius: BorderRadius.circular(20)),
                    child: Text(badge, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            const SizedBox(height: 3),
            Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle), child: Icon(Icons.arrow_forward_rounded, size: 12, color: color))),
          ],
        ),
      ),
    );
  }

  Widget _buildAnnouncementCard() {
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child('Announcements').limitToLast(1).onValue,
      builder: (context, snapshot) {
        Map<String, dynamic>? data;
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final value = snapshot.data!.snapshot.value;
          if (value is Map) {
            final raw = Map<dynamic, dynamic>.from(value);
            if (raw.isNotEmpty) {
              final entry = raw.entries.first;
              if (entry.value is Map) {
                final item = Map<dynamic, dynamic>.from(entry.value as Map);
                data = {
                  "title": item["title"]?.toString() ?? "Announcement",
                  "message": item["message"]?.toString() ?? "",
                  "createdAt": item["createdAt"]?.toString(),
                };
              }
            }
          }
        }

        final hasAnnouncement = data != null;
        final title = data?["title"]?.toString() ?? "";
        final message = data?["message"]?.toString() ?? "";

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.hero),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.campaign_rounded, color: Colors.white, size: 34),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Company announcement', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    if (hasAnnouncement) ...[
                      Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 5),
                      Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 14),
                      SizedBox(
                        height: 34,
                        child: ElevatedButton(
                          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementDetailScreen(isAdmin: true))),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                          child: const Row(mainAxisSize: MainAxisSize.min, children: [Text("View Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), SizedBox(width: 3), Icon(Icons.chevron_right, size: 15)]),
                        ),
                      ),
                    ] else
                      const Text("No announcements yet!", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
