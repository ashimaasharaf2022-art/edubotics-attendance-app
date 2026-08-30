import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Full breakdown of what fed into the month's Outstanding time figure on
/// the Attendance History screen, plus the lifetime running total for
/// context. Every activity entry here is one that was actually included in
/// the MONTH total \u2014 nothing is capped, so adding these up always equals
/// the month figure. The all-time figure is a separate running balance
/// across every month of attendance and isn't broken down line-by-line here.
class CompensationActivityScreen extends StatelessWidget {
  final String monthLabel;
  final int monthOutstandingMinutes;
  final int allTimeOutstandingMinutes;
  final List<Map<String, String>> activity;

  const CompensationActivityScreen({
    super.key,
    required this.monthLabel,
    required this.monthOutstandingMinutes,
    required this.allTimeOutstandingMinutes,
    required this.activity,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Compensation Activity", style: TextStyle(color: Colors.white)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(monthLabel, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  "Total outstanding time: ${AttendanceCalculator.formatHours(allTimeOutstandingMinutes / 60)}",
                  style: TextStyle(
                    color: allTimeOutstandingMinutes > 0 ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 3),
                const Text("Runs across every month of attendance, not just this one.", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 10),
                Container(height: 1, color: AppColors.divider),
                const SizedBox(height: 10),
                Text(
                  "This month: ${AttendanceCalculator.formatHours(monthOutstandingMinutes / 60)}",
                  style: TextStyle(
                    color: monthOutstandingMinutes > 0 ? AppColors.danger : AppColors.success,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text("Activity this month", style: TextStyle(color: AppColors.textSecondary, fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (activity.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text("No compensation activity this month.", style: TextStyle(color: AppColors.textSecondary))),
            )
          else
            ...activity.map(
              (item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.history, size: 16, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item['date'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                          const SizedBox(height: 3),
                          Text(item['text'] ?? '', style: const TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}