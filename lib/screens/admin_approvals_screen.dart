import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'dart:math';
import '../utils/app_colors.dart';
import '../utils/activity_logger.dart';
import '../utils/notification_center.dart';
import '../utils/attendance_calculator.dart';

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

class _AdminApprovalsScreenState extends State<AdminApprovalsScreen> with SingleTickerProviderStateMixin {
  late DatabaseReference dbRef;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _tabController = TabController(length: 4, vsync: this, initialIndex: widget.initialTabIndex.clamp(0, 3));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _resolveMessage(String key) async {
    await dbRef.child('AdminMessages').child(key).update({'status': 'resolved'});
  }

  String _generateOtp() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  Future<void> _generateOtpFor(String employeeId, String requestId) async {
    final otp = _generateOtp();
    final expiry = DateTime.now().add(const Duration(minutes: 10));

    await dbRef.child("DeviceApprovalRequests").child(employeeId).child(requestId).update({
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
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Done")),
        ],
      ),
    );
  }

  Future<void> _rejectDevice(String employeeId, String requestId) async {
    await dbRef.child("DeviceApprovalRequests").child(employeeId).child(requestId).update({"status": "rejected"});

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
  }

  Future<void> _reviewWfh(String employeeId, String dateKey, String decision) async {
    await dbRef.child("WorkFromHomeRequests").child(employeeId).child(dateKey).update({"status": decision});

    await ActivityLogger.log(
      adminId: widget.adminId,
      adminName: widget.adminName,
      action: decision == "approved" ? "Approved WFH" : "Rejected WFH",
      details: "$employeeId \u2014 $dateKey",
    );

    await NotificationCenter.send(
      employeeId: employeeId,
      title: decision == "approved" ? "Work From Home Approved" : "Work From Home Rejected",
      message: "Your WFH request for $dateKey was $decision.",
    );
  }

  /// Verifying an auto punch-out is NOT a shortcut to a free full day. The
  /// admin only supplies the real checkout time; the day is then run through
  /// the exact same 9-hour (gross, break included) rule as any normal punch.
  /// So a verified 9:00 AM \u2192 6:00 PM day is a full day, but a verified
  /// 9:00 AM \u2192 4:00 PM day is a mis-punch and owes the shortfall, same as
  /// if the employee had punched out themselves at 4:00 PM.
  Future<void> _reviewPunchRequest(Map<String, dynamic> request, String decision) async {
    final employeeId = request['employeeId'].toString();
    final date = request['date'].toString();
    TimeOfDay? selectedTime;
    if (decision == 'approved') {
      final suggested = AttendanceCalculator.toMinutes(request['suggestedPunchOut']?.toString()) ??
          AttendanceCalculator.checkOutEndMinutes;
      selectedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: suggested ~/ 60, minute: suggested % 60),
        helpText: 'Select verified checkout time',
      );
      if (selectedTime == null) return;
    }
    final selectedText = selectedTime?.format(context);
    await dbRef.child('PunchRequests').child(employeeId).child(date).update({
      'status': decision,
      'reviewedBy': widget.adminId,
      'reviewedAt': DateTime.now().toIso8601String(),
      if (selectedText != null) 'selectedPunchOut': selectedText,
    });

    if (decision == 'approved') {
      final punchIn = request['punchIn']?.toString();
      final result = AttendanceCalculator.calculate(punchIn: punchIn, punchOut: selectedText);
      final isFullDay = result.dayType == DayType.fullDay;

      await dbRef.child('Attendance').child(employeeId).child(date).update({
        'punchOut': selectedText,
        'status': 'Checked Out',
        'attendanceStatus': isFullDay
            ? 'Full Day (auto punch-out verified)'
            : 'Mis-punch (auto punch-out verified)',
        'approvedAutoCheckout': true,
        // The record is no longer an unresolved auto punch-out \u2014 it's a
        // normal, classified attendance record now.
        'autoPunchOut': null,
        'autoCheckedOutAt': null,
        'punchoutRequestStatus': null,
      });

      await NotificationCenter.send(
        employeeId: employeeId,
        title: 'Auto checkout approved',
        message: isFullDay
            ? 'Your checkout for $date was verified as $selectedText and the day was marked Full Day.'
            : 'Your checkout for $date was verified as $selectedText. That\'s short of 9 hours, so ${AttendanceCalculator.formatHours(result.shortfallHours)} was added to your outstanding compensation.',
      );
    } else {
      await dbRef.child('Attendance').child(employeeId).child(date).update({
        'status': 'Auto Checkout Rejected',
        'attendanceStatus': 'Auto punch-out rejected by admin',
      });
      await NotificationCenter.send(
        employeeId: employeeId,
        title: 'Auto checkout rejected',
        message: 'Your auto checkout request for $date was rejected.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Other Requests", style: TextStyle(color: Colors.white)),
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
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child('AdminMessages').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("No employee messages yet."));
        }
        final raw = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final items = raw.entries.toList()
          ..sort((a, b) => (Map<dynamic, dynamic>.from(b.value)["createdAt"] ?? "")
              .toString()
              .compareTo((Map<dynamic, dynamic>.from(a.value)["createdAt"] ?? "").toString()));

        if (items.isEmpty) return const Center(child: Text("No employee messages yet."));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (_, index) {
            final entry = items[index];
            final data = Map<dynamic, dynamic>.from(entry.value as Map);
            final resolved = data['status'] == 'resolved';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
              child: ListTile(
                leading: Icon(Icons.markunread_outlined, color: resolved ? AppColors.textSecondary : AppColors.primary),
                title: Text(data['employeeName']?.toString() ?? data['employeeId']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text(data['message']?.toString() ?? ''),
                trailing: resolved
                    ? const Text("Resolved", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11))
                    : TextButton(onPressed: () => _resolveMessage(entry.key.toString()), child: const Text('Resolve')),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildDeviceList() {
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child("DeviceApprovalRequests").onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("No device login requests"));
        }

        final empMap = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final items = <Map<String, dynamic>>[];

        empMap.forEach((empId, requestsMap) {
          final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
          requests.forEach((requestId, value) {
            final req = Map<dynamic, dynamic>.from(value as Map);
            if (req["status"] == "pending" || req["status"] == "otp_ready") {
              items.add({...req, "employeeId": empId, "requestId": requestId});
            }
          });
        });

        if (items.isEmpty) return const Center(child: Text("No pending device requests"));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final isOtpReady = item["status"] == "otp_ready";

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${item["employeeName"]} (${item["employeeId"]})", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("Device: ${item["deviceModel"]}", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  if (isOtpReady) ...[
                    const SizedBox(height: 6),
                    Text("OTP: ${item["otpCode"]}", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                          onPressed: () => _rejectDevice(item["employeeId"], item["requestId"]),
                          child: const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                          onPressed: () => _generateOtpFor(item["employeeId"], item["requestId"]),
                          child: Text(isOtpReady ? "Regenerate OTP" : "Generate OTP", style: const TextStyle(color: Colors.white)),
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
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child("WorkFromHomeRequests").onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
          return const Center(child: Text("No WFH requests"));
        }

        final empMap = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final items = <Map<String, dynamic>>[];

        empMap.forEach((empId, datesMap) {
          final dates = Map<dynamic, dynamic>.from(datesMap as Map);
          dates.forEach((dateKey, value) {
            final req = Map<dynamic, dynamic>.from(value as Map);
            if (req["status"] == "pending") {
              items.add({...req, "employeeId": empId, "dateKey": dateKey});
            }
          });
        });

        if (items.isEmpty) return const Center(child: Text("No pending WFH requests"));

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("${item["employeeName"] ?? item["employeeId"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text("Date: ${item["dateKey"]}", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                  if (item["address"] != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: AppColors.primary),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item["address"].toString(),
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
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
                          style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                          onPressed: () => _reviewWfh(item["employeeId"], item["dateKey"], "rejected"),
                          child: const Text("Reject"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                          onPressed: () => _reviewWfh(item["employeeId"], item["dateKey"], "approved"),
                          child: const Text("Approve", style: TextStyle(color: Colors.white)),
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
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child('PunchRequests').onValue,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text('No punch requests'));
        final employees = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
        final requests = <Map<String, dynamic>>[];
        employees.forEach((employeeId, values) {
          final dates = Map<dynamic, dynamic>.from(values as Map);
          dates.forEach((date, value) {
            final request = Map<dynamic, dynamic>.from(value as Map);
            // This queue is reserved for an employee who forgot to check out.
            // Short-day / compensation records have their own Attendance tab.
            if (request['status'] == 'pending' && request['type'] == 'auto_checkout') {
              requests.add({...request, 'employeeId': employeeId.toString(), 'date': date.toString()});
            }
          });
        });
        if (requests.isEmpty) return const Center(child: Text('No pending punch requests'));
        return ListView.builder(padding: const EdgeInsets.all(16), itemCount: requests.length, itemBuilder: (_, i) {
          final item = requests[i];
          return Container(margin: const EdgeInsets.only(bottom: 10), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${item['employeeId']} • ${item['date']}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4), Text('Check-in: ${item['punchIn'] ?? '--'} • No checkout recorded', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 4), Text('Suggested boundary: ${item['suggestedPunchOut'] ?? '11:59 PM'}', style: const TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 10), Row(children: [Expanded(child: OutlinedButton(onPressed: () => _reviewPunchRequest(item, 'rejected'), child: const Text('Reject'))), const SizedBox(width: 10), Expanded(child: ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: AppColors.success), onPressed: () => _reviewPunchRequest(item, 'approved'), child: const Text('Verify & choose time', style: TextStyle(color: Colors.white))))])
          ]));
        });
      },
    );
  }
}