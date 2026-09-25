import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class CalendarRangePicker extends StatefulWidget {
  final DateTime? initialFrom;
  final DateTime? initialTo;
  final DateTime? minDate;
  final DateTime? maxDate;
  final void Function(DateTime from, DateTime to) onRangeSelected;

  const CalendarRangePicker({
    super.key,
    this.initialFrom,
    this.initialTo,
    this.minDate,
    this.maxDate,
    required this.onRangeSelected,
  });

  @override
  State<CalendarRangePicker> createState() => _CalendarRangePickerState();
}

class _CalendarRangePickerState extends State<CalendarRangePicker> {
  late DateTime visibleMonth;
  DateTime? from;
  DateTime? to;

  static const _months = ["January","February","March","April","May","June","July","August","September","October","November","December"];
  static const _weekdays = ["Mo","Tu","We","Th","Fr","Sa","Su"];

  @override
  void initState() {
    super.initState();
    from = widget.initialFrom;
    to = widget.initialTo;
    visibleMonth = from ?? DateTime.now();
  }

  void _onDayTap(DateTime day) {
    setState(() {
      if (from == null || (from != null && to != null)) {
        from = day;
        to = null;
      } else if (day.isBefore(from!)) {
        to = from;
        from = day;
      } else {
        to = day;
      }
    });
    if (from != null && to != null) {
      widget.onRangeSelected(from!, to!);
    }
  }

  bool _isInRange(DateTime day) {
    if (from == null || to == null) return false;
    return day.isAfter(from!.subtract(const Duration(days: 1))) && day.isBefore(to!.add(const Duration(days: 1)));
  }

  bool _isEndpoint(DateTime day) {
    return (from != null && _sameDay(day, from!)) || (to != null && _sameDay(day, to!));
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  bool _isBeforeMin(DateTime day) {
    final min = widget.minDate;
    return min != null && day.isBefore(DateTime(min.year, min.month, min.day));
  }

  bool _isAfterMax(DateTime day) {
    final max = widget.maxDate;
    return max != null && day.isAfter(DateTime(max.year, max.month, max.day));
  }

  bool _isDisabled(DateTime day) => _isBeforeMin(day) || _isAfterMax(day);

  bool _canShowPreviousMonth() {
    final min = widget.minDate;
    if (min == null) return true;
    final previousMonth = DateTime(visibleMonth.year, visibleMonth.month - 1, 1);
    final minMonth = DateTime(min.year, min.month, 1);
    return !previousMonth.isBefore(minMonth);
  }

  bool _canShowNextMonth() {
    final max = widget.maxDate;
    if (max == null) return true;
    final nextMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 1);
    final maxMonth = DateTime(max.year, max.month, 1);
    return !nextMonth.isAfter(maxMonth);
  }

  @override
  Widget build(BuildContext context) {
    final firstOfMonth = DateTime(visibleMonth.year, visibleMonth.month, 1);
    final daysInMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 0).day;
    final leadingBlank = (firstOfMonth.weekday - 1) % 7;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              onPressed: _canShowPreviousMonth()
                  ? () => setState(() => visibleMonth = DateTime(visibleMonth.year, visibleMonth.month - 1, 1))
                  : null,
            ),
            Text("${_months[visibleMonth.month - 1]} ${visibleMonth.year}", style: const TextStyle(fontWeight: FontWeight.bold)),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              onPressed: _canShowNextMonth()
                  ? () => setState(() => visibleMonth = DateTime(visibleMonth.year, visibleMonth.month + 1, 1))
                  : null,
            ),
          ],
        ),
        Row(
          children: _weekdays.map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))))).toList(),
        ),
        const SizedBox(height: 4),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7),
          itemCount: leadingBlank + daysInMonth,
          itemBuilder: (context, index) {
            if (index < leadingBlank) return const SizedBox.shrink();
            final day = DateTime(visibleMonth.year, visibleMonth.month, index - leadingBlank + 1);
            final isDisabled = _isDisabled(day);
            final inRange = _isInRange(day);
            final isEndpoint = _isEndpoint(day);

            return GestureDetector(
              onTap: isDisabled ? null : () => _onDayTap(day),
              child: Container(
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: isEndpoint ? AppColors.primary : (inRange ? AppColors.primary.withValues(alpha: 0.15) : null),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  "${day.day}",
                  style: TextStyle(
                    color: isDisabled
                        ? AppColors.textSecondary.withValues(alpha: 0.4)
                        : (isEndpoint ? Colors.white : AppColors.textPrimary),
                    fontWeight: isEndpoint ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13,
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}