
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/leave_constants.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';
import '../utils/email_alert_helper.dart';
import 'leave_request_bottom_sheet.dart';

class LeaveScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onBack;

  const LeaveScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onBack,
  });

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  late DatabaseReference dbRef;

  bool loading = true;
  Map<String, int> balance = {};
  List<Map<dynamic, dynamic>> requests = [];
  String filter = 'all';

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadData();
  }

  int get _currentYear => DateTime.now().year;

  Future<void> _loadData() async {
    if (mounted) setState(() => loading = true);

    try {
      final balanceSnap = await dbRef
          .child('LeaveBalances')
          .child(widget.employeeId)
          .child(_currentYear.toString())
          .get();

      final loadedBalance =
          Map<String, int>.from(LeaveConstants.defaultQuota);

      if (balanceSnap.exists && balanceSnap.value is Map) {
        final data = Map<dynamic, dynamic>.from(balanceSnap.value as Map);

        for (final type in LeaveConstants.allTypes) {
          if (data[type] != null) {
            loadedBalance[type] =
                int.tryParse(data[type].toString()) ??
                LeaveConstants.defaultQuota[type]!;
          }
        }
      } else {
        await dbRef
            .child('LeaveBalances')
            .child(widget.employeeId)
            .child(_currentYear.toString())
            .set(LeaveConstants.defaultQuota);
      }

      final requestsSnap = await dbRef
          .child('LeaveRequests')
          .child(widget.employeeId)
          .get();

      final loadedRequests = <Map<dynamic, dynamic>>[];

      if (requestsSnap.exists && requestsSnap.value is Map) {
        final data = Map<dynamic, dynamic>.from(requestsSnap.value as Map);

        data.forEach((requestId, value) {
          if (value is Map) {
            final req = Map<dynamic, dynamic>.from(value);
            req['requestId'] = requestId;
            loadedRequests.add(req);
          }
        });

        loadedRequests.sort(
          (a, b) => (b['appliedOn'] ?? '')
              .toString()
              .compareTo((a['appliedOn'] ?? '').toString()),
        );
      }

      if (!mounted) return;

      setState(() {
        balance = loadedBalance;
        requests = loadedRequests;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load leave data: $e')),
      );
    }
  }

  Future<void> _showApplyDialog() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.48),
      enableDrag: true,
      builder: (_) => LeaveRequestBottomSheet(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        initialBalance: balance,
      ),
    );

    if (result == null || !mounted) return;

    await _submitLeaveRequest(
      leaveType: result['leaveType'] as String,
      fromDate: result['fromDate'] as DateTime,
      toDate: result['toDate'] as DateTime,
      numberOfDays: result['numberOfDays'] as int,
      reason: result['reason'] as String,
    );
  }

  Future<void> _submitLeaveRequest({
    required String leaveType,
    required DateTime fromDate,
    required DateTime toDate,
    required int numberOfDays,
    required String reason,
  }) async {
    try {
      final requestRef =
          dbRef.child('LeaveRequests').child(widget.employeeId).push();

      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': widget.employeeName,
        'leaveType': leaveType,
        'fromDate': DateFormat('yyyy-MM-dd').format(fromDate),
        'toDate': DateFormat('yyyy-MM-dd').format(toDate),
        'numberOfDays': numberOfDays,
        'reason': reason,
        'status': 'pending',
        'appliedOn': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      });

      await NotificationCenter.sendAdmin(
        title: 'New Leave Request',
        message:
            '${widget.employeeName} has requested '
            '${LeaveConstants.displayName(leaveType)} from '
            '${DateFormat('dd MMM yyyy').format(fromDate)} to '
            '${DateFormat('dd MMM yyyy').format(toDate)}.',
      );

      await EmailAlertHelper.sendAlert(
        templateId: EmailAlertHelper.templateLeaveRequest,
        subject: 'New Leave Request — ${widget.employeeName}',
        message:
            '${widget.employeeName} (${widget.employeeId}) has requested '
            '${LeaveConstants.displayName(leaveType)} from '
            '${DateFormat('dd MMM yyyy').format(fromDate)} to '
            '${DateFormat('dd MMM yyyy').format(toDate)} '
            '($numberOfDays day(s)).\n\n'
            'Reason: $reason\n\n'
            'Open the app to approve or reject this request.',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Leave request submitted')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Request'),
        content: const Text('Withdraw this leave request?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes, Cancel'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await dbRef
          .child('LeaveRequests')
          .child(widget.employeeId)
          .child(requestId)
          .remove();

      await NotificationCenter.sendAdmin(
        title: 'Leave Request Cancelled',
        message:
            '${widget.employeeName} cancelled their pending leave request.',
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request cancelled')),
      );

      await _loadData();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  List<Map<dynamic, dynamic>> get _filteredRequests {
    if (filter == 'all') return requests;

    return requests.where((request) {
      return (request['status']?.toString() ?? 'pending') == filter;
    }).toList();
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  Color _typeColor(int index) {
    const colors = [
      Color(0xFF08A66C),
      Color(0xFFB87900),
      Color(0xFF7542D8),
      Color(0xFF3D7FD6),
    ];
    return colors[index % colors.length];
  }

  int get _totalBalance => balance.values.fold(0, (sum, value) => sum + value);

  String _formatDateRange(Map<dynamic, dynamic> request) {
    final from = request['fromDate']?.toString() ?? '';
    final to = request['toDate']?.toString() ?? '';

    if (from.isEmpty || to.isEmpty) return '$from — $to';

    DateTime? parse(String value) => DateTime.tryParse(value);

    final fromDate = parse(from);
    final toDate = parse(to);

    if (fromDate == null || toDate == null) {
      return '$from — $to';
    }

    return '${DateFormat('d MMM').format(fromDate)} — '
        '${DateFormat('d MMM').format(toDate)}';
  }

  String _monthLabel() => DateFormat('MMM yyyy').format(DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                ),
              )
            : RefreshIndicator(
                color: AppColors.primary,
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
                  children: [
                    _buildHeader(),
                    const SizedBox(height: 18),
                    _buildSummary(),
                    const SizedBox(height: 16),
                    _buildRequestsHeader(),
                    const SizedBox(height: 9),
                    _buildFilters(),
                    const SizedBox(height: 10),
                    if (_filteredRequests.isEmpty)
                      _buildEmptyState()
                    else
                      ..._filteredRequests.map(_buildRequestCard),
                  ],
                ),
              ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: _showApplyDialog,
            icon: const Icon(Icons.add_rounded, size: 19),
            label: const Text(
              'Request a leave',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        _roundIconButton(
          icon: Icons.chevron_left_rounded,
          onTap: widget.onBack ??
              () {
                Navigator.maybePop(context);
              },
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Leave',
              style: TextStyle(
                fontSize: 20,
                height: 1,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _monthLabel(),
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: AppColors.divider),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 19,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildSummary() {
    final types = LeaveConstants.allTypes;

    return Container(
      padding: const EdgeInsets.fromLTRB(15, 14, 15, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Leave summary',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              SizedBox(
                width: 100,
                height: 100,
                child: CustomPaint(
                  painter: _LeaveDonutPainter(
                    values: types
                        .map((type) => balance[type] ?? 0)
                        .toList(),
                    colors: List.generate(
                      types.length,
                      (index) => _typeColor(index),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  children: List.generate(types.length, (index) {
                    final type = types[index];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: _typeColor(index),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              LeaveConstants.displayName(type),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                          Text(
                            '${balance[type] ?? 0}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRequestsHeader() {
    return const Text(
      'Leave requests',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildFilters() {
    const items = [
      ('All', 'all'),
      ('Pending', 'pending'),
      ('Approved', 'approved'),
      ('Rejected', 'rejected'),
    ];

    return Row(
      children: items.map((item) {
        final selected = filter == item.$2;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 5),
            child: GestureDetector(
              onTap: () => setState(() => filter = item.$2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 31,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.veryLightGreen
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(
                    color: selected
                        ? AppColors.green
                        : AppColors.divider,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (item.$2 != 'all') ...[
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _statusColor(item.$2),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      item.$1,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: selected
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRequestCard(Map<dynamic, dynamic> request) {
    final status = request['status']?.toString() ?? 'pending';
    final type = LeaveConstants.displayName(
      request['leaveType']?.toString() ?? '',
    );
    final days = int.tryParse(
          request['numberOfDays']?.toString() ?? '',
        ) ??
        1;

    final reason = request['reason']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '$type request',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _statusBadge(status),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.check_box_outline_blank_rounded,
                size: 11,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                _formatDateRange(request),
                style: const TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(
              reason,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10,
                height: 1.3,
                color: AppColors.mutedText,
              ),
            ),
          ],
          if (status == 'pending') ...[
            const SizedBox(height: 5),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    _cancelRequest(request['requestId'].toString()),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 2,
                  ),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  foregroundColor: AppColors.danger,
                ),
                child: Text(
                  days > 0 ? 'Cancel request' : 'Cancel',
                  style: const TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(String status) {
    final color = _statusColor(status);
    final label = status.isEmpty
        ? 'Pending'
        : '${status[0].toUpperCase()}${status.substring(1)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 42),
      alignment: Alignment.center,
      child: Column(
        children: [
          Icon(
            Icons.event_available_outlined,
            size: 34,
            color: AppColors.mutedText.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 8),
          const Text(
            'No leave requests',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaveDonutPainter extends CustomPainter {
  final List<int> values;
  final List<Color> colors;

  _LeaveDonutPainter({
    required this.values,
    required this.colors,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2 - 2;

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..color = const Color(0xFFECEFEB);

    canvas.drawCircle(center, radius, trackPaint);

    if (total <= 0) return;

    var startAngle = -1.5708;

    for (var i = 0; i < values.length; i++) {
      if (values[i] <= 0) continue;

      final sweep = (values[i] / total) * 6.283185307;

      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12
        ..strokeCap = StrokeCap.butt
        ..color = colors[i % colors.length];

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweep,
        false,
        paint,
      );

      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _LeaveDonutPainter oldDelegate) {
    return oldDelegate.values != values || oldDelegate.colors != colors;
  }
}
