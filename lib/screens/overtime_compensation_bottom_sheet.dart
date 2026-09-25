import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

class IncompleteDutyOption {
  final String date;
  final int shortfallMinutes;

  const IncompleteDutyOption({
    required this.date,
    required this.shortfallMinutes,
  });
}

/// Employee-side OD compensation request.
///
/// The sheet never changes Attendance directly. It creates a request for the
/// existing admin CompensationRequests workflow.
class OvertimeCompensationBottomSheet extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final String date;
  final AttendanceResult calculation;
  final int availableOvertimeMinutes;
  final List<IncompleteDutyOption> incompleteDuties;

  const OvertimeCompensationBottomSheet({
    super.key,
    required this.employeeId,
    required this.employeeName,
    required this.date,
    required this.calculation,
    required this.availableOvertimeMinutes,
    required this.incompleteDuties,
  });

  @override
  State<OvertimeCompensationBottomSheet> createState() =>
      _OvertimeCompensationBottomSheetState();
}

class _OvertimeCompensationBottomSheetState
    extends State<OvertimeCompensationBottomSheet> {
  static const _allOptions = <String>[
    'Comp-off (extra day off)',
    'Extra pay',
    'Regularize attendance',
  ];

  late String selectedType;
  late final TextEditingController reasonController;

  int get currentOvertimeMinutes =>
      (widget.calculation.extraHours * 60).round();

  bool get hasActiveIncompleteDuty => widget.incompleteDuties.isNotEmpty;

  IncompleteDutyOption? get suggestedDuty =>
      widget.incompleteDuties.isEmpty ? null : widget.incompleteDuties.first;

  int get maxCompOffDays =>
      widget.availableOvertimeMinutes ~/ AttendanceCalculator.requiredMinutes;

  @override
  void initState() {
    super.initState();
    selectedType = hasActiveIncompleteDuty
        ? 'Regularize attendance'
        : _allOptions.first;
    reasonController = TextEditingController();
  }

  @override
  void dispose() {
    reasonController.dispose();
    super.dispose();
  }

  int get requestedMinutes {
    if (selectedType == 'Comp-off (extra day off)') {
      return maxCompOffDays * AttendanceCalculator.requiredMinutes;
    }

    if (selectedType == 'Regularize attendance') {
      final target = suggestedDuty;
      if (target == null) return 0;
      // Regularization targets the entire remaining shortfall of the
      // selected ID. The admin verifies available OD before approval.
      return target.shortfallMinutes;
    }

    // Extra pay defaults to the overtime on the selected OD day.
    return currentOvertimeMinutes;
  }

  String _hours(int minutes) {
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final overtime = AttendanceCalculator.formatHours(
      widget.calculation.extraHours,
    );
    final target = suggestedDuty;

    final options = hasActiveIncompleteDuty
        ? const ['Regularize attendance']
        : _allOptions;

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
                  width: 32,
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
                  Expanded(
                    child: Text(
                      widget.date,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Text(
                'Overtime duty',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.calendarPresentText,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              _line('Check in', widget.calculation.label.isEmpty ? '—' : 'Verified'),
              _line('Overtime this day', overtime),
              _line('Available overtime', _hours(widget.availableOvertimeMinutes)),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: AppColors.successLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  hasActiveIncompleteDuty
                      ? 'You have an active incomplete duty. Comp-off and extra pay are disabled. The system suggests the ID requiring the least time first.'
                      : 'You have no active incomplete duty. You may request comp-off, extra pay, or regularize attendance.',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1.35,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ),
              if (target != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'SYSTEM SUGGESTION',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${target.date} needs ${_hours(target.shortfallMinutes)} to become Present.',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'This is the active ID with the smallest remaining shortfall.',
                        style: const TextStyle(
                          fontSize: 9,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 14),
              const Text(
                'Compensation type',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: selectedType,
                isExpanded: true,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: AppColors.veryLightGreen,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
                items: options
                    .map(
                      (option) => DropdownMenuItem<String>(
                        value: option,
                        child: Text(
                          option,
                          style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => selectedType = value);
                },
              ),
              if (selectedType == 'Comp-off (extra day off)') ...[
                const SizedBox(height: 9),
                Text(
                  maxCompOffDays > 0
                      ? '$maxCompOffDays compensatory day(s) available at 9h per day.'
                      : 'You need at least 9h of available overtime for one comp-off day.',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (selectedType == 'Regularize attendance' &&
                  target != null) ...[
                const SizedBox(height: 9),
                Text(
                  'This request will use up to ${_hours(requestedMinutes)} from this OD for ${target.date}.',
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Message to admin',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: reasonController,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Add context for your compensation request',
                  hintStyle: const TextStyle(fontSize: 10, color: AppColors.mutedText),
                  filled: true,
                  fillColor: AppColors.veryLightGreen,
                  contentPadding: const EdgeInsets.all(12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: AppColors.divider),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: ElevatedButton(
                  onPressed: requestedMinutes <= 0
                      ? null
                      : () {
                          Navigator.pop(context, <String, dynamic>{
                            'compensationType': selectedType,
                            'requestedMinutes': requestedMinutes,
                            'targetDate': target?.date,
                            'odDates': <String>[widget.date],
                            'reason': reasonController.text.trim(),
                            'selectedDates': <String>[
                              widget.date,
                              if (target != null &&
                                  selectedType == 'Regularize attendance')
                                target.date,
                            ],
                          });
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: AppColors.green.withValues(alpha: .35),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Submit request',
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

  Widget _line(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
