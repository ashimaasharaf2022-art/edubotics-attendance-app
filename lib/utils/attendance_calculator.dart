import 'package:intl/intl.dart';

/// A completed office day is either a full day or a mis-punch. The latter is
/// deliberately separate from an absence: the employee was present, but still
/// owes working time which can be made up on a later day.
enum DayType { fullDay, halfDay, misPunch, absent, notMarked }

class AttendanceResult {
  final DayType dayType;
  final double netHours;
  final double shortfallHours;
  final double extraHours;
  final String label;

  AttendanceResult({
    required this.dayType,
    required this.netHours,
    required this.label,
    this.shortfallHours = 0,
    this.extraHours = 0,
  });
}

/// One check-in/check-out pair within a day. [punchOut] is null while the
/// session is still open (the employee hasn't checked out of it yet).
class AttendanceSession {
  final String punchIn;
  final String? punchOut;
  const AttendanceSession({required this.punchIn, this.punchOut});
}

/// The company attendance policy.
///
/// - Office employees may punch in from 08:00 and punch out any time up to
///   11:59 PM, any number of times per day.
/// - A full day requires 9 hours of total worked time, summed across every
///   session that day (time in the gaps between sessions doesn't count).
/// - The 1:00 PM\u20132:00 PM lunch hour ALWAYS counts toward the 9 hours,
///   whether the employee stayed checked in through it or checked out and
///   back in around it \u2014 as long as lunch actually falls within their day
///   (from first punch-in to last punch-out). Only the portion of lunch not
///   already covered by a session is added, so it's never double-counted.
/// - Less than 9 hours total is a mis-punch and the shortfall is owed.
/// - More than 9 hours is extra work, which offsets earlier shortfall.
/// - Approved work-from-home days are always full days once checked out.
class AttendanceCalculator {
  static const int requiredMinutes = 9 * 60;
  static const int checkInStartMinutes = 8 * 60;
  // Punch-out is allowed up to 11:59 PM (not midnight).
  static const int checkOutEndMinutes = 23 * 60 + 59;

  static const int lunchStart = 13 * 60;
  static const int lunchEnd = 14 * 60;

  // Shared literal so every file (auto-checkout, admin screens, etc.) agrees
  // on the forced end-of-day punch-out time.
  static const String autoCheckoutTime = '11:59 PM';

  static int? toMinutes(String? timeStr) {
    if (timeStr == null || timeStr.trim().isEmpty || timeStr == '--:--') return null;
    try {
      final dt = DateFormat('h:mm a').parse(timeStr.trim());
      return dt.hour * 60 + dt.minute;
    } catch (_) {
      return null;
    }
  }

  static double computeNetHours(int inMinutes, int outMinutes) {
    final rawMinutes = outMinutes - inMinutes;
    if (rawMinutes < 0) return 0;
    return rawMinutes / 60.0;
  }

  /// Single check-in/check-out day \u2014 the original shape, still fully
  /// supported. Internally this is just a one-session call into
  /// [calculateFromSessions], so single- and multi-session days are always
  /// classified by the exact same rules.
  static AttendanceResult calculate({
    required String? punchIn,
    required String? punchOut,
    bool workFromHome = false,
  }) {
    if (punchIn == null) return AttendanceResult(dayType: DayType.absent, netHours: 0, label: 'Absent');
    return calculateFromSessions(
      [AttendanceSession(punchIn: punchIn, punchOut: punchOut)],
      workFromHome: workFromHome,
    );
  }

  /// Multiple check-in/check-out pairs in one day. Total worked time is the
  /// SUM of each session's duration; gaps between sessions don't count,
  /// EXCEPT the lunch hour, which is always credited (see class doc).
  static AttendanceResult calculateFromSessions(
    List<AttendanceSession> sessions, {
    bool workFromHome = false,
  }) {
    if (sessions.isEmpty) return AttendanceResult(dayType: DayType.absent, netHours: 0, label: 'Absent');

    final firstIn = toMinutes(sessions.first.punchIn);
    if (firstIn == null) return AttendanceResult(dayType: DayType.absent, netHours: 0, label: 'Absent');

    // If the last session is still open, the day isn't classifiable yet —
    // it's still in progress.
    if (sessions.last.punchOut == null) {
      return AttendanceResult(dayType: DayType.notMarked, netHours: 0, label: 'Checked In');
    }

    int totalMinutes = 0;
    int lunchCoveredMinutes = 0;
    int? overallOut;

    for (final session in sessions) {
      final inM = toMinutes(session.punchIn);
      final outM = toMinutes(session.punchOut);
      if (inM == null || outM == null || outM < inM) continue;
      totalMinutes += (outM - inM);
      overallOut = overallOut == null ? outM : (outM > overallOut ? outM : overallOut);

      final overlapStart = inM > lunchStart ? inM : lunchStart;
      final overlapEnd = outM < lunchEnd ? outM : lunchEnd;
      if (overlapEnd > overlapStart) {
        lunchCoveredMinutes += (overlapEnd - overlapStart);
      }
    }

    // Credit any lunch minutes not already covered by a session, but only if
    // lunch actually falls within the employee's day (first punch-in to
    // last punch-out) — so arriving after lunch or leaving before it doesn't
    // get credited for lunch they weren't there for.
    if (overallOut != null && firstIn <= lunchStart && overallOut! >= lunchEnd) {
      final uncovered = (lunchEnd - lunchStart) - lunchCoveredMinutes;
      if (uncovered > 0) totalMinutes += uncovered;
    }

    final netHours = totalMinutes / 60.0;

    if (workFromHome) {
      return AttendanceResult(dayType: DayType.fullDay, netHours: netHours, label: 'Full Day (WFH)');
    }

    final difference = netHours - requiredMinutes / 60.0;
    if (difference >= 0) {
      return AttendanceResult(dayType: DayType.fullDay, netHours: netHours, extraHours: difference, label: 'Full Day Present');
    }
    return AttendanceResult(dayType: DayType.misPunch, netHours: netHours, shortfallHours: -difference, label: 'Mis-punch');
  }

  static String formatHours(double hours) {
    final totalMinutes = (hours * 60).round();
    return '${totalMinutes ~/ 60} hr ${totalMinutes % 60} min';
  }
}