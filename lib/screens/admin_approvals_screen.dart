import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import '../utils/app_colors.dart';
import '../utils/activity_logger.dart';
import '../utils/notification_center.dart';
import '../utils/attendance_calculator.dart';
import 'admin_employee_attendance_view_screen.dart';

class AdminApprovalsScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final int initialTabIndex;

  const AdminApprovalsScreen({
    super.key,
    required this.adminId,
    required this.adminName,
    this.initialTabIndex = 0,
  });

  @override
  State<AdminApprovalsScreen> createState() => _AdminApprovalsScreenState();
}

class _AdminApprovalsScreenState
    extends State<AdminApprovalsScreen>
    with SingleTickerProviderStateMixin {
  late DatabaseReference dbRef;
  late TabController _tabController;

  Map<dynamic, dynamic>? _asMap(dynamic value) {
    if (value is Map) {
      return Map<dynamic, dynamic>.from(value);
    }
    return null;
  }

  List<Map<String, dynamic>> _sessionsFromRecord(Map record) {
    final sessions = <Map<String, dynamic>>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (final item in raw) {
        final map = _asMap(item);
        if (map != null && map['punchIn'] != null) {
          sessions.add(
            map.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final map = _asMap(entry.value);
        if (map != null && map['punchIn'] != null) {
          sessions.add(
            map.map((key, value) => MapEntry(key.toString(), value)),
          );
        }
      }
    }

    if (sessions.isEmpty && record['punchIn'] != null) {
      sessions.add({
        'punchIn': record['punchIn'],
        if (record['punchOut'] != null) 'punchOut': record['punchOut'],
      });
    }

    return sessions;
  }

  Widget _streamError(Object? error, {VoidCallback? onRetry}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 40),
            const SizedBox(height: 12),
            const Text(
              "Unable to load requests",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              "Please check the connection and try again.",
              textAlign: TextAlign.center,
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text("Retry"),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _tabController = TabController(
      length: 4,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 3),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resolveMessage(String key) async {
    await dbRef.child('AdminMessages').child(key).update({
      'status': 'resolved',
    });
    if (mounted) setState(() {});
  }

  String _generateOtp() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  Future<void> _generateOtpFor(
    String employeeId,
    String requestId,
  ) async {
    final otp = _generateOtp();
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    await dbRef
        .child("DeviceApprovalRequests")
        .child(employeeId)
        .child(requestId)
        .update({
      "status": "otp_ready",
      "otpCode": otp,
      "otpExpiry": expiry.toIso8601String(),
    });

    await ActivityLogger.log(
      adminId: widget.adminId,
      adminName: widget.adminName,
      action: "Generated Device OTP",
      details: employeeId,
    );

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("OTP Generated"),
        content: Text(
          "Give this code to the employee (valid for 10 minutes):\n\n$otp",
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Done"),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectDevice(
    String employeeId,
    String requestId,
  ) async {
    await dbRef
        .child("DeviceApprovalRequests")
        .child(employeeId)
        .child(requestId)
        .update({
      "status": "rejected",
    });

    await ActivityLogger.log(
      adminId: widget.adminId,
      adminName: widget.adminName,
      action: "Rejected Device Login",
      details: employeeId,
    );

    await NotificationCenter.send(
      employeeId: employeeId,
      title: "Device Login Rejected",
      message: "Your new-device login request was rejected by the admin.",
    );
    if (mounted) setState(() {});
  }

  Future<void> _reviewWfh(
    String employeeId,
    String dateKey,
    String decision,
  ) async {
    await dbRef
        .child("WorkFromHomeRequests")
        .child(employeeId)
        .child(dateKey)
        .update({
      "status": decision,
    });

    await ActivityLogger.log(
      adminId: widget.adminId,
      adminName: widget.adminName,
      action: decision == "approved"
          ? "Approved WFH"
          : "Rejected WFH",
      details: "$employeeId — $dateKey",
    );

    await NotificationCenter.send(
      employeeId: employeeId,
      title: decision == "approved"
          ? "Work From Home Approved"
          : "Work From Home Rejected",
      message: "Your WFH request for $dateKey was $decision.",
    );
    if (mounted) setState(() {});
  }

  /// Handles the existing Punchout Request workflow.
  ///
  /// MIS-PUNCH is only a temporary system state.
  ///
  /// When an admin approves the request:
  ///   1. The admin chooses the employee's actual punch-out time.
  ///   2. The attendance is recalculated using the actual punch-in
  ///      and selected punch-out.
  ///   3. The final attendance becomes either:
  ///        - Full Day
  ///        - Work-Pending
  ///   4. Temporary automatic/MIS-PUNCH fields are removed.
  ///   5. 11:59 PM is NOT retained as the actual punch-out.
  ///   6. No punch-out GPS/location is invented.

  Future<void> _viewPunchAttendance(
    Map<String, dynamic> request,
  ) async {
    final employeeId = request['employeeId']?.toString() ?? '';
    final date = request['date']?.toString() ?? '';
    if (employeeId.isEmpty || date.isEmpty || !mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminEmployeeAttendanceViewScreen(
          employeeId: employeeId,
          employeeName: request['employeeName']?.toString() ?? '',
          focusDates: {date},
        ),
      ),
    );
  }

  Future<void> _reviewPunchRequest(
    Map<String, dynamic> request,
    String decision, {
    bool editTime = true,
  }) async {
    final employeeId = request['employeeId']?.toString() ?? '';
    final date = request['date']?.toString() ?? '';
    if (employeeId.isEmpty || date.isEmpty) return;

    TimeOfDay? selectedTime;

    if (decision == 'approved') {
      final requestedMinutes = AttendanceCalculator.toMinutes(
        request['actualPunchOutRequested']?.toString(),
      );

      final suggested = requestedMinutes ??
          AttendanceCalculator.toMinutes(
            request['suggestedPunchOut']?.toString(),
          ) ??
          AttendanceCalculator.toMinutes('11:59 PM')!;

      if (editTime) {
        selectedTime = await showTimePicker(
          context: context,
          initialTime: TimeOfDay(
            hour: suggested ~/ 60,
            minute: suggested % 60,
          ),
          helpText: 'Edit / verify checkout time',
        );

        if (selectedTime == null) return;
      } else {
        if (requestedMinutes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('No punch-out time was submitted by the employee.'),
              ),
            );
          }
          return;
        }

        selectedTime = TimeOfDay(
          hour: requestedMinutes ~/ 60,
          minute: requestedMinutes % 60,
        );
      }
    }

    final selectedText = selectedTime?.format(context);
    final now = DateTime.now().toIso8601String();
    final requestRef = dbRef
        .child('PunchRequests')
        .child(employeeId)
        .child(date);

    if (decision == 'rejected') {
      await requestRef.update({
        'status': 'rejected',
        'reviewedBy': widget.adminId,
        'reviewedAt': now,
      });

      await dbRef
          .child('Attendance')
          .child(employeeId)
          .child(date)
          .update({
        'status': 'MIS-PUNCH',
        'attendanceStatus': 'MIS-PUNCH',
        'punchoutRequestStatus': 'rejected',
      });

      await ActivityLogger.log(
        adminId: widget.adminId,
        adminName: widget.adminName,
        action: 'Rejected Punchout Request',
        details: '$employeeId — $date',
      );

      await NotificationCenter.send(
        employeeId: employeeId,
        title: 'Punchout request rejected',
        message:
            'Your punchout request for $date was rejected by the admin. You can delete the request from Attendance History and submit it again if needed.',
      );

      if (mounted) setState(() {});
      return;
    }

    // Read the real attendance record. The checkout must be written to the
    // actual LAST open session, not only to the old top-level compatibility
    // field.
    final attendanceRef = dbRef
        .child('Attendance')
        .child(employeeId)
        .child(date);
    final attendanceSnap = await attendanceRef.get();
    final record = _asMap(attendanceSnap.value);

    if (record == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Attendance record could not be found.')),
        );
      }
      return;
    }

    final sessions = _sessionsFromRecord(record);
    if (sessions.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No attendance session was found.')),
        );
      }
      return;
    }

    final lastIndex = sessions.length - 1;
    final lastOut = sessions[lastIndex]['punchOut']?.toString().trim();

    // The MIS-PUNCH request must correspond to the last unfinished session.
    if (lastOut != null && lastOut.isNotEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This attendance session is already checked out.'),
          ),
        );
      }
      return;
    }

    sessions[lastIndex]['punchOut'] = selectedText;

    // Remove temporary fields from every session before saving the final
    // corrected attendance. Do not create a punch-out location if none exists.
    for (final session in sessions) {
      session.remove('temporaryPunchOut');
      session.remove('autoPunchOut');
      session.remove('autoCheckedOutAt');
      session.remove('approvedAutoCheckout');
      session.remove('misPunch');
      session.remove('mis_punch');
      session.remove('misPunchDetectedAt');
    }

    final calculationSessions = sessions
        .map(
          (session) => AttendanceSession(
            punchIn: session['punchIn'].toString(),
            punchOut: session['punchOut']?.toString(),
          ),
        )
        .toList();

    final result = AttendanceCalculator.calculateFromSessions(
      calculationSessions,
      workFromHome: record['workFromHome'] == true,
    );

    String finalAttendanceStatus;
    switch (result.dayType) {
      case DayType.fullDay:
        finalAttendanceStatus = 'FULL DAY';
        break;
      case DayType.workPending:
        finalAttendanceStatus = 'WORK-PENDING';
        break;
      case DayType.absent:
        finalAttendanceStatus = 'ABSENT';
        break;
    }

    final update = <String, dynamic>{
      'sessions': sessions,
      'punchIn': sessions.first['punchIn'],
      'punchOut': sessions.last['punchOut'],
      'status': 'Checked Out',
      'attendanceStatus': finalAttendanceStatus,
      'netWorkMinutes': (result.netHours * 60).round(),
      'shortfallMinutes': (result.shortfallHours * 60).round(),
      'extraWorkMinutes': (result.extraHours * 60).round(),
      'punchoutRequestStatus': null,
      'misPunch': null,
      'mis_punch': null,
      'misPunchDetectedAt': null,
      'temporaryPunchOut': null,
      'autoPunchOut': null,
      'autoCheckedOutAt': null,
      'approvedAutoCheckout': null,
    };

    // Keep existing real location data. Only update a location if the
    // selected session already contains it; never invent a GPS position.
    if (sessions.last['punchOutLat'] != null) {
      update['punchOutLat'] = sessions.last['punchOutLat'];
    }
    if (sessions.last['punchOutLng'] != null) {
      update['punchOutLng'] = sessions.last['punchOutLng'];
    }
    if (sessions.last['punchOutAddress'] != null) {
      update['punchOutAddress'] = sessions.last['punchOutAddress'];
    }

    await attendanceRef.update(update);

    await requestRef.update({
      'status': 'approved',
      'reviewedBy': widget.adminId,
      'reviewedAt': now,
      'selectedPunchOut': selectedText,
    });

    await ActivityLogger.log(
      adminId: widget.adminId,
      adminName: widget.adminName,
      action: 'Verified Punchout Request',
      details:
          '$employeeId — $date — actual checkout: $selectedText — $finalAttendanceStatus',
    );

    final notificationMessage = result.dayType == DayType.fullDay
        ? 'Your checkout for $date was verified as $selectedText and the day was marked FULL DAY.'
        : result.dayType == DayType.workPending
            ? 'Your checkout for $date was verified as $selectedText. The day is WORK-PENDING and ${AttendanceCalculator.formatHours(result.shortfallHours)} remains outstanding.'
            : 'Your checkout for $date was verified as $selectedText.';

    await NotificationCenter.send(
      employeeId: employeeId,
      title: 'Checkout verified',
      message: notificationMessage,
    );

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "Other Requests",
          style: TextStyle(color: Colors.white),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: "Messages"),
            Tab(text: "Device Logins"),
            Tab(text: "Work From Home"),
            Tab(text: "Punchout Requests"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildMessagesList(),
          _buildDeviceList(),
          _buildWfhList(),
          _buildPunchRequests(),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return FutureBuilder<DatabaseEvent>(
      future: dbRef.child('AdminMessages').once(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _streamError(snapshot.error);
        }

        final raw = _asMap(
          snapshot.hasData ? snapshot.data!.snapshot.value : null,
        );

        if (raw == null || raw.isEmpty) {
          return const Center(child: Text("No employee messages yet."));
        }

        final items = raw.entries.where((entry) => entry.value is Map).toList()
          ..sort(
            (a, b) {
              final aMap = _asMap(a.value) ?? {};
              final bMap = _asMap(b.value) ?? {};
              return (bMap["createdAt"] ?? "")
                  .toString()
                  .compareTo((aMap["createdAt"] ?? "").toString());
            },
          );

        if (items.isEmpty) {
          return const Center(child: Text("No employee messages yet."));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final entry = items[index];
            final data = _asMap(entry.value) ?? {};
            final resolved = data['status'] == 'resolved';

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                boxShadow: AppShadows.card,
              ),
              child: ListTile(
                leading: Icon(
                  Icons.markunread_outlined,
                  color: resolved ? AppColors.textSecondary : AppColors.primary,
                ),
                title: Text(
                  data['employeeName']?.toString() ??
                      data['employeeId']?.toString() ??
                      '',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Text(data['message']?.toString() ?? ''),
                trailing: resolved
                    ? const Text(
                        "Resolved",
                        style: TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      )
                    : TextButton(
                        onPressed: () => _resolveMessage(entry.key.toString()),
                        child: const Text('Resolve'),
                      ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDeviceList() {
    return FutureBuilder<DatabaseEvent>(
      future: dbRef.child("DeviceApprovalRequests").once(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _streamError(snapshot.error);
        }

        final empMap = _asMap(
          snapshot.hasData ? snapshot.data!.snapshot.value : null,
        );

        if (empMap == null || empMap.isEmpty) {
          return const Center(child: Text("No device login requests"));
        }

        final items = <Map<String, dynamic>>[];

        empMap.forEach((empId, requestsMap) {
          final requests = _asMap(requestsMap);
          if (requests == null) return;

          requests.forEach((requestId, value) {
            final req = _asMap(value);
            if (req == null) return;

            final status = req["status"]?.toString().toLowerCase();
            if (status == "pending" || status == "otp_ready") {
              items.add({
                ...req.map((key, value) => MapEntry(key.toString(), value)),
                "employeeId": empId.toString(),
                "requestId": requestId.toString(),
              });
            }
          });
        });

        if (items.isEmpty) {
          return const Center(child: Text("No pending device requests"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isOtpReady = item["status"]?.toString().toLowerCase() == "otp_ready";

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${item["employeeName"] ?? item["employeeId"]} (${item["employeeId"]})",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Device: ${item["deviceModel"] ?? "--"}",
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (isOtpReady) ...[
                    const SizedBox(height: 6),
                    Text(
                      "OTP: ${item["otpCode"] ?? "--"}",
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: () => _rejectDevice(
                            item["employeeId"].toString(),
                            item["requestId"].toString(),
                          ),
                          child: const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                          ),
                          onPressed: () => _generateOtpFor(
                            item["employeeId"].toString(),
                            item["requestId"].toString(),
                          ),
                          child: Text(
                            isOtpReady ? "Regenerate OTP" : "Generate OTP",
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildWfhList() {
    return FutureBuilder<DatabaseEvent>(
      future: dbRef.child("WorkFromHomeRequests").once(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _streamError(snapshot.error);
        }

        final empMap = _asMap(
          snapshot.hasData ? snapshot.data!.snapshot.value : null,
        );

        if (empMap == null || empMap.isEmpty) {
          return const Center(child: Text("No WFH requests"));
        }

        final items = <Map<String, dynamic>>[];

        empMap.forEach((empId, datesMap) {
          final dates = _asMap(datesMap);
          if (dates == null) return;

          dates.forEach((dateKey, value) {
            final req = _asMap(value);
            if (req == null) return;

            if (req["status"]?.toString().toLowerCase() == "pending") {
              items.add({
                ...req.map((key, value) => MapEntry(key.toString(), value)),
                "employeeId": empId.toString(),
                "dateKey": dateKey.toString(),
              });
            }
          });
        });

        if (items.isEmpty) {
          return const Center(child: Text("No pending WFH requests"));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "${item["employeeName"] ?? item["employeeId"]} (${item["employeeId"]})",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Date: ${item["dateKey"]}",
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  if (item["address"] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item["address"].toString(),
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                          ),
                          onPressed: () => _reviewWfh(
                            item["employeeId"].toString(),
                            item["dateKey"].toString(),
                            "rejected",
                          ),
                          child: const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          onPressed: () => _reviewWfh(
                            item["employeeId"].toString(),
                            item["dateKey"].toString(),
                            "approved",
                          ),
                          child: const Text(
                            "Approve",
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildPunchRequests() {
    return FutureBuilder<DatabaseEvent>(
      future: dbRef.child('PunchRequests').once(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _streamError(snapshot.error);
        }

        final employees = _asMap(
          snapshot.hasData ? snapshot.data!.snapshot.value : null,
        );

        if (employees == null || employees.isEmpty) {
          return const Center(child: Text('No punch requests'));
        }

        final requests = <Map<String, dynamic>>[];

        employees.forEach((employeeId, values) {
          final dates = _asMap(values);
          if (dates == null) return;

          dates.forEach((date, value) {
            final request = _asMap(value);
            if (request == null) return;

            final status = request['status']?.toString().toLowerCase();
            final type = request['type']?.toString().toLowerCase();

            if (status == 'pending' && type == 'mis_punch') {
              requests.add({
                ...request.map((key, value) => MapEntry(key.toString(), value)),
                'employeeId': employeeId.toString(),
                'date': date.toString(),
              });
            }
          });
        });

        if (requests.isEmpty) {
          return const Center(child: Text('No pending punch requests'));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          itemBuilder: (_, i) {
            final item = requests[i];

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                boxShadow: AppShadows.card,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item['employeeName'] ?? item['employeeId']} (${item['employeeId']}) • ${item['date']}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Check-in: ${item['punchIn'] ?? '--'} • No checkout recorded',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Requested punch-out: ${item['actualPunchOutRequested'] ?? '--'}',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (item['message'] != null &&
                      item['message'].toString().trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Employee note: ${item['message']}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ],
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: () => _viewPunchAttendance(item),
                    icon: const Icon(Icons.visibility_outlined, size: 16),
                    label: const Text(
                      'VIEW ATTENDANCE',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _reviewPunchRequest(item, 'rejected'),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _reviewPunchRequest(
                            item,
                            'approved',
                            editTime: false,
                          ),
                          child: const Text('Approve'),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.success,
                          ),
                          onPressed: () => _reviewPunchRequest(
                            item,
                            'approved',
                            editTime: true,
                          ),
                          child: const Text(
                            'Edit',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
