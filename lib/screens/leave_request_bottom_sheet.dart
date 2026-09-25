import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/leave_constants.dart';
import '../utils/app_colors.dart';
import '../widgets/calendar_range_picker.dart';

/// Reusable leave request bottom sheet.
///
/// The sheet is presented by the Dashboard or Leaves screen. It returns the
/// request data after the sheet has completely closed, so Firebase writes are
/// never performed while the modal route is being disposed.
class LeaveRequestBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final Map<String, int>? initialBalance;

  const LeaveRequestBottomSheet({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.initialBalance,
  });

  @override
  State<LeaveRequestBottomSheet> createState() => _LeaveRequestBottomSheetState();
}

class _LeaveRequestBottomSheetState extends State<LeaveRequestBottomSheet> {
  late DatabaseReference dbRef;

  bool loading = true;
  Map<String, int> balance = {};
  String selectedType = LeaveConstants.allTypes.isNotEmpty
      ? LeaveConstants.allTypes.first
      : LeaveConstants.casual;
  DateTime? fromDate;
  DateTime? toDate;
  late final TextEditingController reasonController;

  @override
  void initState() {
    super.initState();
    reasonController = TextEditingController();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    if (widget.initialBalance != null) {
      balance = Map<String, int>.from(widget.initialBalance!);
      loading = false;
    } else {
      _loadBalance();
    }
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  Future<void> _loadBalance() async {
    try {
      final year = DateTime.now().year.toString();
      final ref = dbRef.child('LeaveBalances').child(widget.employeeId).child(year);
      final snapshot = await ref.get();

      final loaded = Map<String, int>.from(LeaveConstants.defaultQuota);
      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        for (final type in LeaveConstants.allTypes) {
          final value = data[type];
          if (value != null) {
            loaded[type] = int.tryParse(value.toString()) ??
                LeaveConstants.defaultQuota[type]!;
          }
        }
      } else {
        await ref.set(LeaveConstants.defaultQuota);
      }

      if (!mounted) return;
      setState(() {
        balance = loaded;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        balance = Map<String, int>.from(LeaveConstants.defaultQuota);
        loading = false;
      });
    }
  }

  int get numberOfDays {
    if (fromDate == null || toDate == null) return 0;
    return toDate!.difference(fromDate!).inDays + 1;
  }

  String _dateLabel(DateTime? date) {
    return date == null ? 'dd-mm-yyyy' : DateFormat('dd-MM-yyyy').format(date);
  }

  Future<void> _pickLeaveRange() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final maxDate = DateTime(now.year + 1, 12, 31);

    final result = await showModalBottomSheet<Map<String, DateTime>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.42),
      enableDrag: true,
      builder: (calendarContext) {
        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(calendarContext).size.height * 0.72,
          ),
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Select leave dates',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () => Navigator.pop(calendarContext),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.divider),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(Icons.close_rounded, size: 18),
                    ),
                  ),
                ],
              ),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Tap the start date, then tap the end date',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: SingleChildScrollView(
                  child: CalendarRangePicker(
                    initialFrom: fromDate,
                    initialTo: toDate,
                    minDate: today,
                    maxDate: maxDate,
                    onRangeSelected: (from, to) {
                      Navigator.pop(calendarContext, {
                        'from': from,
                        'to': to,
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      fromDate = result['from'];
      toDate = result['to'];
    });
  }

  void _submit() {
    if (loading) return;

    if (fromDate == null || toDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select the leave dates.')),
      );
      return;
    }

    if (numberOfDays <= 0) return;

    // IMPORTANT: close the sheet first. The caller performs the Firebase
    // write after this route has fully closed. This avoids the framework
    // '_dependents.isEmpty' assertion seen when updating sheet state and
    // popping the modal in the same frame.
    Navigator.of(context).pop(<String, dynamic>{
      'leaveType': selectedType,
      'fromDate': fromDate!,
      'toDate': toDate!,
      'numberOfDays': numberOfDays,
      'reason': reasonController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final totalAvailable = balance.values.fold<int>(0, (sum, value) => sum + value);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Expanded(
                      child: Text(
                        'Request a leave',
                        style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(30),
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.divider),
                        ),
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.close_rounded,
                          size: 25,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  loading ? 'Loading leave balance...' : '$totalAvailable days available this year',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 24),
                _label('Leave type'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 27),
                  decoration: _inputDecoration(),
                  items: LeaveConstants.allTypes
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(
                            LeaveConstants.displayName(type),
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: loading
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => selectedType = value);
                        },
                ),
                const SizedBox(height: 18),
                _label('Leave dates'),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _dateField(
                        helperText: 'From',
                        label: _dateLabel(fromDate),
                        onTap: loading ? null : _pickLeaveRange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _dateField(
                        helperText: 'To',
                        label: _dateLabel(toDate),
                        onTap: loading ? null : _pickLeaveRange,
                      ),
                    ),
                  ],
                ),
                if (numberOfDays > 0) ...[
                  const SizedBox(height: 7),
                  Text(
                    '$numberOfDays day${numberOfDays == 1 ? '' : 's'} requested',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _label('Reason'),
                const SizedBox(height: 8),
                TextField(
                  controller: reasonController,
                  minLines: 3,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: _inputDecoration(
                    hintText: 'Add a short note for your manager',
                    alignLabelWithHint: true,
                  ),
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: loading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.green.withValues(alpha: 0.45),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Submit request',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: AppColors.textSecondary,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  InputDecoration _inputDecoration({
    String? hintText,
    bool alignLabelWithHint = false,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: AppColors.mutedText,
        fontSize: 15,
      ),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 15,
      ),
      alignLabelWithHint: alignLabelWithHint,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.3),
      ),
    );
  }

  Widget _dateField({
    required String helperText,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 82,
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    helperText,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    label,
                    style: TextStyle(
                      color: label == 'dd-mm-yyyy'
                          ? AppColors.mutedText
                          : AppColors.textPrimary,
                      fontSize: 15,
                      fontWeight: label == 'dd-mm-yyyy'
                          ? FontWeight.w500
                          : FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.calendar_today_outlined,
              size: 24,
              color: AppColors.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}
