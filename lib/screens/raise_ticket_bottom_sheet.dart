import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

/// Employee helpdesk ticket form matching the Workora reference design.
///
/// The ticket is stored at:
/// HelpdeskRequests/{employeeId}/{pushId}
///
/// Both `description` and legacy-compatible `message` are written so the
/// existing admin/helpdesk workflow can continue to read the request.
class RaiseTicketBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const RaiseTicketBottomSheet({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<RaiseTicketBottomSheet> createState() =>
      _RaiseTicketBottomSheetState();
}

class _RaiseTicketBottomSheetState extends State<RaiseTicketBottomSheet> {
  late DatabaseReference dbRef;

  final _subjectController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _department = 'HR';
  bool _submitting = false;

  static const _departments = <String>[
    'HR',
    'IT Helpdesk',
    'Managerial team',
    'High table',
  ];

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
    _subjectController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final subject = _subjectController.text.trim();
    final description = _descriptionController.text.trim();

    if (subject.isEmpty || description.isEmpty) {
      _showMessage('Please enter a subject and describe the issue.');
      return;
    }

    setState(() => _submitting = true);

    try {
      final requestRef = dbRef
          .child('HelpdeskRequests')
          .child(widget.employeeId)
          .push();

      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': widget.employeeName,
        'department': _department,
        'subject': subject,
        'description': description,
        // Keep compatibility with the existing helpdesk schema.
        'message': description,
        'status': 'pending',
        'createdAt': DateTime.now().toIso8601String(),
      });

      // Only Managerial team tickets are routed to the Admin Dashboard.
      // HR, IT Helpdesk, and High table will be handled by their
      // respective dashboards when those dashboards are created.
      if (_department == 'Managerial team') {
        await NotificationCenter.sendAdmin(
          title: 'New Managerial Ticket',
          message:
              '${widget.employeeName} raised a managerial ticket: $subject',
        );
      }

      if (!mounted) return;

      // Close the bottom sheet only after the Firebase write and any
      // notification work have completed. Do not use the sheet's
      // BuildContext after popping it; doing so can trigger Flutter's
      // `_dependents.isEmpty` framework assertion.
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _showMessage('Unable to submit ticket: $e');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 13,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(
          color: AppColors.green,
          width: 1.3,
        ),
      ),
      hintStyle: const TextStyle(
        color: AppColors.mutedText,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );
  }

  Widget _label(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
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
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 30,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Raise a ticket',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'HR & IT helpdesk — typical response in 1 business day',
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  InkWell(
                    onTap: _submitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    borderRadius: BorderRadius.circular(30),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.divider),
                        color: Colors.white,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.close_rounded,
                        size: 17,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _label('Department'),
              DropdownButtonFormField<String>(
                initialValue: _department,
                isExpanded: true,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
                decoration: _fieldDecoration(hint: 'Select department'),
                items: _departments
                    .map(
                      (department) => DropdownMenuItem<String>(
                        value: department,
                        child: Text(
                          department,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: _submitting
                    ? null
                    : (value) {
                        if (value == null) return;
                        setState(() => _department = value);
                      },
              ),
              const SizedBox(height: 12),
              _label('Subject'),
              TextField(
                controller: _subjectController,
                textInputAction: TextInputAction.next,
                decoration: _fieldDecoration(
                  hint: 'e.g. Laptop not charging',
                ),
              ),
              const SizedBox(height: 12),
              _label('Description'),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                textInputAction: TextInputAction.newline,
                decoration: _fieldDecoration(
                  hint: 'Describe the issue',
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor:
                        AppColors.green.withValues(alpha: .55),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: _submitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Submit ticket',
                          style: TextStyle(
                            fontSize: 12,
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
}
