import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/notification_center.dart';

/// Employee screen used when an Attendance History day is classified as
/// WORK-PENDING. The employee can submit a request to use available extra
/// work/compensation time against the selected pending day.
class CompensationRequestScreen extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final String initialDate;

  const CompensationRequestScreen({
    super.key,
    required this.employeeId,
    this.employeeName,
    required this.initialDate,
  });

  @override
  State<CompensationRequestScreen> createState() =>
      _CompensationRequestScreenState();
}

class _CompensationRequestScreenState
    extends State<CompensationRequestScreen> {
  late final DatabaseReference dbRef;

  bool loading = true;
  bool submitting = false;
  bool hasPendingRequest = false;

  int shortfallMinutes = 0;
  int availableExtraMinutes = 0;

  String? existingStatus;
  String? existingRequestId;

  final TextEditingController reasonController = TextEditingController();

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

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => loading = true);

    try {
      final attendanceSnapshot = await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .get();

      final attendance = <String, Map<String, dynamic>>{};

      if (attendanceSnapshot.exists && attendanceSnapshot.value is Map) {
        final raw = Map<dynamic, dynamic>.from(
          attendanceSnapshot.value as Map,
        );

        for (final entry in raw.entries) {
          if (entry.value is Map) {
            attendance[entry.key.toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }

      final target = attendance[widget.initialDate];

      if (target != null) {
        final sessions = _sessionsFromRecord(target);
        if (sessions.isNotEmpty) {
          final result = AttendanceCalculator.calculateFromSessions(
            sessions,
            workFromHome: target['workFromHome'] == true,
          );

          shortfallMinutes = (result.shortfallHours * 60).round();
        }
      }

      // Calculate the employee's currently available extra-work pool using
      // the same attendance records used by HistoryScreen.
      for (final entry in attendance.entries) {
        final record = entry.value;
        final status = record['status']?.toString().toUpperCase();

        if (status == 'MIS-PUNCH' ||
            status == 'AUTO CHECKOUT PENDING' ||
            record['autoPunchOut'] == true) {
          continue;
        }

        final sessions = _sessionsFromRecord(record);
        if (sessions.isEmpty) continue;

        final result = AttendanceCalculator.calculateFromSessions(
          sessions,
          workFromHome: record['workFromHome'] == true,
        );

        if (result.extraHours > 0) {
          availableExtraMinutes += (result.extraHours * 60).round();
        }
      }

      final requestsSnapshot = await dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .get();

      if (requestsSnapshot.exists && requestsSnapshot.value is Map) {
        final requests = Map<dynamic, dynamic>.from(
          requestsSnapshot.value as Map,
        );

        for (final entry in requests.entries) {
          if (entry.value is! Map) continue;

          final request = Map<dynamic, dynamic>.from(entry.value as Map);
          final date = request['date']?.toString() ?? '';
          final status = request['status']?.toString().toLowerCase() ?? '';

          if (date == widget.initialDate &&
              status != 'cancelled' &&
              status != 'rejected') {
            hasPendingRequest = true;
            existingStatus = status;
            existingRequestId = entry.key.toString();
            break;
          }
        }
      }
    } catch (_) {
      // Keep the screen usable even if one optional data source is unavailable.
    }

    if (!mounted) return;
    setState(() => loading = false);
  }

  List<AttendanceSession> _sessionsFromRecord(Map<String, dynamic> record) {
    final sessions = <AttendanceSession>[];
    final rawSessions = record['sessions'];

    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is! Map) continue;

        final punchIn = item['punchIn']?.toString().trim();
        if (punchIn == null || punchIn.isEmpty) continue;

        final punchOut = item['punchOut']?.toString().trim();

        sessions.add(
          AttendanceSession(
            punchIn: punchIn,
            punchOut: punchOut == null || punchOut.isEmpty ? null : punchOut,
          ),
        );
      }
    }

    if (sessions.isEmpty) {
      final punchIn = record['punchIn']?.toString().trim();
      if (punchIn != null && punchIn.isNotEmpty) {
        final punchOut = record['punchOut']?.toString().trim();
        sessions.add(
          AttendanceSession(
            punchIn: punchIn,
            punchOut: punchOut == null || punchOut.isEmpty ? null : punchOut,
          ),
        );
      }
    }

    return sessions;
  }

  Future<void> _submit() async {
    if (submitting || hasPendingRequest) return;

    if (shortfallMinutes <= 0) {
      _showMessage('This day no longer has outstanding work time.');
      return;
    }

    setState(() => submitting = true);

    try {
      final requestedMinutes = availableExtraMinutes > 0
          ? shortfallMinutes.clamp(1, availableExtraMinutes)
          : shortfallMinutes;

      final requestRef = dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .push();

      final now = DateTime.now().toIso8601String();
      final name = (widget.employeeName ?? widget.employeeId).trim();

      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': name,
        'date': widget.initialDate,
        'requestedMinutes': requestedMinutes,
        'shortfallMinutes': shortfallMinutes,
        'availableExtraMinutes': availableExtraMinutes,
        'reason': reasonController.text.trim(),
        'status': 'pending',
        'requestedAt': now,
      });

      await NotificationCenter.sendAdmin(
        title: 'Compensation Request',
        message:
            '$name requested compensation for ${_formattedDate(widget.initialDate)} '
            '(${AttendanceCalculator.formatHours(requestedMinutes / 60)}).',
      );

      if (!mounted) return;

      setState(() {
        hasPendingRequest = true;
        existingStatus = 'pending';
        existingRequestId = requestRef.key;
        submitting = false;
      });

      _showMessage('Compensation request sent to admin.');
    } catch (e) {
      if (!mounted) return;
      setState(() => submitting = false);
      _showMessage('Could not submit the compensation request: $e');
    }
  }

  Future<void> _cancelRequest() async {
    final requestId = existingRequestId;
    if (requestId == null || requestId.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel request?'),
        content: const Text(
          'This will withdraw the pending compensation request.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Keep'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cancel request'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .child(requestId)
          .update({
        'status': 'cancelled',
        'cancelledAt': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;
      setState(() {
        hasPendingRequest = false;
        existingStatus = 'cancelled';
      });
      _showMessage('Compensation request cancelled.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Could not cancel the request: $e');
    }
  }

  String _formattedDate(String value) {
    try {
      return DateFormat('dd MMM yyyy').format(DateTime.parse(value));
    } catch (_) {
      return value;
    }
  }

  String _hours(int minutes) {
    return AttendanceCalculator.formatHours(minutes / 60);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final employeeName = widget.employeeName?.trim().isNotEmpty == true
        ? widget.employeeName!.trim()
        : widget.employeeId;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Compensation Request'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Work-Pending day',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _formattedDate(widget.initialDate),
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        employeeName,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 18),
                      _summaryRow(
                        Icons.timer_outlined,
                        'Outstanding time',
                        _hours(shortfallMinutes),
                        AppColors.warning,
                      ),
                      const SizedBox(height: 10),
                      _summaryRow(
                        Icons.add_task_outlined,
                        'Available extra work',
                        _hours(availableExtraMinutes),
                        AppColors.success,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                if (hasPendingRequest)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.warningLight,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: .25),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.schedule_send_rounded,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Request ${existingStatus ?? 'pending'}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Your compensation request for this day has already been submitted.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _cancelRequest,
                            child: const Text('Withdraw request'),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  const Text(
                    'Request compensation',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Submit this Work-Pending day for admin review. The admin can review the request before it is applied to your attendance balance.',
                    style: TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: reasonController,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      labelText: 'Reason / note (optional)',
                      hintText: 'Add a note for the admin',
                      filled: true,
                      fillColor: AppColors.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.divider,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: const BorderSide(
                          color: AppColors.divider,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: submitting ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        submitting ? 'Sending...' : 'Submit request',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _summaryRow(
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .10),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 12,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}
