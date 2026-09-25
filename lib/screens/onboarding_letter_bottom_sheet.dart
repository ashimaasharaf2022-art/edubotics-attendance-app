import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class OnboardingLetterBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const OnboardingLetterBottomSheet({super.key, required this.employeeId, required this.employeeName});

  @override
  State<OnboardingLetterBottomSheet> createState() => _OnboardingLetterState();
}

class _OnboardingLetterState extends State<OnboardingLetterBottomSheet> {
  late final DatabaseReference _dbRef;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
  }

  Future<void> _submit() async {
    if (_submitting) return;

    setState(() => _submitting = true);

    try {
      final requestedAt = DateTime.now().toIso8601String();

      // Create the request where the admin workflow can read it:
      // DocumentRequests/{employeeId}/{pushId}
      final requestRef = _dbRef
          .child('DocumentRequests')
          .child(widget.employeeId)
          .push();

      await requestRef.set({
        'requestId': requestRef.key,
        'employeeId': widget.employeeId,
        'employeeName': widget.employeeName,
        'documentType': 'Onboarding letter',
        'description': 'Request for a onboarding letter from HR.',
        'status': 'pending',
        'requestedAt': requestedAt,
      });

      // Notification is an additional alert. If it fails, the Firebase
      // request above is still successfully stored for the admin dashboard.
      try {
        await NotificationCenter.sendAdmin(
          title: 'Onboarding Letter Request',
          message: '${widget.employeeName} requested an onboarding letter.',
        );
      } catch (_) {}

      if (!mounted) return;

      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onboarding letter request sent to HR.')),
      );
    } catch (e) {
  if (!mounted) return;

  setState(() => _submitting = false);

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Could not submit onboarding letter request: $e'),
    ),
  );
}
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(maxHeight: 620),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 30, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(10)))),
              const SizedBox(height: 12),
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(color: const Color(0xFFFFF2DF), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.emoji_people_outlined, color: Color(0xFFB77816), size: 21),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Onboarding letter', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                        const SizedBox(height: 2),
                        const Text('Request a formal confirmation of your joining and onboarding details.', style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Material(
                    color: AppColors.surface,
                    shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
                    child: InkWell(
                      onTap: _submitting ? null : () => Navigator.pop(context),
                      customBorder: const CircleBorder(),
                      child: const SizedBox(width: 30, height: 30, child: Icon(Icons.close_rounded, size: 16)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(13), border: Border.all(color: AppColors.divider)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('REQUEST FOR', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: AppColors.textSecondary, letterSpacing: .7)),
                    const SizedBox(height: 7),
                    _InfoRow(label: 'Employee', value: widget.employeeName.isEmpty ? widget.employeeId : widget.employeeName),
                    const SizedBox(height: 5),
                    _InfoRow(label: 'Employee ID', value: widget.employeeId),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const Text('The letter will normally include', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const SizedBox(height: 7),
                            Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('Employee name and employee ID', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('Designation and department', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('Date of joining', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('Reporting manager and work location, where maintained', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('Employment type and other approved joining details', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              Padding(padding: const EdgeInsets.only(bottom: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(margin: const EdgeInsets.only(top: 5), width: 5, height: 5, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)), const SizedBox(width: 8), Expanded(child: Text('HR/company authorization and issue date', style: const TextStyle(fontSize: 10.5, height: 1.35, color: AppColors.textSecondary))) ])),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(11)),
                child: const Text('The final document uses the employee information verified in the HR system.', style: TextStyle(fontSize: 10, height: 1.35, color: AppColors.textSecondary)),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _submitting ? null : _submit,
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, disabledBackgroundColor: AppColors.green, elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                  child: _submitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Submit request', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(width: 76, child: Text(label, style: const TextStyle(fontSize: 9.5, color: AppColors.textSecondary))),
      Expanded(child: Text(value.isEmpty ? 'Not specified' : value, style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
    ],
  );
}
