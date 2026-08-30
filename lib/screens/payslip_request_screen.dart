import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class PayslipRequestScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const PayslipRequestScreen({super.key, required this.employeeId, required this.employeeName});

  @override
  State<PayslipRequestScreen> createState() => _PayslipRequestScreenState();
}

class _PayslipRequestScreenState extends State<PayslipRequestScreen> {
  late DatabaseReference dbRef;
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  final _noteController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final months = List.generate(12, (i) => DateTime(DateTime.now().year, DateTime.now().month - i, 1));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: months
              .map((m) => ListTile(
                    title: Text(DateFormat("MMMM yyyy").format(m)),
                    onTap: () => Navigator.pop(context, m),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => selectedMonth = picked);
  }

  Future<void> _submitRequest() async {
    if (_sending) return;
    setState(() => _sending = true);

    final monthKey = DateFormat("yyyy-MM").format(selectedMonth);
    try {
      await dbRef.child("PayslipRequests").child(widget.employeeId).push().set({
        "employeeId": widget.employeeId,
        "employeeName": widget.employeeName,
        "month": monthKey,
        "monthLabel": DateFormat("MMMM yyyy").format(selectedMonth),
        "note": _noteController.text.trim(),
        "status": "pending",
        "requestedAt": DateTime.now().toIso8601String(),
      });

      await NotificationCenter.sendAdmin(
        title: "Payslip Request",
        message: "${widget.employeeName} requested a payslip for ${DateFormat("MMMM yyyy").format(selectedMonth)}.",
      );

      if (!mounted) return;
      _noteController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Payslip request sent to admin.")),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case "ready":
        return AppColors.success;
      case "rejected":
        return AppColors.danger;
      default:
        return AppColors.warning;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case "ready":
        return "Ready";
      case "rejected":
        return "Rejected";
      default:
        return "Pending";
    }
  }

  Future<void> _deletePendingRequest(String requestId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete payslip request?'),
        content: const Text('This request will be removed before it is reviewed by an administrator.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: AppColors.danger), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await dbRef.child('PayslipRequests').child(widget.employeeId).child(requestId).remove();
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Payslip request deleted.')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text("Request Payslip", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(gradient: AppGradients.punchCard, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.hero),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [
                  Icon(Icons.receipt_long_outlined, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text("Payslip Request", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                ]),
                const SizedBox(height: 6),
                const Text("Pick a month and we'll notify admin to generate your payslip.", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("Month", style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickMonth,
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.divider), borderRadius: BorderRadius.circular(12)),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontWeight: FontWeight.w700)),
                        const Icon(Icons.calendar_today_outlined, size: 18, color: AppColors.primary),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text("Note (optional)", style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                TextField(
                  controller: _noteController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: "e.g. Needed for a loan application",
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _sending ? null : _submitRequest,
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30))),
              child: _sending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text("SEND REQUEST", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 24),
          const Text("Your Requests", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 12),
          StreamBuilder<DatabaseEvent>(
            stream: dbRef.child("PayslipRequests").child(widget.employeeId).onValue,
            builder: (context, snapshot) {
              if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
                return const Text("No payslip requests yet.", style: TextStyle(color: AppColors.textSecondary, fontSize: 13));
              }
              final raw = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
              final items = raw.entries.toList()
                ..sort((a, b) => (Map<dynamic, dynamic>.from(b.value)["requestedAt"] ?? "")
                    .toString()
                    .compareTo((Map<dynamic, dynamic>.from(a.value)["requestedAt"] ?? "").toString()));

              return Column(
                children: items.map((e) {
                  final data = Map<dynamic, dynamic>.from(e.value as Map);
                  final status = data["status"]?.toString() ?? "pending";
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(12)),
                          child: const Icon(Icons.receipt_long_outlined, color: AppColors.primary, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(data["monthLabel"]?.toString() ?? data["month"]?.toString() ?? "", style: const TextStyle(fontWeight: FontWeight.bold)),
                              if ((data["note"]?.toString() ?? "").isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(data["note"].toString(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: _statusColor(status).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text(_statusLabel(status), style: TextStyle(color: _statusColor(status), fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                        if (status == 'pending')
                          IconButton(
                            onPressed: () => _deletePendingRequest(e.key.toString()),
                            icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                            tooltip: 'Delete request',
                          ),
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
