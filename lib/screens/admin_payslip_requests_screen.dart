import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class AdminPayslipRequestsScreen extends StatefulWidget {
  final String adminId;
  final String adminName;

  const AdminPayslipRequestsScreen({
    super.key,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<AdminPayslipRequestsScreen> createState() => _AdminPayslipRequestsScreenState();
}

class _AdminPayslipRequestsScreenState extends State<AdminPayslipRequestsScreen> {
  late DatabaseReference dbRef;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  Future<void> _updatePayslipStatus(String employeeId, String key, String status) async {
    await dbRef.child('PayslipRequests').child(employeeId).child(key).update({'status': status});
    final snap = await dbRef.child('PayslipRequests').child(employeeId).child(key).get();
    if (!snap.exists) return;
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    await NotificationCenter.send(
      employeeId: employeeId,
      title: status == 'ready' ? 'Payslip Ready' : 'Payslip Request Update',
      message: status == 'ready'
          ? 'Your payslip for ${data['monthLabel'] ?? data['month']} is ready. Please check with HR.'
          : 'Your payslip request for ${data['monthLabel'] ?? data['month']} was $status.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Payslip Requests", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: dbRef.child('PayslipRequests').onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("No payslip requests yet."));
          }
          final empMap = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
          final items = <Map<String, dynamic>>[];
          empMap.forEach((empId, requestsMap) {
            final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
            requests.forEach((key, value) {
              final req = Map<dynamic, dynamic>.from(value as Map);
              items.add({...req, "employeeId": empId.toString(), "key": key.toString()});
            });
          });
          items.sort((a, b) => (b["requestedAt"] ?? "").toString().compareTo((a["requestedAt"] ?? "").toString()));

          if (items.isEmpty) return const Center(child: Text("No payslip requests yet."));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (_, index) {
              final item = items[index];
              final status = item["status"]?.toString() ?? "pending";
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${item["employeeName"] ?? item["employeeId"]}", style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text("Month: ${item["monthLabel"] ?? item["month"]}", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    if ((item["note"]?.toString() ?? "").isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(item["note"].toString(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                    ],
                    const SizedBox(height: 10),
                    if (status == "pending")
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(foregroundColor: AppColors.danger),
                              onPressed: () => _updatePayslipStatus(item["employeeId"], item["key"], "rejected"),
                              child: const Text("Reject"),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
                              onPressed: () => _updatePayslipStatus(item["employeeId"], item["key"], "ready"),
                              child: const Text("Mark Ready", style: TextStyle(color: Colors.white)),
                            ),
                          ),
                        ],
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: (status == "ready" ? AppColors.success : AppColors.danger).withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          status == "ready" ? "Ready" : "Rejected",
                          style: TextStyle(color: status == "ready" ? AppColors.success : AppColors.danger, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}
