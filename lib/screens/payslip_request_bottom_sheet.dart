import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

/// Employee payslip request form shown as a modal bottom sheet.
///
/// Data is stored at:
/// PayslipRequests/{employeeId}/{pushId}
///
/// This keeps the same Firebase schema as the existing
/// PayslipRequestScreen, so the admin workflow does not need to change.
class PayslipRequestBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const PayslipRequestBottomSheet({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<PayslipRequestBottomSheet> createState() =>
      _PayslipRequestBottomSheetState();
}

class _PayslipRequestBottomSheetState
    extends State<PayslipRequestBottomSheet> {
  late DatabaseReference dbRef;

  DateTime _selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  final _noteController = TextEditingController();
  bool _submitting = false;

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();

    final months = List.generate(
      12,
      (index) => DateTime(now.year, now.month - index, 1),
    );

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          child: SafeArea(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
              itemCount: months.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final month = months[index];
                final selected =
                    month.year == _selectedMonth.year &&
                    month.month == _selectedMonth.month;

                return ListTile(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    Icons.calendar_month_outlined,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(
                    DateFormat('MMMM yyyy').format(month),
                    style: TextStyle(
                      fontWeight:
                          selected ? FontWeight.w800 : FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  trailing: selected
                      ? const Icon(
                          Icons.check_circle,
                          color: AppColors.green,
                        )
                      : null,
                  onTap: () => Navigator.pop(context, month),
                );
              },
            ),
          ),
        );
      },
    );

    if (picked != null && mounted) {
      setState(() => _selectedMonth = picked);
    }
  }

  Future<void> _submitRequest() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    final monthKey = DateFormat('yyyy-MM').format(_selectedMonth);
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);
    final note = _noteController.text.trim();

    try {
      await dbRef
          .child('PayslipRequests')
          .child(widget.employeeId)
          .push()
          .set({
        'employeeId': widget.employeeId,
        'employeeName': widget.employeeName,
        'month': monthKey,
        'monthLabel': monthLabel,
        'note': note,
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
      });

      await NotificationCenter.sendAdmin(
        title: 'Payslip Request',
        message:
            '${widget.employeeName} requested a payslip for $monthLabel.',
      );

      if (!mounted) return;

      Navigator.of(context).pop();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payslip request sent to admin.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      setState(() => _submitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Unable to send payslip request. Please try again.',
          ),
        ),
      );
    }
  }

  InputDecoration _fieldDecoration({
    required String hintText,
  }) {
    return InputDecoration(
      hintText: hintText,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 14,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.divider,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: AppColors.green,
          width: 1.3,
        ),
      ),
      hintStyle: const TextStyle(
        color: AppColors.mutedText,
        fontSize: 13,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: AppColors.green.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Request Payslip',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Choose a month and send a request to HR.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 20),

              const Text(
                'Month',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),

              InkWell(
                onTap: _pickMonth,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.divider,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          DateFormat('MMMM yyyy')
                              .format(_selectedMonth),
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.calendar_today_outlined,
                        color: AppColors.primary,
                        size: 19,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              const Text(
                'Note (optional)',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 7),

              TextField(
                controller: _noteController,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: _fieldDecoration(
                  hintText: 'e.g. Needed for a loan application',
                ),
              ),

              const SizedBox(height: 18),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submitRequest,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    disabledBackgroundColor:
                        AppColors.primary.withValues(alpha: 0.55),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 21,
                          height: 21,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'SEND REQUEST',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 6),
            ],
          ),
        ),
      ),
    );
  }
}
