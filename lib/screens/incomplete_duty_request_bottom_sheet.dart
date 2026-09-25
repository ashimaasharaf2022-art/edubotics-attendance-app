import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

/// Employee request sheet for an incomplete-duty day.
///
/// This does NOT regularize the attendance day. It only sends the employee's
/// reason and optional note about which day they would like to compensate it.
class IncompleteDutyRequestBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String date;
  final String workedHours;
  final int shortfallMinutes;

  const IncompleteDutyRequestBottomSheet({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.workedHours,
    required this.shortfallMinutes,
  });

  @override
  State<IncompleteDutyRequestBottomSheet> createState() =>
      _IncompleteDutyRequestBottomSheetState();
}

class _IncompleteDutyRequestBottomSheetState
    extends State<IncompleteDutyRequestBottomSheet> {
  late final TextEditingController reasonController;
  late final TextEditingController compensationDayController;

  @override
  void initState() {
    super.initState();
    reasonController = TextEditingController();
    compensationDayController = TextEditingController();
  }

  @override
  void dispose() {
    reasonController.dispose();
    compensationDayController.dispose();
    super.dispose();
  }

  void _submit() {
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter the reason for the incomplete duty.')),
      );
      return;
    }

    Navigator.of(context).pop(<String, dynamic>{
      'reason': reason,
      'compensationDayMessage': compensationDayController.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final shortfall = '${widget.shortfallMinutes ~/ 60}h ${widget.shortfallMinutes % 60}m';

    return SafeArea(
      top: false,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          20,
          10,
          20,
          18 + MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Incomplete duty',
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Tell HR why your verified working time was below 9 hours.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppColors.divider),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'ATTENDANCE',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.date,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.workedHours} worked  •  $shortfall still pending',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Reason',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: reasonController,
                minLines: 3,
                maxLines: 5,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Explain what happened on this day',
                  filled: true,
                  fillColor: AppColors.veryLightGreen,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Compensation day / message (optional)',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 7),
              TextField(
                controller: compensationDayController,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'e.g. I would like to compensate this on 25 Sep.',
                  filled: true,
                  fillColor: AppColors.veryLightGreen,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'This message does not regularize the day. Regularization happens only when verified overtime is used and the admin approves the compensation.',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.35,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton(
                  onPressed: _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Send reason to admin',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
