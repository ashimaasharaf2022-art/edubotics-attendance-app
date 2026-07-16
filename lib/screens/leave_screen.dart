import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/leave_constants.dart';
import '../utils/app_colors.dart';
import 'apply_leave_screen.dart';
import '../utils/email_alert_helper.dart';

class LeaveScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const LeaveScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends State<LeaveScreen> {
  late DatabaseReference dbRef;

  bool loading = true;
  Map<String, int> balance = {};
  List<Map<dynamic, dynamic>> requests = [];
  String filter = "all";

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _loadData();
  }

  int get _currentYear => DateTime.now().year;

  Future<void> _loadData() async {
    setState(() => loading = true);

    try {
      final balanceSnap = await dbRef
          .child("LeaveBalances")
          .child(widget.employeeId)
          .child(_currentYear.toString())
          .get();

      Map<String, int> loadedBalance = Map.from(LeaveConstants.defaultQuota);
      if (balanceSnap.exists) {
        final data = Map<dynamic, dynamic>.from(balanceSnap.value as Map);
        for (final type in LeaveConstants.allTypes) {
          if (data[type] != null) {
            loadedBalance[type] = int.tryParse(data[type].toString()) ?? LeaveConstants.defaultQuota[type]!;
          }
        }
      } else {
        await dbRef
            .child("LeaveBalances")
            .child(widget.employeeId)
            .child(_currentYear.toString())
            .set(LeaveConstants.defaultQuota);
      }

      final requestsSnap = await dbRef.child("LeaveRequests").child(widget.employeeId).get();

      List<Map<dynamic, dynamic>> loadedRequests = [];
      if (requestsSnap.exists) {
        final data = Map<dynamic, dynamic>.from(requestsSnap.value as Map);
        data.forEach((requestId, value) {
          final req = Map<dynamic, dynamic>.from(value as Map);
          req["requestId"] = requestId;
          loadedRequests.add(req);
        });
        loadedRequests.sort((a, b) => (b["appliedOn"] ?? "").toString().compareTo((a["appliedOn"] ?? "").toString()));
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
        SnackBar(content: Text("Failed to load leave data: $e")),
      );
    }
  }

  Future<void> _showApplyDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ApplyLeaveScreen(balance: balance)),
    );

    if (result == null) return;

    await _submitLeaveRequest(
      leaveType: result["leaveType"],
      fromDate: result["fromDate"],
      toDate: result["toDate"],
      numberOfDays: result["numberOfDays"],
      reason: result["reason"],
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
    final requestRef = dbRef.child("LeaveRequests").child(widget.employeeId).push();

    await requestRef.set({
      "employeeId": widget.employeeId,
      "employeeName": widget.employeeName,
      "leaveType": leaveType,
      "fromDate": DateFormat("yyyy-MM-dd").format(fromDate),
      "toDate": DateFormat("yyyy-MM-dd").format(toDate),
      "numberOfDays": numberOfDays,
      "reason": reason,
      "status": "pending",
      "appliedOn": DateFormat("yyyy-MM-dd").format(DateTime.now()),
    });

    await EmailAlertHelper.sendAlert(
      subject: "New Leave Request \u2014 ${widget.employeeName}",
      message:
          "${widget.employeeName} (${widget.employeeId}) has requested "
          "${LeaveConstants.displayName(leaveType)} from "
          "${DateFormat("dd MMM yyyy").format(fromDate)} to "
          "${DateFormat("dd MMM yyyy").format(toDate)} ($numberOfDays day(s)).\n\n"
          "Reason: $reason\n\n"
          "Open the app to approve or reject this request.",
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Leave request submitted")),
    );
    _loadData();
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Error : $e")),
    );
  }
}
  Future<void> _cancelRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Cancel Request"),
        content: const Text("Withdraw this leave request?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("No")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Yes, Cancel")),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await dbRef.child("LeaveRequests").child(widget.employeeId).child(requestId).remove();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Request cancelled")));
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "approved":
        return AppColors.success;
      case "rejected":
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = filter == "all" ? requests : requests.where((r) => r["leaveType"] == filter).toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text(
          "Leaves",
          style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 22),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add, color: AppColors.textPrimary),
            onPressed: _showApplyDialog,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  Row(
                    children: LeaveConstants.allTypes.map((type) {
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: AppShadows.card,
                          ),
                          child: Column(
                            children: [
                              Text(
                                "${balance[type] ?? 0}",
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                LeaveConstants.displayName(type),
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: AppShadows.card,
                    ),
                    child: Row(
                      children: [
                        _filterChip("All", "all"),
                        ...LeaveConstants.allTypes.map((t) => _filterChip(LeaveConstants.displayName(t), t)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text("No leave requests yet", style: TextStyle(color: AppColors.textSecondary)),
                      ),
                    )
                  else
                    ...filtered.map((r) {
                      final status = r["status"]?.toString() ?? "pending";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: AppShadows.card,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "${r["numberOfDays"]} Day${(r["numberOfDays"] ?? 1) > 1 ? 's' : ''} Application",
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: _statusColor(status).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    status[0].toUpperCase() + status.substring(1),
                                    style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "${r["fromDate"]} to ${r["toDate"]}",
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              LeaveConstants.displayName(r["leaveType"]?.toString() ?? ""),
                              style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              "Reason: ${r["reason"] ?? "--"}",
                              style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                            ),
                            if (status == "pending") ...[
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () => _cancelRequest(r["requestId"].toString()),
                                  style: TextButton.styleFrom(foregroundColor: AppColors.danger),
                                  child: const Text("Cancel Request"),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }

  Widget _filterChip(String label, String value) {
    final selected = filter == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => filter = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(26),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}