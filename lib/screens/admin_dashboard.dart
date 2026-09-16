import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import 'admin_approvals_screen.dart';
import 'admin_payslip_requests_screen.dart';
import 'admin_leave_screen.dart';
import 'announcement_detail_screen.dart';
import 'account_settings_screen.dart';
import 'admin_activity_log_screen.dart';
import 'admin_compensation_requests_screen.dart';
import 'manage_admins_screen.dart';
import '../utils/attachment_upload.dart';

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

  Map<dynamic, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<dynamic, dynamic>.from(value);
    return null;
  }

  bool loading = true;
  int totalEmployees = 0;
  int checkedInToday = 0;
  int pendingApprovals = 0;
  int pendingPayslips = 0;
  int pendingCompensation = 0;

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
      errorBuilder: (_, __, ___) => Icon(Icons.blur_circular_rounded, color: AppColors.green, size: size),
    );
  }

  bool _isSuperAdminRole(dynamic userData) {
    final data = _asMap(userData);
    if (data == null) return false;
    return data["role"]?.toString().toLowerCase() == "superadmin";
  }

  /// Pulls together everything the two quick-action badges need:
  /// pendingApprovals (device logins + WFH requests + admin messages +
  /// pending auto-checkout punch requests) and pendingPayslips.
  Future<void> _loadPendingApprovals() async {
    int otherCount = 0;
    int compensationCount = 0;

    final deviceSnap = await dbRef.child("DeviceApprovalRequests").get();
    final deviceMap = _asMap(deviceSnap.value);
    deviceMap?.forEach((_, requestsMap) {
      final requests = _asMap(requestsMap);
      requests?.forEach((_, v) {
        final req = _asMap(v);
        final status = req?["status"]?.toString().toLowerCase();
        if (status == "pending" || status == "otp_ready") otherCount++;
      });
    });

    final wfhSnap = await dbRef.child("WorkFromHomeRequests").get();
    final wfhMap = _asMap(wfhSnap.value);
    wfhMap?.forEach((_, datesMap) {
      final dates = _asMap(datesMap);
      dates?.forEach((_, v) {
        final req = _asMap(v);
        if (req?["status"]?.toString().toLowerCase() == "pending") {
          otherCount++;
        }
      });
    });

    final msgSnap = await dbRef.child("AdminMessages").get();
    final msgMap = _asMap(msgSnap.value);
    msgMap?.forEach((_, v) {
      final req = _asMap(v);
      if (req?["status"]?.toString().toLowerCase() != "resolved") {
        otherCount++;
      }
    });

    final punchSnap = await dbRef.child('PunchRequests').get();
    final punchMap = _asMap(punchSnap.value);
    punchMap?.forEach((_, datesMap) {
      final dates = _asMap(datesMap);
      dates?.forEach((_, value) {
        final request = _asMap(value);
        if (request?['status']?.toString().toLowerCase() == 'pending' &&
            request?['type']?.toString().toLowerCase() == 'mis_punch') {
          otherCount++;
        }
      });
    });

    final compensationSnap = await dbRef.child('CompensationRequests').get();
    final compensationMap = _asMap(compensationSnap.value);
    compensationMap?.forEach((_, requestsMap) {
      final requests = _asMap(requestsMap);
      requests?.forEach((_, value) {
        final request = _asMap(value);
        if (request?['status']?.toString().toLowerCase() == 'pending') {
          compensationCount++;
        }
      });
    });

    int payslipCount = 0;
    final paySnap = await dbRef.child("PayslipRequests").get();
    final payMap = _asMap(paySnap.value);
    payMap?.forEach((_, requestsMap) {
      final requests = _asMap(requestsMap);
      requests?.forEach((_, v) {
        final req = _asMap(v);
        if (req?["status"]?.toString().toLowerCase() == "pending") {
          payslipCount++;
        }
      });
    });

    if (!mounted) return;
    setState(() {
      pendingApprovals = otherCount;
      pendingPayslips = payslipCount;
      pendingCompensation = compensationCount;
    });
  }

  Future<void> _loadQuickStats() async {
    setState(() => loading = true);
    try {
      final usersSnap = await dbRef.child("users").get();
      final attendanceSnap = await dbRef.child("Attendance").get();

      int employeeCount = 0;
      final validEmployeeIds = <String>{};
      final usersMap = _asMap(usersSnap.value);
      usersMap?.forEach((id, data) {
        // Super Admin is not an employee — exclude from all counts.
        if (_isSuperAdminRole(data)) return;
        employeeCount++;
        validEmployeeIds.add(id.toString());
      });

      int checkedIn = 0;
      final attendanceMap = _asMap(attendanceSnap.value);
      if (attendanceMap != null) {
        final today = _todayKey();
        attendanceMap.forEach((_, v) {
          final days = _asMap(v);
          if (days == null || !days.containsKey(today)) return;
          final todayRecord = _asMap(days[today]);
          if (todayRecord == null) return;
          final status = todayRecord["status"]?.toString() ?? "";
          if (status == "Checked In" || status == "Checked Out") {
            checkedIn++;
          }
        });
      }

      if (!mounted) return;
      setState(() {
        totalEmployees = employeeCount;
        checkedInToday = checkedIn;
        loading = false;
      });
    } catch (_) {
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
    UploadedAttachment? attachment;
    bool uploading = false;

    final publish = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (bottomContext) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.campaign_rounded, color: AppColors.primary, size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Publish Announcement',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: title,
                  decoration: InputDecoration(
                    labelText: 'Title *',
                    hintText: 'e.g. Office Holiday Notice',
                    prefixIcon: const Icon(Icons.title),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: message,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: 'Message *',
                    hintText: 'Write your announcement details here...',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Attachment (Optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.textSecondary)),
                const SizedBox(height: 8),
                if (attachment == null) ...[
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: uploading
                              ? null
                              : () async {
                                  setSheetState(() => uploading = true);
                                  try {
                                    final res = await AttachmentUpload.pickAndUploadImage('announcements');
                                    if (res != null) {
                                      setSheetState(() => attachment = res);
                                    }
                                  } catch (err) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to attach image: $err')),
                                    );
                                  } finally {
                                    setSheetState(() => uploading = false);
                                  }
                                },
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: const Text('Add Image'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: uploading
                              ? null
                              : () async {
                                  setSheetState(() => uploading = true);
                                  try {
                                    final res = await AttachmentUpload.pickAndUploadDocument('announcements');
                                    if (res != null) {
                                      setSheetState(() => attachment = res);
                                    }
                                  } catch (err) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('Failed to attach document: $err')),
                                    );
                                  } finally {
                                    setSheetState(() => uploading = false);
                                  }
                                },
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Add Document'),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        if (attachment!.isImage && attachment!.previewBytes != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              attachment!.previewBytes!,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                        else if (attachment!.isImage && attachment!.url.startsWith('data:image/'))
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(attachment!.url.split(',').last),
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                            ),
                          )
                        else
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              attachment!.isImage ? Icons.image : Icons.insert_drive_file,
                              color: AppColors.primary,
                            ),
                          ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment!.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                              const Text('Attached successfully', style: TextStyle(color: AppColors.success, fontSize: 11)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                          tooltip: 'Remove attachment',
                          onPressed: () => setSheetState(() => attachment = null),
                        ),
                      ],
                    ),
                  ),
                ],
                if (uploading) ...[
                  const SizedBox(height: 12),
                  const Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                        SizedBox(width: 10),
                        Text('Uploading attachment...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: uploading
                        ? null
                        : () {
                            if (title.text.trim().isEmpty || message.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Please fill both Title and Message')),
                              );
                              return;
                            }
                            Navigator.pop(context, true);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('PUBLISH ANNOUNCEMENT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (publish != true || title.text.trim().isEmpty || message.text.trim().isEmpty) return;

    try {
      await dbRef.child('Announcements').push().set({
        'title': title.text.trim(),
        'message': message.text.trim(),
        'createdBy': widget.employeeId,
        'createdAt': DateTime.now().toIso8601String(),
        if (attachment != null) 'attachment': attachment!.toMap(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement published successfully")));
      _refreshAll();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to publish announcement: $e")));
    }
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
                          Expanded(child: _statGradientCard(Icons.people_alt_rounded, loading ? "--" : "$totalEmployees", "Total Employees", const [AppColors.primary, AppColors.green])),
                          const SizedBox(width: 12),
                          Expanded(child: _statGradientCard(Icons.verified_rounded, loading ? "--" : "$checkedInToday", "Checked In Today", const [AppColors.info, AppColors.primary])),
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
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AccountSettingsScreen(
                        employeeId: widget.employeeId,
                        isAdminPanel: true,
                      ),
                    ),
                  );
                },
                child: Row(
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
                            "${widget.isSuperAdmin ? "Super Admin" : (widget.employeeName != null && widget.employeeName!.isNotEmpty ? widget.employeeName : "Admin")} \u{1F44B}",
                            style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), shape: BoxShape.circle),
                      child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white70, size: 14),
                    ),
                  ],
                ),
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
                  AppColors.primary,
                  () => Navigator.push(context, MaterialPageRoute(builder: (_) => AdminLeaveScreen(adminId: widget.employeeId, adminName: widget.employeeName ?? widget.employeeId))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _quickActionCard(
                  Icons.receipt_long_outlined,
                  "Payslip Requests",
                  "Review and issue payslips",
                  AppColors.info,
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
                  Icons.schedule_send_rounded,
                  "Compensation Requests",
                  "Review Work-Pending plans",
                  AppColors.warning,
                  () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AdminCompensationRequestsScreen(
                          adminId: widget.employeeId,
                          adminName: widget.employeeName ?? widget.employeeId,
                        ),
                      ),
                    );
                    _loadPendingApprovals();
                  },
                  badge: pendingCompensation > 0 ? "$pendingCompensation" : null,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _quickActionCard(
          Icons.campaign_outlined,
          "Publish Announcements",
          "Create and publish updates",
          AppColors.primary,
          _publishAnnouncement,
        ),
        if (widget.isSuperAdmin) ...[
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _quickActionCard(
                    Icons.manage_accounts_outlined,
                    'Manage Admins',
                    'Grant or revoke admin access',
                    AppColors.warning,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ManageAdminsScreen(
                          superAdminId: widget.employeeId,
                          superAdminName: widget.employeeName ?? widget.employeeId,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _quickActionCard(
                    Icons.history_outlined,
                    'Admin Activity',
                    'Monitor administrative activity',
                    AppColors.info,
                    () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminActivityLogScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
      stream: dbRef.child('Announcements').onValue,
      builder: (context, snapshot) {
        final announcements = <Map<String, String>>[];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final value = snapshot.data!.snapshot.value;
          if (value is Map) {
            final raw = Map<dynamic, dynamic>.from(value);
            raw.forEach((_, value) {
              if (value is Map) {
                final item = Map<dynamic, dynamic>.from(value);
                announcements.add({'title': item['title']?.toString() ?? 'Announcement', 'createdAt': item['createdAt']?.toString() ?? ''});
              }
            });
            announcements.sort((a, b) => b['createdAt']!.compareTo(a['createdAt']!));
          }
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.hero),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [Icon(Icons.campaign_rounded, color: Colors.white, size: 28), SizedBox(width: 10), Text('Announcements', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
            const SizedBox(height: 12),
            if (announcements.isEmpty)
              const Text('No announcements yet!', style: TextStyle(color: Colors.white70))
            else
              ...announcements.map(_adminAnnouncementRow),
          ]),
        );
      },
    );
  }

  Widget _adminAnnouncementRow(Map<String, String> item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white.withOpacity(.14),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementDetailScreen(isAdmin: true))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                const Icon(Icons.article_outlined, color: Colors.white, size: 18),
                const SizedBox(width: 9),
                Expanded(child: Text(item['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
