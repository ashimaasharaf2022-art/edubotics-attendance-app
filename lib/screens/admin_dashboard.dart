import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/attachment_upload.dart';
import 'add_employee_screen.dart';
import 'admin_activity_log_screen.dart';
import 'admin_approvals_screen.dart';
import 'admin_attendance_screen.dart';
import 'admin_compensation_requests_screen.dart';
import 'admin_leave_screen.dart';
import 'admin_message_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_payslip_requests_screen.dart';
import 'announcement_detail_screen.dart';
import 'manage_admins_screen.dart';
import 'profile_screen.dart';
import 'reports_screen.dart';

/// Admin Home only.
///
/// IMPORTANT:
/// - This file intentionally does not create a bottom navigation bar.
///   AdminShell owns the Admin Home / Attendance / Reports / Profile navigation.
/// - This screen listens to the existing Firebase Realtime Database nodes.
/// - Employee-side screens are not modified by this implementation.
class AdminDashboard extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final bool isSuperAdmin;

  const AdminDashboard({
    super.key,
    required this.employeeId,
    this.employeeName,
    this.isSuperAdmin = false,
  });

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  late final DatabaseReference _db;
  final List<StreamSubscription<DatabaseEvent>> _subscriptions = [];

  bool _loading = true;
  bool _hasUnreadNotification = false;

  int _totalEmployees = 0;
  int _checkedInToday = 0;

  int _leaveRequests = 0;
  int _wfhRequests = 0;
  int _punchRequests = 0;
  int _supportTickets = 0;
  int _adminMessages = 0;
  int _deviceApprovals = 0;
  int _compensationRequests = 0;
  int _pendingPayslips = 0;
  int _documentRequests = 0;

  final Set<String> _employeeIds = <String>{};
  List<String> _pendingLeaveNames = [];

  int get _absentToday => _totalEmployees > _checkedInToday
      ? _totalEmployees - _checkedInToday
      : 0;

  int get _pendingApprovals =>
      _leaveRequests +
      _wfhRequests +
      _punchRequests +
      _supportTickets +
      _adminMessages +
      _deviceApprovals +
      _compensationRequests +
      _documentRequests;

  int get _attentionCount => _pendingApprovals;

  @override
  void initState() {
    super.initState();

    _db = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _startRealtimeListeners();
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // REAL-TIME DATABASE
  // ---------------------------------------------------------------------------

  void _startRealtimeListeners() {
    _listenToUsers();
    _listenToAttendance();

    _listenToLeaveRequests();
    _listenToWorkFromHomeRequests();
    _listenToPunchRequests();
    _listenToHelpdeskRequests();
    _listenToAdminMessages();
    _listenToDeviceApprovals();
    _listenToCompensationRequests();
    _listenToPayslipRequests();
    _listenToDocumentRequests();
    _listenToNotifications();
  }

  void _listenToUsers() {
    final subscription = _db.child('users').onValue.listen((event) {
      final value = _asMap(event.snapshot.value);
      int count = 0;
      final employeeIds = <String>{};

      value?.forEach((id, rawUser) {
        final user = _asMap(rawUser);
        if (user == null) return;

        final role = user['role']?.toString().trim().toLowerCase();
        if (role == 'superadmin') return;

        count++;
        employeeIds.add(id.toString());
      });

      if (!mounted) return;
      setState(() {
        _totalEmployees = count;
        _employeeIds
          ..clear()
          ..addAll(employeeIds);
        _loading = false;
      });
    });

    _subscriptions.add(subscription);
  }

  void _listenToAttendance() {
    final subscription = _db.child('Attendance').onValue.listen((event) {
      final value = _asMap(event.snapshot.value);
      final today = _todayKey();
      int checkedIn = 0;

      if (_employeeIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _checkedInToday = 0;
          _loading = false;
        });
        return;
      }

      value?.forEach((employeeId, rawEmployee) {
        if (!_employeeIds.contains(employeeId.toString())) {
          return;
        }

        final employee = _asMap(rawEmployee);
        if (employee == null) return;

        final todayRecord = _asMap(employee[today]);
        if (todayRecord == null) return;

        final status = todayRecord['status']?.toString().trim().toLowerCase();
        final punchIn = todayRecord['punchIn'];

        // Both Checked In and Checked Out mean the employee attended today.
        if ((status == 'checked in' || status == 'checked out') ||
            (punchIn != null && punchIn.toString().trim().isNotEmpty)) {
          checkedIn++;
        }
      });

      if (!mounted) return;
      setState(() {
        _checkedInToday = checkedIn;
        _loading = false;
      });
    });

    _subscriptions.add(subscription);
  }

  void _listenToLeaveRequests() {
    final subscription = _db.child('LeaveRequests').onValue.listen((event) {
      final pendingNames = <String>[];
      int count = 0;
      final root = _asMap(event.snapshot.value);

      root?.forEach((_, rawRequests) {
        final requests = _asMap(rawRequests);
        requests?.forEach((_, rawRequest) {
          final request = _asMap(rawRequest);
          if (!_isPending(request)) return;

          count++;
          final name = _requestEmployeeName(request);
          if (name.isNotEmpty && !pendingNames.contains(name)) {
            pendingNames.add(name);
          }
        });
      });

      if (!mounted) return;
      setState(() {
        _leaveRequests = count;
        _pendingLeaveNames = pendingNames.take(3).toList();
        _loading = false;
      });
    });

    _subscriptions.add(subscription);
  }

  void _listenToWorkFromHomeRequests() {
    final subscription = _db.child('WorkFromHomeRequests').onValue.listen((event) {
      final count = _countPendingNested(event.snapshot.value);
      _setIfMounted(() => _wfhRequests = count);
    });

    _subscriptions.add(subscription);
  }

  void _listenToPunchRequests() {
    final subscription = _db.child('PunchRequests').onValue.listen((event) {
      int count = 0;
      final root = _asMap(event.snapshot.value);

      root?.forEach((_, rawDates) {
        final dates = _asMap(rawDates);
        dates?.forEach((_, rawRequest) {
          final request = _asMap(rawRequest);
          final status = request?['status']?.toString().trim().toLowerCase();
          final type = request?['type']?.toString().trim().toLowerCase();

          if (status == 'pending' &&
              (type == 'mis_punch' || type == 'mispunch')) {
            count++;
          }
        });
      });

      _setIfMounted(() => _punchRequests = count);
    });

    _subscriptions.add(subscription);
  }

  void _listenToHelpdeskRequests() {
    final subscription = _db.child('HelpdeskRequests').onValue.listen((event) {
      int count = 0;
      final root = _asMap(event.snapshot.value);

      root?.forEach((_, rawRequests) {
        final requests = _asMap(rawRequests);
        requests?.forEach((_, rawRequest) {
          final request = _asMap(rawRequest);
          if (request == null) return;

          final department =
              request['department']?.toString().trim().toLowerCase();
          final status = request['status']?.toString().trim().toLowerCase();

          if (department == 'managerial team' && status == 'pending') {
            count++;
          }
        });
      });

      _setIfMounted(() => _supportTickets = count);
    });

    _subscriptions.add(subscription);
  }

  void _listenToAdminMessages() {
    final subscription = _db.child('AdminMessages').onValue.listen((event) {
      int count = 0;
      final root = _asMap(event.snapshot.value);

      root?.forEach((_, rawMessage) {
        final message = _asMap(rawMessage);
        if (message == null) return;

        final status = message['status']?.toString().trim().toLowerCase();
        if (status != 'resolved') count++;
      });

      _setIfMounted(() => _adminMessages = count);
    });

    _subscriptions.add(subscription);
  }

  void _listenToDeviceApprovals() {
    final subscription =
        _db.child('DeviceApprovalRequests').onValue.listen((event) {
      int count = 0;
      final root = _asMap(event.snapshot.value);

      root?.forEach((_, rawRequests) {
        final requests = _asMap(rawRequests);
        requests?.forEach((_, rawRequest) {
          final request = _asMap(rawRequest);
          final status = request?['status']?.toString().trim().toLowerCase();
          if (status == 'pending' || status == 'otp_ready') count++;
        });
      });

      _setIfMounted(() => _deviceApprovals = count);
    });

    _subscriptions.add(subscription);
  }

  void _listenToCompensationRequests() {
    final subscription =
        _db.child('CompensationRequests').onValue.listen((event) {
      _setIfMounted(
        () => _compensationRequests =
            _countPendingNested(event.snapshot.value),
      );
    });

    _subscriptions.add(subscription);
  }

  void _listenToPayslipRequests() {
    final subscription = _db.child('PayslipRequests').onValue.listen((event) {
      _setIfMounted(
        () => _pendingPayslips = _countPendingNested(event.snapshot.value),
      );
    });

    _subscriptions.add(subscription);
  }

  void _listenToDocumentRequests() {
    final subscription = _db.child('DocumentRequests').onValue.listen((event) {
      _setIfMounted(
        () => _documentRequests = _countPendingNested(event.snapshot.value),
      );
    });

    _subscriptions.add(subscription);
  }

  void _listenToNotifications() {
    // AdminNotifications is the admin notification node used by the project.
    // Notifications is also checked for compatibility with existing data.
    StreamSubscription<DatabaseEvent>? adminSub;
    StreamSubscription<DatabaseEvent>? genericSub;

    adminSub = _db.child('AdminNotifications').onValue.listen((event) {
      final unread = _countUnread(event.snapshot.value);
      _setIfMounted(() => _hasUnreadNotification = unread > 0);
    });

    genericSub = _db.child('Notifications').onValue.listen((event) {
      final unread = _countUnread(event.snapshot.value);
      if (unread > 0) {
        _setIfMounted(() => _hasUnreadNotification = true);
      }
    });

    _subscriptions.add(adminSub);
    _subscriptions.add(genericSub);
  }

  // ---------------------------------------------------------------------------
  // DATA HELPERS
  // ---------------------------------------------------------------------------

  Map<dynamic, dynamic>? _asMap(dynamic value) {
    if (value is Map) return Map<dynamic, dynamic>.from(value);
    return null;
  }

  bool _isPending(Map<dynamic, dynamic>? data) {
    final status = data?['status']?.toString().trim().toLowerCase();
    return status == 'pending';
  }

  int _countPendingNested(dynamic value) {
    int count = 0;

    void walk(dynamic data) {
      if (data is Map) {
        final map = Map<dynamic, dynamic>.from(data);
        final status = map['status']?.toString().trim().toLowerCase();
        if (status == 'pending') {
          count++;
          return;
        }
        for (final child in map.values) {
          walk(child);
        }
      } else if (data is List) {
        for (final child in data) {
          walk(child);
        }
      }
    }

    walk(value);
    return count;
  }

  int _countPendingFlatOrNested(dynamic value) {
    return _countPendingNested(value);
  }

  int _countUnread(dynamic value) {
    int count = 0;

    void walk(dynamic data) {
      if (data is Map) {
        final map = Map<dynamic, dynamic>.from(data);
        final read = map['read'];
        final isRead = map['isRead'];
        final status = map['status']?.toString().trim().toLowerCase();

        if (read == false || isRead == false || status == 'unread') {
          count++;
          return;
        }

        for (final child in map.values) {
          walk(child);
        }
      } else if (data is List) {
        for (final child in data) {
          walk(child);
        }
      }
    }

    walk(value);
    return count;
  }

  String _requestEmployeeName(Map<dynamic, dynamic>? request) {
    final value = request?['employeeName'] ??
        request?['name'] ??
        request?['employee'] ??
        request?['employeeId'];
    return value?.toString().trim() ?? '';
  }

  void _setIfMounted(VoidCallback callback) {
    if (!mounted) return;
    setState(callback);
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _firstName() {
    final name = (widget.employeeName ?? widget.employeeId).trim();
    if (name.isEmpty) return 'Admin';
    return name.split(RegExp(r'\s+')).first;
  }

  String _roleName() => widget.isSuperAdmin ? 'Super Admin' : 'General Manager';

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  String _weekdayShort() {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[DateTime.now().weekday - 1];
  }

  String _monthShort() {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return months[DateTime.now().month - 1];
  }

  // ---------------------------------------------------------------------------
  // NAVIGATION
  // ---------------------------------------------------------------------------

  String get _adminName => widget.employeeName ?? widget.employeeId;

  void _openNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminNotificationsScreen()),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          employeeId: widget.employeeId,
          isAdmin: true,
          isSuperAdmin: widget.isSuperAdmin,
        ),
      ),
    );
  }

  void _openLeaveRequests() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminLeaveScreen(
          adminId: widget.employeeId,
          adminName: _adminName,
        ),
      ),
    );
  }

  void _openPayslips() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminPayslipRequestsScreen(
          adminId: widget.employeeId,
          adminName: _adminName,
        ),
      ),
    );
  }

  void _openDocumentRequests() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DocumentRequestsSheet(
        db: _db,
        adminId: widget.employeeId,
        adminName: _adminName,
      ),
    );
  }

  void _openMessages() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminMessagesScreen()),
    );
  }

  void _reviewPrimaryApproval() {
    if (_leaveRequests > 0) {
      _openLeaveRequests();
      return;
    }

    if (_wfhRequests > 0) {
      _openApprovals(tab: 2);
      return;
    }

    if (_punchRequests > 0) {
      _openApprovals(tab: 3);
      return;
    }

    if (_adminMessages > 0 || _deviceApprovals > 0) {
      _openApprovals(tab: _adminMessages > 0 ? 0 : 1);
      return;
    }

    if (_supportTickets > 0) {
      _openSupportTickets();
      return;
    }

    if (_compensationRequests > 0) {
      _openCompensation();
      return;
    }

    if (_documentRequests > 0) {
      _openDocumentRequests();
      return;
    }
  }

  void _openSupportTickets() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SupportTicketsSheet(db: _db),
    );
  }

  void _openApprovals({int tab = 0}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminApprovalsScreen(
          adminId: widget.employeeId,
          adminName: _adminName,
          initialTabIndex: tab,
        ),
      ),
    );
  }

  void _openAttendance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminAttendanceScreen(
          adminId: widget.employeeId,
          adminName: _adminName,
        ),
      ),
    );
  }

  void _openReports() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ReportsScreen()),
    );
  }

  void _openActivityLog() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AdminActivityLogScreen()),
    );
  }

  void _openCompensation() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminCompensationRequestsScreen(
          adminId: widget.employeeId,
          adminName: _adminName,
        ),
      ),
    );
  }

  void _openAnnouncements() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AnnouncementDetailScreen(isAdmin: true),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.green,
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _buildHeader(),
                    const SizedBox(height: 28),
                    _buildGreetingSection(),
                    const SizedBox(height: 24),
                    _buildApprovalHero(),
                    const SizedBox(height: 16),
                    _buildStatsStrip(),
                    const SizedBox(height: 28),
                    _buildQuickActionsHeader(),
                    const SizedBox(height: 12),
                    _buildQuickActionsGrid(),
                    const SizedBox(height: 18),
                    _buildAttendanceInsight(),
                    const SizedBox(height: 8),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    // The dashboard is already connected to onValue listeners.
    // Reading once here forces an immediate connection check without replacing
    // the live streams.
    try {
      await _db.child('users').get();
      await _db.child('Attendance').get();
    } catch (_) {
      // Keep the current live values if the temporary refresh read fails.
    }
  }

  // ---------------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------------

  Widget _buildHeader() {
    return Row(
      children: [
        _buildBrand(),
        const Spacer(),
        _circleButton(
          icon: Icons.notifications_none_rounded,
          onTap: _openNotifications,
          showDot: _hasUnreadNotification,
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: _openProfile,
          child: Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: AppColors.brightGreen,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(
                Icons.person_outline_rounded,
                color: AppColors.primaryDark,
                size: 25,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrand() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 34,
          height: 38,
          child: Image.asset(
            'assets/images/workora_logo.png',
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.blur_circular_rounded,
              color: AppColors.green,
              size: 30,
            ),
          ),
        ),
        const SizedBox(width: 7),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'workora',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.8,
                height: 1,
              ),
            ),
            SizedBox(height: 5),
            Text(
              'H R M S · A D M I N',
              style: TextStyle(
                color: AppColors.mutedText,
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.8,
                height: 1,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _circleButton({
    required IconData icon,
    required VoidCallback onTap,
    bool showDot = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.surface,
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.divider),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: AppColors.textPrimary, size: 24),
            if (showDot)
              Positioned(
                right: 10,
                top: 9,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GREETING
  // ---------------------------------------------------------------------------

  Widget _buildGreetingSection() {
    final now = DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_greeting()},',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  height: .98,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.6,
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      _firstName(),
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.green,
                        fontSize: 34,
                        height: .98,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  const Text('👋', style: TextStyle(fontSize: 26)),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                _attentionCount == 0
                    ? 'You\'re all caught up today.'
                    : '$_attentionCount ${_attentionCount == 1 ? 'thing needs' : 'things need'}\nyour attention today.',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 15,
                  height: 1.35,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_weekdayShort()}, ${now.day} ${_monthShort()}',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            Text(
              '${now.year}',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.successLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Text(
                _roleName(),
                style: const TextStyle(
                  color: AppColors.green,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // APPROVAL HERO
  // ---------------------------------------------------------------------------

  Widget _buildApprovalHero() {
    final leaveCount = _leaveRequests;
    final headlineCount = leaveCount > 0 ? leaveCount : _pendingApprovals;

    final names = _pendingLeaveNames.isEmpty
        ? 'No pending leave requests right now.'
        : _formatNames(_pendingLeaveNames, leaveCount);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 19, 20, 18),
      decoration: BoxDecoration(
        gradient: AppGradients.punchCard,
        borderRadius: BorderRadius.circular(28),
        boxShadow: AppShadows.hero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.brightGreen,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 9),
              const Text(
                'NEEDS YOUR APPROVAL',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$headlineCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 54,
                  height: .82,
                  fontWeight: FontWeight.w900,
                  letterSpacing: -2,
                ),
              ),
              const SizedBox(width: 13),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  leaveCount > 0
                      ? (leaveCount == 1
                          ? 'pending leave request'
                          : 'pending leave requests')
                      : (headlineCount == 1
                          ? 'pending request'
                          : 'pending requests'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            names,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: AppGradients.brightGreen,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _pendingApprovals == 0 ? null : _reviewPrimaryApproval,
                  borderRadius: BorderRadius.circular(17),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_rounded,
                        color: AppColors.primaryDark,
                        size: 22,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Review now',
                        style: TextStyle(
                          color: AppColors.primaryDark,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 15),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$_checkedInToday checked in today',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '$_absentToday absent',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatNames(List<String> names, int total) {
    if (names.isEmpty) return 'No pending leave requests right now.';
    if (names.length == 1) {
      return '${names.first} is waiting on a decision.';
    }
    if (names.length == 2) {
      return '${names[0]} and ${names[1]} are waiting on a decision.';
    }

    final remaining = total > names.length ? ' and others' : '';
    return '${names[0]}, ${names[1]} and ${names[2]}$remaining are waiting on a decision.';
  }

  // ---------------------------------------------------------------------------
  // STATS STRIP
  // ---------------------------------------------------------------------------

  Widget _buildStatsStrip() {
    return Container(
      height: 112,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(23),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          _statItem(
            Icons.person_outline_rounded,
            '$_totalEmployees',
            'Employees',
            AppColors.green,
          ),
          _statDivider(),
          _statItem(
            Icons.check_circle_outline_rounded,
            '$_checkedInToday',
            'Checked in',
            AppColors.calendarPresentText,
          ),
          _statDivider(),
          _statItem(
            Icons.error_outline_rounded,
            '$_absentToday',
            'Absent',
            AppColors.grey,
          ),
          _statDivider(),
          _statItem(
            Icons.credit_card_outlined,
            '$_pendingApprovals',
            'Pending',
            AppColors.info,
          ),
        ],
      ),
    );
  }

  Widget _statDivider() {
    return Container(
      width: 1,
      height: 57,
      color: AppColors.divider,
    );
  }

  Widget _statItem(IconData icon, String value, String label, Color color) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 23),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 20,
              height: 1,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.mutedText,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // QUICK ACTIONS
  // ---------------------------------------------------------------------------

  Widget _buildQuickActionsHeader() {
    return Row(
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 22,
            fontWeight: FontWeight.w900,
            letterSpacing: -.6,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _showAllActions,
          child: const Row(
            children: [
              Text(
                'See all',
                style: TextStyle(
                  color: AppColors.green,
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                ),
              ),
              SizedBox(width: 3),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColors.green,
                size: 20,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsGrid() {
    return Column(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _quickActionCard(
                title: 'Leave Requests',
                subtitle: 'Review & approve',
                icon: Icons.event_available_outlined,
                background: AppColors.successLight,
                iconColor: AppColors.green,
                badge: _leaveRequests,
                onTap: _openLeaveRequests,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _quickActionCard(
                title: 'Payslip Requests',
                subtitle: 'Review & issue',
                icon: Icons.description_outlined,
                background: const Color(0xFFF2F9D9),
                iconColor: AppColors.primary,
                badge: _pendingPayslips,
                onTap: _openPayslips,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _quickActionCard(
                title: 'Other Messages',
                subtitle: 'Employee requests',
                icon: Icons.chat_bubble_outline_rounded,
                background: AppColors.lightGrey,
                iconColor: AppColors.textSecondary,
                badge: _adminMessages,
                onTap: _openMessages,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: _quickActionCard(
                title: 'Publish\nAnnouncement',
                subtitle: 'Notify everyone',
                icon: Icons.campaign_outlined,
                background: const Color(0xFFDFF5F1),
                iconColor: AppColors.green,
                onTap: _publishAnnouncement,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _quickActionCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color background,
    required Color iconColor,
    required VoidCallback onTap,
    int? badge,
  }) {
    return Material(
      color: background,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        child: Container(
          height: 178,
          padding: const EdgeInsets.fromLTRB(17, 17, 14, 15),
          child: Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.72),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: iconColor, size: 24),
                ),
              ),
              if (badge != null && badge > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 27),
                    height: 27,
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    decoration: const BoxDecoration(
                      color: AppColors.primaryDark,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$badge',
                      style: const TextStyle(
                        color: AppColors.brightGreen,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        height: 1.12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.35,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 5),
                        Container(
                          width: 31,
                          height: 31,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.chevron_right_rounded,
                            color: iconColor,
                            size: 19,
                          ),
                        ),
                      ],
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

  // ---------------------------------------------------------------------------
  // ATTENDANCE INSIGHT
  // ---------------------------------------------------------------------------

  Widget _buildAttendanceInsight() {
    final attendanceRate = _totalEmployees == 0
        ? 0
        : ((_checkedInToday / _totalEmployees) * 100).round();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppColors.primaryDark,
        borderRadius: BorderRadius.circular(25),
        boxShadow: AppShadows.hero,
      ),
      child: Row(
        children: [
          Container(
            width: 51,
            height: 51,
            decoration: BoxDecoration(
              color: AppColors.green.withOpacity(.22),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.auto_awesome_outlined,
              color: AppColors.brightGreen,
              size: 24,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Team attendance is $attendanceRate% today',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _absentToday == 0
                      ? 'Everyone has checked in today.'
                      : 'Keep an eye on the $_absentToday who are absent today.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _openAttendance,
            icon: const Icon(
              Icons.chevron_right_rounded,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SEE ALL
  // ---------------------------------------------------------------------------

  void _showAllActions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.divider,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    'Admin actions',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Open the tools available from the Admin Panel.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _actionTile(
                    Icons.people_alt_outlined,
                    'Employee Management',
                    'View employee attendance and add employees',
                    _openEmployeeManagement,
                  ),
                  _actionTile(
                    Icons.event_note_outlined,
                    'Leave Requests',
                    'Review and approve leave requests',
                    _openLeaveRequests,
                  ),
                  _actionTile(
                    Icons.home_work_outlined,
                    'Work From Home',
                    'Review WFH requests',
                    () => _openApprovals(tab: 2),
                  ),
                  _actionTile(
                    Icons.fact_check_outlined,
                    'Attendance Corrections',
                    'Review punch-out and mis-punch requests',
                    () => _openApprovals(tab: 3),
                  ),
                  _actionTile(
                    Icons.support_agent_outlined,
                    'Support Tickets',
                    'Open employee helpdesk requests',
                    _openSupportTickets,
                  ),
                  _actionTile(
                    Icons.payments_outlined,
                    'Compensation',
                    'Review compensation requests',
                    _openCompensation,
                  ),
                  _actionTile(
                    Icons.receipt_long_outlined,
                    'Payslips',
                    'Review and issue payslips',
                    _openPayslips,
                  ),
                  _actionTile(
                    Icons.folder_shared_outlined,
                    'Document Requests',
                    'Review letters and other document requests',
                    _openDocumentRequests,
                  ),
                  _actionTile(
                    Icons.bar_chart_outlined,
                    'Reports',
                    'Open admin reports',
                    _openReports,
                  ),
                  _actionTile(
                    Icons.campaign_outlined,
                    'Announcements',
                    'Publish and manage announcements',
                    () {
                      Navigator.pop(sheetContext);
                      _publishAnnouncement();
                    },
                  ),
                  _actionTile(
                    Icons.history_outlined,
                    'Admin Activity',
                    'View administrative activity',
                    _openActivityLog,
                  ),
                  if (widget.isSuperAdmin)
                    _actionTile(
                      Icons.manage_accounts_outlined,
                      'Manage Admins',
                      'Manage administrator access',
                      () {
                        Navigator.pop(sheetContext);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ManageAdminsScreen(
                              superAdminId: widget.employeeId,
                              superAdminName: _adminName,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _actionTile(
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: AppColors.green, size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.mutedText,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // EMPLOYEE MANAGEMENT — DASHBOARD ONLY
  // ---------------------------------------------------------------------------

  void _openEmployeeManagement() {
    Navigator.pop(context);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EmployeeManagementSheet(
        db: _db,
        onAddEmployee: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AddEmployeeScreen()),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ANNOUNCEMENT PUBLISHER
  // ---------------------------------------------------------------------------

  Future<void> _publishAnnouncement() async {
    final titleController = TextEditingController();
    final messageController = TextEditingController();
    UploadedAttachment? attachment;
    bool uploading = false;

    try {
      final published = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) {
          return StatefulBuilder(
            builder: (context, setSheetState) {
              return Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * .88,
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  12,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: AppColors.divider,
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                      const SizedBox(height: 17),
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: AppColors.successLight,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Icon(
                              Icons.campaign_outlined,
                              color: AppColors.green,
                            ),
                          ),
                          const SizedBox(width: 11),
                          const Expanded(
                            child: Text(
                              'Publish Announcement',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.pop(sheetContext, false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _inputField(
                        controller: titleController,
                        label: 'Title *',
                        hint: 'e.g. Office Holiday Notice',
                      ),
                      const SizedBox(height: 12),
                      _inputField(
                        controller: messageController,
                        label: 'Message *',
                        hint: 'Write your announcement details here...',
                        maxLines: 4,
                      ),
                      const SizedBox(height: 15),
                      const Text(
                        'Attachment (Optional)',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (attachment == null)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: uploading
                                    ? null
                                    : () async {
                                        setSheetState(() => uploading = true);
                                        try {
                                          final result = await AttachmentUpload
                                              .pickAndUploadImage('announcements');
                                          if (result != null) {
                                            setSheetState(() => attachment = result);
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Unable to attach image: $e'),
                                              ),
                                            );
                                          }
                                        } finally {
                                          setSheetState(() => uploading = false);
                                        }
                                      },
                                icon: const Icon(Icons.image_outlined),
                                label: const Text('Add Image'),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: uploading
                                    ? null
                                    : () async {
                                        setSheetState(() => uploading = true);
                                        try {
                                          final result = await AttachmentUpload
                                              .pickAndUploadDocument('announcements');
                                          if (result != null) {
                                            setSheetState(() => attachment = result);
                                          }
                                        } catch (e) {
                                          if (mounted) {
                                            ScaffoldMessenger.of(context).showSnackBar(
                                              SnackBar(
                                                content: Text('Unable to attach document: $e'),
                                              ),
                                            );
                                          }
                                        } finally {
                                          setSheetState(() => uploading = false);
                                        }
                                      },
                                icon: const Icon(Icons.attach_file_rounded),
                                label: const Text('Add File'),
                              ),
                            ),
                          ],
                        )
                      else
                        _attachmentPreview(
                          attachment!,
                          onRemove: () => setSheetState(() => attachment = null),
                        ),
                      if (uploading) ...[
                        const SizedBox(height: 12),
                        const Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              SizedBox(
                                width: 17,
                                height: 17,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 9),
                              Text(
                                'Uploading attachment...',
                                style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: uploading
                              ? null
                              : () {
                                  if (titleController.text.trim().isEmpty ||
                                      messageController.text.trim().isEmpty) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Please enter both title and message.',
                                        ),
                                      ),
                                    );
                                    return;
                                  }
                                  Navigator.pop(sheetContext, true);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: const Text(
                            'PUBLISH ANNOUNCEMENT',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: .2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );

      if (published != true) return;

      if (titleController.text.trim().isEmpty ||
          messageController.text.trim().isEmpty) {
        return;
      }

      await _db.child('Announcements').push().set({
        'title': titleController.text.trim(),
        'message': messageController.text.trim(),
        'createdBy': widget.employeeId,
        'createdAt': DateTime.now().toIso8601String(),
        if (attachment != null) 'attachment': attachment!.toMap(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Announcement published successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to publish announcement: $e')),
      );
    } finally {
      titleController.dispose();
      messageController.dispose();
    }
  }

  Widget _inputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(15),
          borderSide: const BorderSide(color: AppColors.green, width: 1.3),
        ),
      ),
    );
  }

  Widget _attachmentPreview(
    UploadedAttachment attachment, {
    required VoidCallback onRemove,
  }) {
    Widget preview;

    if (attachment.isImage && attachment.previewBytes != null) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.memory(
          attachment.previewBytes!,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    } else if (attachment.isImage && attachment.url.startsWith('data:image/')) {
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.memory(
          base64Decode(attachment.url.split(',').last),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
        ),
      );
    } else {
      preview = Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: AppColors.successLight,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(
          attachment.isImage ? Icons.image_outlined : Icons.description_outlined,
          color: AppColors.green,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          preview,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  attachment.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Attached successfully',
                  style: TextStyle(
                    color: AppColors.success,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(
              Icons.delete_outline_rounded,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// DASHBOARD-ONLY SUPPORT TICKETS SHEET
// =============================================================================

class _DocumentRequestsSheet extends StatefulWidget {
  final DatabaseReference db;
  final String adminId;
  final String adminName;

  const _DocumentRequestsSheet({
    required this.db,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<_DocumentRequestsSheet> createState() => _DocumentRequestsSheetState();
}

class _DocumentRequestsSheetState extends State<_DocumentRequestsSheet> {
  Future<void> _updateRequest(
    String employeeId,
    String requestId,
    String status,
  ) async {
    await widget.db
        .child('DocumentRequests')
        .child(employeeId)
        .child(requestId)
        .update({
      'status': status,
      'reviewedAt': DateTime.now().toIso8601String(),
      'reviewedBy': widget.adminId,
      'reviewedByName': widget.adminName,
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == 'approved'
              ? 'Document request approved.'
              : 'Document request rejected.',
        ),
      ),
    );
  }

  String _requestedDate(String? value) {
    if (value == null || value.trim().isEmpty) return '--';
    try {
      final date = DateTime.parse(value).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year} ${date.hour.toString().padLeft(2, '0')}:'
          '${date.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * .82,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: StreamBuilder<DatabaseEvent>(
          stream: widget.db.child('DocumentRequests').onValue,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Text(
                  'Could not load document requests.',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              );
            }

            final requests = <Map<String, dynamic>>[];
            final root = snapshot.data?.snapshot.value;

            if (root is Map) {
              final employees = Map<dynamic, dynamic>.from(root);
              for (final employeeEntry in employees.entries) {
                final employeeId = employeeEntry.key.toString();
                if (employeeEntry.value is! Map) continue;

                final employeeRequests =
                    Map<dynamic, dynamic>.from(employeeEntry.value as Map);

                for (final requestEntry in employeeRequests.entries) {
                  if (requestEntry.value is! Map) continue;
                  final data =
                      Map<dynamic, dynamic>.from(requestEntry.value as Map);
                  final status =
                      data['status']?.toString().trim().toLowerCase();

                  if (status != 'pending') continue;

                  requests.add({
                    ...data.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ),
                    'employeeId': employeeId,
                    'requestId': requestEntry.key.toString(),
                  });
                }
              }
            }

            requests.sort(
              (a, b) => (b['requestedAt']?.toString() ?? '')
                  .compareTo(a['requestedAt']?.toString() ?? ''),
            );

            return Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Document Requests',
                              style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Review employee letters and other documents.',
                              style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.successLight,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          '${requests.length} pending',
                          style: const TextStyle(
                            color: AppColors.green,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: requests.isEmpty
                      ? const Center(
                          child: Text(
                            'No pending document requests.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                            ),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                          itemCount: requests.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final item = requests[index];
                            final employeeName =
                                item['employeeName']?.toString() ??
                                    item['employeeId']?.toString() ??
                                    'Employee';
                            final employeeId =
                                item['employeeId']?.toString() ?? '--';
                            final requestId =
                                item['requestId']?.toString() ?? '';
                            final documentType =
                                item['documentType']?.toString() ??
                                    'Document request';
                            final description =
                                item['description']?.toString() ?? '';
                            final requestedAt =
                                _requestedDate(item['requestedAt']?.toString());

                            return Container(
                              padding: const EdgeInsets.all(15),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: AppColors.divider,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 42,
                                        height: 42,
                                        decoration: BoxDecoration(
                                          color: AppColors.successLight,
                                          borderRadius:
                                              BorderRadius.circular(13),
                                        ),
                                        child: const Icon(
                                          Icons.description_outlined,
                                          color: AppColors.green,
                                          size: 21,
                                        ),
                                      ),
                                      const SizedBox(width: 11),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              documentType,
                                              style: const TextStyle(
                                                color: AppColors.textPrimary,
                                                fontSize: 15,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                            const SizedBox(height: 3),
                                            Text(
                                              '$employeeName • $employeeId',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (description.trim().isNotEmpty) ...[
                                    const SizedBox(height: 11),
                                    Text(
                                      description,
                                      style: const TextStyle(
                                        color: AppColors.textSecondary,
                                        fontSize: 12,
                                        height: 1.35,
                                      ),
                                    ),
                                  ],
                                  const SizedBox(height: 9),
                                  Text(
                                    'Requested: $requestedAt',
                                    style: const TextStyle(
                                      color: AppColors.mutedText,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                  const SizedBox(height: 13),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          onPressed: requestId.isEmpty
                                              ? null
                                              : () => _updateRequest(
                                                    employeeId,
                                                    requestId,
                                                    'rejected',
                                                  ),
                                          child: const Text('Reject'),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.green,
                                            foregroundColor: Colors.white,
                                          ),
                                          onPressed: requestId.isEmpty
                                              ? null
                                              : () => _updateRequest(
                                                    employeeId,
                                                    requestId,
                                                    'approved',
                                                  ),
                                          child: const Text('Approve'),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SupportTicketsSheet extends StatelessWidget {
  final DatabaseReference db;

  const _SupportTicketsSheet({required this.db});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * .78,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 18, 20, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Support Tickets',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 21,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Employee helpdesk requests',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: db.child('HelpdeskRequests').onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final tickets = <Map<String, dynamic>>[];
                final root = snapshot.data?.snapshot.value;

                if (root is Map) {
                  final rootMap = Map<dynamic, dynamic>.from(root);
                  rootMap.forEach((employeeId, rawRequests) {
                    if (rawRequests is! Map) return;
                    final requests = Map<dynamic, dynamic>.from(rawRequests);
                    requests.forEach((requestId, rawRequest) {
                      if (rawRequest is! Map) return;
                      final request = Map<dynamic, dynamic>.from(rawRequest);
                      final status =
                          request['status']?.toString().trim().toLowerCase();
                      final department =
                          request['department']?.toString().trim().toLowerCase();

                      // Admin Dashboard handles only Managerial team tickets.
                      // HR, IT Helpdesk, and High table belong to their
                      // respective dashboards.
                      if (department != 'managerial team') return;
                      if (status == 'resolved' || status == 'closed') return;

                      tickets.add({
                        'employeeId': employeeId.toString(),
                        'requestId': requestId.toString(),
                        ...request.map((key, value) =>
                            MapEntry(key.toString(), value)),
                      });
                    });
                  });
                }

                tickets.sort((a, b) =>
                    (b['createdAt'] ?? '').toString().compareTo(
                          (a['createdAt'] ?? '').toString(),
                        ));

                if (tickets.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No open support tickets.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  itemCount: tickets.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) {
                    final ticket = tickets[index];
                    final employeeName =
                        (ticket['employeeName'] ?? ticket['employeeId'])
                            .toString();
                    final subject =
                        (ticket['subject'] ?? 'Support request').toString();
                    final message =
                        (ticket['message'] ?? '').toString();

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  employeeName,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warningLight,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'OPEN',
                                  style: TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 9,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subject,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (message.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              message,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 11,
                                height: 1.3,
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () async {
                                await db
                                    .child('HelpdeskRequests')
                                    .child(ticket['employeeId'].toString())
                                    .child(ticket['requestId'].toString())
                                    .update({
                                  'status': 'resolved',
                                  'resolvedAt': DateTime.now().toIso8601String(),
                                });
                              },
                              icon: const Icon(Icons.check_rounded, size: 17),
                              label: const Text('Resolve'),
                            ),
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

// =============================================================================
// DASHBOARD-ONLY EMPLOYEE MANAGEMENT SHEET
// =============================================================================

class _EmployeeManagementSheet extends StatelessWidget {
  final DatabaseReference db;
  final VoidCallback onAddEmployee;

  const _EmployeeManagementSheet({
    required this.db,
    required this.onAddEmployee,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * .78,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 42,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Employee Management',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 21,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Live employee directory',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onAddEmployee,
                  tooltip: 'Add employee',
                  icon: const Icon(
                    Icons.person_add_alt_1_rounded,
                    color: AppColors.green,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<DatabaseEvent>(
              stream: db.child('users').onValue,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final users = <Map<String, dynamic>>[];
                final value = snapshot.data?.snapshot.value;
                final root = value is Map
                    ? Map<dynamic, dynamic>.from(value)
                    : <dynamic, dynamic>{};

                root.forEach((id, raw) {
                  final user = raw is Map
                      ? Map<dynamic, dynamic>.from(raw)
                      : <dynamic, dynamic>{};
                  final role = user['role']?.toString().trim().toLowerCase();
                  if (role == 'superadmin') return;

                  users.add({
                    'id': id.toString(),
                    'name': (user['name'] ??
                            user['employeeName'] ??
                            user['displayName'] ??
                            id)
                        .toString(),
                    'designation': (user['designation'] ??
                            user['role'] ??
                            'Employee')
                        .toString(),
                  });
                });

                users.sort(
                  (a, b) => a['name']
                      .toString()
                      .toLowerCase()
                      .compareTo(b['name'].toString().toLowerCase()),
                );

                if (users.isEmpty) {
                  return const Center(
                    child: Text(
                      'No employees found.',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
                  itemCount: users.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final user = users[index];
                    final name = user['name'].toString();
                    final initials = _initials(name);

                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 22,
                            backgroundColor: AppColors.successLight,
                            child: Text(
                              initials,
                              style: const TextStyle(
                                color: AppColors.green,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  '${user['id']} · ${user['designation']}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: onAddEmployee,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('ADD EMPLOYEE'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryDark,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }
}
