import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/leave_constants.dart';
import '../utils/activity_logger.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class AdminLeaveScreen extends StatefulWidget {
  final String adminId;
  final String adminName;

  const AdminLeaveScreen({
    super.key,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<AdminLeaveScreen> createState() => _AdminLeaveScreenState();
}

class _AdminLeaveScreenState extends State<AdminLeaveScreen> {
  late DatabaseReference dbRef;

  bool loading = true;
  List<Map<dynamic, dynamic>> allRequests = [];
  String filterStatus = "all";

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);

    try {
      final snapshot = await dbRef.child("LeaveRequests").get();

      List<Map<dynamic, dynamic>> loaded = [];
      if (snapshot.exists) {
        final empMap = Map<dynamic, dynamic>.from(snapshot.value as Map);
        empMap.forEach((employeeId, requestsMap) {
          final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
          requests.forEach((requestId, value) {
            final req = Map<dynamic, dynamic>.from(value as Map);
            req["requestId"] = requestId;
            req["employeeIdKey"] = employeeId;
            loaded.add(req);
          });
        });
        loaded.sort((a, b) =>
            (b["appliedOn"] ?? "").toString().compareTo((a["appliedOn"] ?? "").toString()));
      }

      if (!mounted) return;
      setState(() {
        allRequests = loaded;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load leave requests: $e")),
      );
    }
  }

  /// Returns [allRequests] filtered by [filterStatus]. "all" returns
  /// everything unfiltered; any other value matches the request's
  /// stored status field exactly (defaulting to "pending" if a
  /// request somehow has no status field at all).
  List<Map<dynamic, dynamic>> get _filteredRequests {
    if (filterStatus == "all") return allRequests;
    return allRequests.where((r) {
      final status = (r["status"]?.toString() ?? "pending").trim().toLowerCase();
      return status == filterStatus;
    }).toList();
  }

  Future<void> _reviewRequest(Map<dynamic, dynamic> request, String decision) async {
    final employeeId = request["employeeIdKey"].toString();
    final requestId = request["requestId"].toString();
    final leaveType = request["leaveType"].toString();
    final numberOfDays = int.tryParse(request["numberOfDays"].toString()) ?? 0;
    final fromDate = request["fromDate"].toString();
    final year = DateTime.parse(fromDate).year.toString();

    try {
      final requestRef = dbRef
          .child("LeaveRequests")
          .child(employeeId)
          .child(requestId);

      await requestRef.update({
        "status": decision,
        "reviewedBy": widget.adminId,
        "reviewedOn": DateTime.now().toString().split(" ").first,
      });

      if (decision == "approved") {
        final balanceRef = dbRef
            .child("LeaveBalances")
            .child(employeeId)
            .child(year)
            .child(leaveType);

        final currentSnap = await balanceRef.get();
        final current = currentSnap.exists
            ? int.tryParse(currentSnap.value.toString()) ?? 0
            : LeaveConstants.defaultQuota[leaveType] ?? 0;

        final updated = (current - numberOfDays).clamp(0, 9999);
        await balanceRef.set(updated);
      }

      await ActivityLogger.log(
        adminId: widget.adminId,
        adminName: widget.adminName,
        action: decision == "approved" ? "Approved Leave" : "Rejected Leave",
        details: "${request["employeeName"]} \u2014 ${LeaveConstants.displayName(leaveType)}, $numberOfDays day(s)",
      );

      await NotificationCenter.send(
        employeeId: employeeId,
        title: decision == "approved" ? "Leave Approved" : "Leave Rejected",
        message: "Your ${LeaveConstants.displayName(leaveType)} request ($fromDate to ${request["toDate"]}) was $decision.",
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Request $decision")),
      );
      _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error : $e")),
      );
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
    final filtered = _filteredRequests;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "Leave Requests",
          style: TextStyle(color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: loading ? null : _loadData,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment<String>(value: "all", label: Text("All")),
                      ButtonSegment<String>(value: "approved", label: Text("Approved")),
                      ButtonSegment<String>(value: "rejected", label: Text("Rejected")),
                      ButtonSegment<String>(value: "pending", label: Text("Pending")),
                    ],
                    selected: <String>{filterStatus},
                    onSelectionChanged: (Set<String> selection) {
                      setState(() => filterStatus = selection.first);
                    },
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor: AppColors.primary,
                      selectedForegroundColor: Colors.white,
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? const Center(child: Text("No leave requests"))
                      : RefreshIndicator(
                          onRefresh: _loadData,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final r = filtered[index];
                              final status = (r["status"]?.toString() ?? "pending").trim().toLowerCase();

                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Expanded(
                                            child: Text(
                                              "${r["employeeName"]} (${r["employeeIdKey"]})",
                                              style: const TextStyle(fontWeight: FontWeight.bold),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: _statusColor(status).withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              status[0].toUpperCase() + status.substring(1),
                                              style: TextStyle(
                                                color: _statusColor(status),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(LeaveConstants.displayName(r["leaveType"]?.toString() ?? "")),
                                      Text("${r["fromDate"]} to ${r["toDate"]} (${r["numberOfDays"]} day(s))"),
                                      const SizedBox(height: 4),
                                      Text(
                                        "Reason: ${r["reason"] ?? "--"}",
                                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                                      ),
                                      if (status == "pending") ...[
                                        const SizedBox(height: 12),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: OutlinedButton(
                                                style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                                                onPressed: () => _reviewRequest(r, "rejected"),
                                                child: const Text("Reject"),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: ElevatedButton(
                                                style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                                                onPressed: () => _reviewRequest(r, "approved"),
                                                child: const Text(
                                                  "Approve",
                                                  style: TextStyle(color: Colors.white),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}