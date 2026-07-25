import 'package:intl/intl.dart';

enum DayType { fullDay, halfDay, absent, notMarked }

class AttendanceResult {
  final DayType dayType;
  final double netHours;
  final String label;

  AttendanceResult({required this.dayType, required this.netHours, required this.label});
}

/// Classifies a day's attendance from the recorded punch-in / punch-out
/// clock times.
///
/// Employees may check in and check out at any time — there's no time
/// window restriction. Instead, the *time of day* they punch determines
/// whether the day counts as a Full Day or a Half Day:
///
///   - Punch in by 10:00 AM is required for a Full Day.
///   - If they punched in by 10:00 AM AND punch out is at/after 6:00 PM
///     (shift end), the day is a Full Day.
///   - Punching in after 10:00 AM always results in a Half Day (regardless
///     of checkout time).
///   - Punching in by 10:00 AM but checking out before 6:00 PM (leaving
///     early) results in a Half Day.
///   - No punch-in at all is Absent.
class AttendanceCalculator {
  static const _lunchStart = 13 * 60;
  static const _lunchEnd = 14 * 60;
  static const _teaStart = 16 * 60 + 30;
  static const _teaEnd = 17 * 60;

  // Shift runs 9:30 AM – 6:00 PM (8.5 hours), minus 1.5 hours of breaks.
  static const int fullDayCheckInDeadlineMinutes = 10 * 60; // 10:00 AM
  static const int shiftEndMinutes = 18 * 60; // 6:00 PM

  static int? _toMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    try {
      final dt = DateFormat("h:mm a").parse(timeStr.trim());
      return dt.hour * 60 + dt.minute;
    } catch (_) {
      return null;
    }
  }

  static double _computeNetHours(int inMinutes, int outMinutes) {
    int rawMinutes = outMinutes - inMinutes;
    if (rawMinutes < 0) rawMinutes += 24 * 60;

    final overlapStart = inMinutes > _lunchStart ? inMinutes : _lunchStart;
    final overlapEnd = outMinutes < _lunchEnd ? outMinutes : _lunchEnd;
    final lunchOverlap = (overlapEnd - overlapStart).clamp(0, _lunchEnd - _lunchStart);

    final teaOverlapStart = inMinutes > _teaStart ? inMinutes : _teaStart;
    final teaOverlapEnd = outMinutes < _teaEnd ? outMinutes : _teaEnd;
    final teaOverlap = (teaOverlapEnd - teaOverlapStart).clamp(0, _teaEnd - _teaStart);

    final netMinutes = rawMinutes - lunchOverlap - teaOverlap;
    return netMinutes / 60.0;
  }

  static AttendanceResult calculate({required String? punchIn, required String? punchOut}) {
    final inMinutes = _toMinutes(punchIn);
    final outMinutes = _toMinutes(punchOut);

    if (inMinutes == null) {
      return AttendanceResult(dayType: DayType.absent, netHours: 0, label: "Absent");
    }

    final onTimeCheckIn = inMinutes <= fullDayCheckInDeadlineMinutes;

    if (outMinutes == null) {
      // Still checked in / no checkout recorded yet — not final.
      return AttendanceResult(
        dayType: DayType.notMarked,
        netHours: 0,
        label: onTimeCheckIn ? "Checked In" : "Checked In (Late)",
      );
    }

    final netHours = _computeNetHours(inMinutes, outMinutes);
    final fullShiftCompleted = outMinutes >= shiftEndMinutes;

    DayType type;
    String label;
    if (onTimeCheckIn && fullShiftCompleted) {
      type = DayType.fullDay;
      label = "Full Day Present";
    } else {
      type = DayType.halfDay;
      label = "Half Day Present";
    }

    return AttendanceResult(dayType: type, netHours: netHours, label: label);
  }

  static String formatHours(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;
    return "$h hr $m min";
  }
}
