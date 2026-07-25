import 'package:flutter/material.dart';

/// The shared Workora shift policy. Attendance records store the matching
/// schedule name so weekend work is distinct in reports and audits.
///
/// Employees can check in / check out at any time of day. The check-in and
/// check-out times are only used afterwards to classify the day as a Full
/// Day or Half Day (see AttendanceCalculator):
///   - Check in by [fullDayCheckInDeadline] (10:00 AM) is required for a
///     Full Day.
///   - Check out at or after [shiftEnd] (6:00 PM) keeps the Full Day credit.
///   - Anything else is a Half Day (as long as they checked in at all).
class WorkSchedule {
  static const TimeOfDay checkInStart = TimeOfDay(hour: 9, minute: 30);
  // Kept for reference / display only — check-in is no longer time-locked.
  static const TimeOfDay checkInEnd = TimeOfDay(hour: 10, minute: 0);
  static const TimeOfDay fullDayCheckInDeadline = TimeOfDay(hour: 10, minute: 0);
  static const TimeOfDay fullDayCheckOutDeadline = TimeOfDay(hour: 19, minute: 0);
  static const TimeOfDay lunchStart = TimeOfDay(hour: 13, minute: 0);
  static const TimeOfDay lunchEnd = TimeOfDay(hour: 14, minute: 0);
  static const TimeOfDay teaStart = TimeOfDay(hour: 16, minute: 30);
  static const TimeOfDay teaEnd = TimeOfDay(hour: 17, minute: 0);
  static const TimeOfDay shiftEnd = TimeOfDay(hour: 18, minute: 0);

  static bool get isWeekend {
    final day = DateTime.now().weekday;
    return day == DateTime.saturday || day == DateTime.sunday;
  }

  static String get shiftName => isWeekend ? 'Weekend Shift' : 'Weekday Shift';

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
  static int _nowMinutes() {
    final now = TimeOfDay.now();
    return _minutes(now);
  }

  /// Check-in and check-out are allowed at any time of day; only the
  /// resulting attendance classification depends on the clock.
  static bool get canCheckIn => true;
  static bool get canStartLunch => _nowMinutes() >= _minutes(lunchStart) && _nowMinutes() < _minutes(lunchEnd);
  static bool get canEndLunch => _nowMinutes() >= _minutes(lunchEnd);
  static bool get canStartTea => _nowMinutes() >= _minutes(teaStart) && _nowMinutes() < _minutes(teaEnd);
  static bool get canEndTea => _nowMinutes() >= _minutes(teaEnd);
  static bool get isLunchBreak => _nowMinutes() >= _minutes(lunchStart) && _nowMinutes() < _minutes(lunchEnd);
  static bool get isTeaBreak => _nowMinutes() >= _minutes(teaStart) && _nowMinutes() < _minutes(teaEnd);

  static String get todaySummary => isWeekend ? 'Weekend working day' : 'Monday–Friday working day';
}
