import 'package:intl/intl.dart';

enum DayType { fullDay, halfDay, absent, notMarked }

class AttendanceResult {
  final DayType dayType;
  final double netHours;
  final String label;

  AttendanceResult({required this.dayType, required this.netHours, required this.label});
}

class AttendanceCalculator {
  static const _lunchStart = 13 * 60;
  static const _lunchEnd = 14 * 60;

  static const double fullDayThreshold = 7.5;
  static const double halfDayThresholdDefault = 3.5;

  // Grace period: 30 min leniency on half-day floors for a
  // late-but-honest punch (e.g. arriving 15 min late shouldn't
  // wrongly flip a near-full morning into "absent").
  static const double halfDayThresholdMorningOnly = 3.0;
  static const double halfDayThresholdAfternoonOnly = 3.5;

  static int? _toMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty) return null;
    try {
      final dt = DateFormat("h:mm a").parse(timeStr.trim());
      return dt.hour * 60 + dt.minute;
    } catch (_) {
      return null;
    }
  }

  static AttendanceResult calculate({required String? punchIn, required String? punchOut}) {
    final inMinutes = _toMinutes(punchIn);
    final outMinutes = _toMinutes(punchOut);

    if (inMinutes == null || outMinutes == null) {
      return AttendanceResult(dayType: DayType.notMarked, netHours: 0, label: "Not Marked");
    }

    int rawMinutes = outMinutes - inMinutes;
    if (rawMinutes < 0) rawMinutes += 24 * 60;

    final overlapStart = inMinutes > _lunchStart ? inMinutes : _lunchStart;
    final overlapEnd = outMinutes < _lunchEnd ? outMinutes : _lunchEnd;
    final lunchOverlap = (overlapEnd - overlapStart).clamp(0, _lunchEnd - _lunchStart);

    final netMinutes = rawMinutes - lunchOverlap;
    final netHours = netMinutes / 60.0;

    // Determine which session this shift belongs to, so the right
    // grace-adjusted floor applies.
    final isMorningOnly = outMinutes <= _lunchStart;
    final isAfternoonOnly = inMinutes >= _lunchEnd;

    double halfDayFloor;
    if (isMorningOnly) {
      halfDayFloor = halfDayThresholdMorningOnly;
    } else if (isAfternoonOnly) {
      halfDayFloor = halfDayThresholdAfternoonOnly;
    } else {
      halfDayFloor = halfDayThresholdDefault;
    }

    DayType type;
    String label;

    if (netHours >= fullDayThreshold) {
      type = DayType.fullDay;
      label = "Full Day Present";
    } else if (netHours >= halfDayFloor) {
      type = DayType.halfDay;
      label = "Half Day Present";
    } else {
      type = DayType.absent;
      label = "Absent";
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