import 'package:flutter/material.dart';

/// Shared office-time policy. Work-from-home employees are exempt from these
/// punch-time restrictions, but office punches are still location restricted.
class WorkSchedule {
  static const TimeOfDay checkInStart = TimeOfDay(hour: 8, minute: 0);
  static const TimeOfDay checkOutEnd = TimeOfDay(hour: 23, minute: 59);
  static const TimeOfDay lunchStart = TimeOfDay(hour: 13, minute: 0);
  static const TimeOfDay lunchEnd = TimeOfDay(hour: 14, minute: 0);
  static const TimeOfDay teaStart = TimeOfDay(hour: 16, minute: 30);
  static const TimeOfDay teaEnd = TimeOfDay(hour: 17, minute: 0);
  static const int lunchDurationMinutes = 60;
  static const int requiredWorkMinutes = 9 * 60;

  static int _minutes(TimeOfDay time) => time.hour * 60 + time.minute;
  static int get nowMinutes => _minutes(TimeOfDay.now());
  static bool get canCheckIn => nowMinutes >= _minutes(checkInStart) && nowMinutes <= _minutes(checkOutEnd);
  static bool get canCheckOut => nowMinutes >= _minutes(checkInStart) && nowMinutes <= _minutes(checkOutEnd);
  static bool get isLunchBreak => nowMinutes >= _minutes(lunchStart) && nowMinutes < _minutes(lunchEnd);
  static bool get canStartLunch => isLunchBreak;
  static bool get canEndLunch => nowMinutes >= _minutes(lunchEnd);
  static bool get canStartTea => nowMinutes >= _minutes(teaStart) && nowMinutes < _minutes(teaEnd);
  static bool get canEndTea => nowMinutes >= _minutes(teaEnd);
  static bool get isTeaBreak => nowMinutes >= _minutes(teaStart) && nowMinutes < _minutes(teaEnd);
  static String get shiftName => 'Office Shift';
  static String get todaySummary => 'Office punches: 8:00 AM – 12:00 AM • 9 working hours required';
}
