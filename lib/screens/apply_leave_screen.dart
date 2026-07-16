import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../widgets/calendar_range_picker.dart';
import '../utils/leave_constants.dart';

class ApplyLeaveScreen extends StatefulWidget {
  final Map<String, int> balance;

  const ApplyLeaveScreen({super.key, required this.balance});

  @override
  State<ApplyLeaveScreen> createState() => _ApplyLeaveScreenState();
}

class _ApplyLeaveScreenState extends State<ApplyLeaveScreen> {
  String leaveType = LeaveConstants.casual;
  DateTime? fromDate;
  DateTime? toDate;
  final reasonController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final days = (fromDate != null && toDate != null) ? toDate!.difference(fromDate!).inDays + 1 : 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: const Text("New Leave", style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
              child: DropdownButtonFormField<String>(
                value: leaveType,
                decoration: const InputDecoration(labelText: "Type", border: InputBorder.none),
                items: LeaveConstants.allTypes.map((t) => DropdownMenuItem(
                  value: t,
                  child: Text("${LeaveConstants.displayName(t)} (${widget.balance[t] ?? 0} left)"),
                )).toList(),
                onChanged: (value) { if (value != null) setState(() => leaveType = value); },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
              child: TextField(
                controller: reasonController,
                maxLines: 2,
                decoration: const InputDecoration(labelText: "Reason", border: InputBorder.none),
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
              child: CalendarRangePicker(
                initialFrom: fromDate,
                initialTo: toDate,
                onRangeSelected: (from, to) => setState(() { fromDate = from; toDate = to; }),
              ),
            ),
            if (fromDate != null) ...[
              const SizedBox(height: 8),
              Text(
                toDate != null
                    ? "${DateFormat('dd MMM').format(fromDate!)} to ${DateFormat('dd MMM yyyy').format(toDate!)}"
                    : "From: ${DateFormat('dd MMM yyyy').format(fromDate!)} — select end date",
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: days == 0 ? null : () {
                  if (reasonController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter a reason")));
                    return;
                  }
                  final availableBalance = widget.balance[leaveType] ?? 0;
                  if (days > availableBalance) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text("Only $availableBalance day(s) of ${LeaveConstants.displayName(leaveType)} remaining")),
                    );
                    return;
                  }
                  Navigator.pop(context, {
                    "leaveType": leaveType,
                    "fromDate": fromDate,
                    "toDate": toDate,
                    "numberOfDays": days,
                    "reason": reasonController.text.trim(),
                  });
                },
                child: Text(
                  days == 0 ? "Select dates" : "Apply for $days Day${days > 1 ? 's' : ''} Leave",
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}