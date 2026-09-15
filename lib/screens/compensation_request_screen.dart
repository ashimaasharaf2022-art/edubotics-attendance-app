import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/notification_center.dart';

/// Employee compensation request for ONE Work-Pending date.
///
/// This screen is opened from a particular Work-Pending attendance card, so
/// the employee should never be asked to select unrelated pending dates here.
/// If a request already exists for this date, the request status is shown and
/// the employee can delete a pending/returned/rejected request before sending
/// a new one.
class CompensationRequestScreen extends StatefulWidget {
  final String employeeId;
  final String? employeeName;
  final String? initialDate;

  const CompensationRequestScreen({
    super.key,
    required this.employeeId,
    this.employeeName,
    this.initialDate,
  });

  @override
  State<CompensationRequestScreen> createState() =>
      _CompensationRequestScreenState();
}

class _CompensationRequestScreenState
    extends State<CompensationRequestScreen> {
  late DatabaseReference dbRef;
  final messageController = TextEditingController();

  bool loading = true;
  bool submitting = false;
  bool deleting = false;

  Map<String, dynamic>? attendanceRecord;
  Map<String, dynamic>? existingRequest;
  String? existingRequestId;
  String? errorMessage;

  String get selectedDate => widget.initialDate ?? '';

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
    messageController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    return null;
  }

  List<AttendanceSession> _sessions(Map record) {
    final result = <AttendanceSession>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (final item in raw) {
        final map = _map(item);
        if (map != null && map['punchIn'] != null) {
          result.add(
            AttendanceSession(
              punchIn: map['punchIn'].toString(),
              punchOut: map['punchOut']?.toString(),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final map = _map(entry.value);
        if (map != null && map['punchIn'] != null) {
          result.add(
            AttendanceSession(
              punchIn: map['punchIn'].toString(),
              punchOut: map['punchOut']?.toString(),
            ),
          );
        }
      }
    }

    if (result.isEmpty && record['punchIn'] != null) {
      result.add(
        AttendanceSession(
          punchIn: record['punchIn'].toString(),
          punchOut: record['punchOut']?.toString(),
        ),
      );
    }

    return result;
  }

  AttendanceResult? _calculate(Map record) {
    final sessions = _sessions(record);
    if (sessions.isEmpty) return null;

    final hasOpen = sessions.any(
      (s) => s.punchOut == null || s.punchOut!.trim().isEmpty,
    );
    if (hasOpen) return null;

    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record['workFromHome'] == true,
    );
  }

  bool _requestContainsDate(Map request) {
    final dates = request['selectedDates'];
    if (dates is List) {
      return dates.map((e) => e.toString()).contains(selectedDate);
    }
    if (dates is Map) {
      return dates.values.map((e) => e.toString()).contains(selectedDate);
    }
    return request['date']?.toString() == selectedDate;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'REQUEST SENT — WAITING FOR ADMIN';
      case 'approved':
        return 'REQUEST APPROVED';
      case 'rejected':
        return 'REQUEST REJECTED';
      case 'returned':
        return 'RETURNED FOR CORRECTION';
      default:
        return status.toUpperCase();
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return AppColors.success;
      case 'rejected':
        return AppColors.danger;
      case 'returned':
        return AppColors.warning;
      default:
        return AppColors.primary;
    }
  }

  Future<void> _load() async {
    if (selectedDate.isEmpty) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'No Work-Pending date was selected.';
      });
      return;
    }

    try {
      final attendanceSnap = await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .child(selectedDate)
          .get();

      Map<String, dynamic>? record;
      final recordMap = _map(attendanceSnap.value);
      if (attendanceSnap.exists && recordMap != null) {
        record = recordMap;
      }

      final requestsSnap = await dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .get();

      Map<String, dynamic>? foundRequest;
      String? foundId;

      final requestsMap = _map(requestsSnap.value);
      if (requestsSnap.exists && requestsMap != null) {
        final entries = requestsMap.entries.toList()
          ..sort((a, b) {
            final aMap = _map(a.value);
            final bMap = _map(b.value);
            final aTime = aMap?['updatedAt']?.toString() ??
                aMap?['createdAt']?.toString() ??
                '';
            final bTime = bMap?['updatedAt']?.toString() ??
                bMap?['createdAt']?.toString() ??
                '';
            return bTime.compareTo(aTime);
          });

        for (final entry in entries) {
          final request = _map(entry.value);
          if (request == null || !_requestContainsDate(request)) continue;
          foundRequest = request;
          foundId = entry.key.toString();
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        attendanceRecord = record;
        existingRequest = foundRequest;
        existingRequestId = foundId;
        loading = false;
        errorMessage = null;

        final existingStatus =
            foundRequest?['status']?.toString().toLowerCase();
        if (existingStatus == 'returned' || existingStatus == 'rejected') {
          messageController.text =
              foundRequest?['message']?.toString() ?? '';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        loading = false;
        errorMessage = 'Could not load the compensation request.';
      });
    }
  }

  Future<void> _deleteRequest() async {
    final requestId = existingRequestId;
    final requestStatus =
        existingRequest?['status']?.toString().toLowerCase() ?? '';

    if (requestId == null ||
        (requestStatus != 'pending' &&
            requestStatus != 'returned' &&
            requestStatus != 'rejected')) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete request?'),
        content: const Text(
          'This will remove your compensation request for this date. You can send a new request afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => deleting = true);
    try {
      await dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .child(requestId)
          .remove();

      if (!mounted) return;
      setState(() {
        deleting = false;
        existingRequest = null;
        existingRequestId = null;
        messageController.clear();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compensation request deleted.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete the request: $e')),
      );
    }
  }

  Future<void> _submit() async {
    final message = messageController.text.trim();
    if (message.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please explain when and how you will compensate the pending time.',
          ),
        ),
      );
      return;
    }

    final currentStatus =
        existingRequest?['status']?.toString().toLowerCase();

    if (currentStatus == 'pending' || currentStatus == 'approved') {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentStatus == 'pending'
                ? 'A request has already been sent for $selectedDate.'
                : 'The request for $selectedDate has already been approved.',
          ),
        ),
      );
      return;
    }

    setState(() => submitting = true);

    try {
      final requestRef = existingRequestId == null
          ? dbRef.child('CompensationRequests').child(widget.employeeId).push()
          : dbRef
              .child('CompensationRequests')
              .child(widget.employeeId)
              .child(existingRequestId!);

      final now = DateTime.now().toIso8601String();
      final data = <String, dynamic>{
        'employeeId': widget.employeeId,
        'employeeName': (widget.employeeName ?? '').trim().isEmpty
            ? widget.employeeId
            : widget.employeeName!.trim(),
        'selectedDates': [selectedDate],
        'message': message,
        'status': 'pending',
        'updatedAt': now,
        if (existingRequestId == null) 'createdAt': now,
        if (currentStatus == 'returned' || currentStatus == 'rejected')
          'resubmittedAt': now,
        if (currentStatus == 'returned' || currentStatus == 'rejected')
          'adminMessage': null,
      };

      await requestRef.update(data);

      // Also notify the admin queue that a new/resubmitted request arrived.
      await NotificationCenter.sendAdmin(
        title: 'Compensation Request',
        message:
            '${widget.employeeName ?? widget.employeeId} submitted a compensation request for $selectedDate.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Compensation request sent to admin.')),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => submitting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send compensation request: $e')),
      );
    }
  }

  Widget _requestStatusCard() {
    final request = existingRequest;
    if (request == null) return const SizedBox.shrink();

    final status = request['status']?.toString().toLowerCase() ?? 'pending';
    final color = _statusColor(status);
    final adminMessage = request['adminMessage']?.toString().trim() ?? '';
    final canDelete = status == 'pending' ||
        status == 'returned' ||
        status == 'rejected';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                status == 'approved'
                    ? Icons.check_circle_rounded
                    : status == 'rejected'
                        ? Icons.cancel_rounded
                        : status == 'returned'
                            ? Icons.reply_rounded
                            : Icons.pending_actions_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _statusLabel(status),
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('This request is for $selectedDate only.'),
          if (adminMessage.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'Admin message:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(adminMessage),
          ],
          if (canDelete) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: deleting ? null : _deleteRequest,
                icon: deleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded),
                label: const Text('DELETE REQUEST'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.danger,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = attendanceRecord == null
        ? null
        : _calculate(attendanceRecord!);
    final isWorkPending = result?.dayType == DayType.workPending;
    final requestStatus =
        existingRequest?['status']?.toString().toLowerCase();
    final canSend = requestStatus == null ||
        requestStatus == 'returned' ||
        requestStatus == 'rejected';

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Compensation Request'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          errorMessage!,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (selectedDate.isNotEmpty) ...[
                      const Text(
                        'Work-Pending date',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.pending_actions_rounded,
                              color: AppColors.warning,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    selectedDate,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    result == null
                                        ? 'Attendance is not currently available for compensation.'
                                        : 'Outstanding: ${AttendanceCalculator.formatHours(result.shortfallHours)}',
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    _requestStatusCard(),
                    if (existingRequest != null) const SizedBox(height: 16),
                    if (isWorkPending && canSend) ...[
                      Text(
                        requestStatus == 'returned' || requestStatus == 'rejected'
                            ? 'Correct and resubmit'
                            : 'Message to Admin',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: messageController,
                        maxLines: 5,
                        decoration: InputDecoration(
                          hintText:
                              'Explain when and how you will compensate the pending time.',
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: AppColors.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      SizedBox(
                        height: 50,
                        child: ElevatedButton.icon(
                          onPressed: submitting ? null : _submit,
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
                            requestStatus == 'returned' ||
                                    requestStatus == 'rejected'
                                ? 'RESUBMIT TO ADMIN'
                                : 'SEND TO ADMIN',
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                      ),
                    ] else if (!isWorkPending && existingRequest == null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withOpacity(.08),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          'This date is no longer Work-Pending, so a compensation request cannot be created.',
                        ),
                      ),
                    ],
                  ],
                ),
    );
  }
}
