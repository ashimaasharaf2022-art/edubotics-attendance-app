import 'package:intl/intl.dart';

/// Attendance classification.
///
/// These are the ONLY three final attendance classifications:
///
/// 1. Full Day
/// 2. Work-Pending
/// 3. Absent
///
/// MIS-PUNCH is NOT a DayType.
/// It is a temporary workflow state handled outside this calculator.
enum DayType {
  fullDay,
  workPending,
  absent,
}

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

/// Represents one punch-in / punch-out session.
class AttendanceSession {
  final String punchIn;
  final String? punchOut;

  const AttendanceSession({
    required this.punchIn,
    this.punchOut,
  });
}

/// Central attendance calculator.
///
/// RULES
/// -----
/// Required working time = 9 hours.
///
/// Lunch:
/// 1:00 PM - 2:00 PM
///
/// Lunch COUNTS as working time.
///
/// Final classifications:
///
/// >= 9 hours
///     -> FULL DAY
///
/// < 9 hours with completed attendance
///     -> WORK-PENDING
///
/// No attendance
///     -> ABSENT
///
/// MIS-PUNCH:
///     -> NOT calculated here.
///     -> Handled by AttendanceTabScreen / HistoryScreen.
///     -> Actual punch-out is supplied later by admin.
class AttendanceCalculator {
  /// Required working time = 9 hours.
  static const int requiredMinutes = 9 * 60;

  /// Lunch starts at 1:00 PM.
  static const int lunchStart = 13 * 60;

  /// Lunch ends at 2:00 PM.
  static const int lunchEnd = 14 * 60;

  /// Temporary display/workflow value only.
  ///
  /// IMPORTANT:
  /// This is NOT an actual punch-out.
  ///
  /// It must NEVER be used to calculate working hours.
  static const String autoCheckoutTime = '11:59 PM';

  // ===========================================================================
  // TIME CONVERSION
  // ===========================================================================

  /// Converts a time such as:
  ///
  /// 9:30 AM
  /// 6:45 PM
  ///
  /// into minutes from midnight.
  static int? toMinutes(String? timeStr) {
    if (timeStr == null ||
        timeStr.trim().isEmpty ||
        timeStr.trim() == '--:--') {
      return null;
    }

    final text = timeStr.trim();

    // Normal 12-hour format.
    try {
      final dt = DateFormat('h:mm a').parse(
        text,
      );

      return dt.hour * 60 + dt.minute;
    } catch (_) {}

    // Also support 24-hour values for backward compatibility.
    try {
      final dt = DateFormat('HH:mm').parse(
        text,
      );

      return dt.hour * 60 + dt.minute;
    } catch (_) {}

    // Final flexible parser.
    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?$',
    ).firstMatch(text);

    if (match != null) {
      var hour =
          int.tryParse(match.group(1)!) ?? 0;

      final minute =
          int.tryParse(match.group(2)!) ?? 0;

      final period =
          match.group(3)?.toLowerCase();

      if (period == 'pm' && hour < 12) {
        hour += 12;
      }

      if (period == 'am' && hour == 12) {
        hour = 0;
      }

      if (hour >= 0 &&
          hour < 24 &&
          minute >= 0 &&
          minute < 60) {
        return hour * 60 + minute;
      }
    }

    return null;
  }

  // ===========================================================================
  // SINGLE SESSION
  // ===========================================================================

  /// Calculates one completed attendance session.
  ///
  /// Example:
  ///
  /// 9:30 AM -> 6:30 PM
  ///
  /// = 9 hours
  /// = FULL DAY
  ///
  /// Lunch is naturally included because no lunch deduction is performed.
  static double computeNetHours(
    int inMinutes,
    int outMinutes,
  ) {
    final difference =
        outMinutes - inMinutes;

    if (difference < 0) {
      return 0;
    }

    return difference / 60.0;
  }

  // ===========================================================================
  // NORMAL SINGLE-SESSION CALCULATION
  // ===========================================================================

  static AttendanceResult calculate({
    required String? punchIn,
    required String? punchOut,
    bool workFromHome = false,
  }) {
    // No punch-in = ABSENT.
    if (punchIn == null ||
        punchIn.trim().isEmpty) {
      return AttendanceResult(
        dayType: DayType.absent,
        netHours: 0,
        label: 'Absent',
      );
    }

    // An open punch-in is NOT a completed attendance calculation.
    //
    // MIS-PUNCH handling happens outside this calculator.
    //
    // We return ABSENT here only because AttendanceResult has no
    // "open" state. Screens that need to distinguish an open session
    // must check punchOut before calling this method.
    if (punchOut == null ||
        punchOut.trim().isEmpty) {
      return AttendanceResult(
        dayType: DayType.absent,
        netHours: 0,
        label: 'Absent',
      );
    }

    return calculateFromSessions(
      [
        AttendanceSession(
          punchIn: punchIn,
          punchOut: punchOut,
        ),
      ],
      workFromHome: workFromHome,
    );
  }

  // ===========================================================================
  // MULTIPLE SESSION CALCULATION
  // ===========================================================================

  /// Calculates attendance from multiple completed sessions.
  ///
  /// Example:
  ///
  /// Session 1:
  /// 9:30 AM -> 1:00 PM
  ///
  /// Session 2:
  /// 2:00 PM -> 6:30 PM
  ///
  /// Raw session time:
  /// 3h 30m + 4h 30m = 8h
  ///
  /// Lunch:
  /// 1:00 PM -> 2:00 PM = 1h
  ///
  /// Final:
  /// 9h = FULL DAY
  ///
  /// Lunch is added only when:
  ///
  /// 1. The employee's overall attended period overlaps lunch.
  /// 2. Part of the lunch period is not already represented
  ///    by one of the attendance sessions.
  ///
  /// Therefore:
  ///
  /// 9:30 AM -> 6:30 PM
  ///
  /// already contains lunch, so nothing is added.
  ///
  /// But:
  ///
  /// 9:30 AM -> 1:00 PM
  /// 2:00 PM -> 6:30 PM
  ///
  /// has a one-hour lunch gap, so one hour is credited.
  static AttendanceResult calculateFromSessions(
    List<AttendanceSession> sessions, {
    bool workFromHome = false,
  }) {
    // -------------------------------------------------------------------------
    // NO ATTENDANCE
    // -------------------------------------------------------------------------

    if (sessions.isEmpty) {
      return AttendanceResult(
        dayType: DayType.absent,
        netHours: 0,
        label: 'Absent',
      );
    }

    final validIntervals =
        <_TimeInterval>[];

    // -------------------------------------------------------------------------
    // BUILD VALID INTERVALS
    // -------------------------------------------------------------------------

    for (final session in sessions) {
      final inMinutes =
          toMinutes(session.punchIn);

      final outMinutes =
          toMinutes(session.punchOut);

      // Invalid punch-in.
      if (inMinutes == null) {
        continue;
      }

      // Open session.
      //
      // The calculator does NOT convert this into MIS-PUNCH.
      // MIS-PUNCH is handled by the attendance workflow.
      if (outMinutes == null) {
        return AttendanceResult(
          dayType: DayType.absent,
          netHours: 0,
          label: 'Absent',
        );
      }

      // Ignore invalid time ranges.
      if (outMinutes < inMinutes) {
        continue;
      }

      // Zero-minute sessions are not useful attendance.
      if (outMinutes == inMinutes) {
        continue;
      }

      validIntervals.add(
        _TimeInterval(
          start: inMinutes,
          end: outMinutes,
        ),
      );
    }

    // No valid completed sessions.
    if (validIntervals.isEmpty) {
      return AttendanceResult(
        dayType: DayType.absent,
        netHours: 0,
        label: 'Absent',
      );
    }

    // -------------------------------------------------------------------------
    // SORT SESSIONS
    // -------------------------------------------------------------------------

    validIntervals.sort(
      (a, b) => a.start.compareTo(
        b.start,
      ),
    );

    // -------------------------------------------------------------------------
    // RAW SESSION MINUTES
    // -------------------------------------------------------------------------

    int totalMinutes = 0;

    for (final interval in validIntervals) {
      totalMinutes +=
          interval.end - interval.start;
    }

    // -------------------------------------------------------------------------
    // LUNCH CREDIT
    // -------------------------------------------------------------------------
    //
    // Lunch is working time.
    //
    // We credit only the portion of lunch that lies between the first
    // punch-in and the last punch-out and is NOT already covered by
    // a session.
    // -------------------------------------------------------------------------

    final firstStart =
        validIntervals.first.start;

    final lastEnd =
        validIntervals.last.end;

    final attendanceSpansLunch =
        firstStart < lunchEnd &&
        lastEnd > lunchStart;

    if (attendanceSpansLunch) {
      final lunchCreditStart =
          lunchStart > firstStart
              ? lunchStart
              : firstStart;

      final lunchCreditEnd =
          lunchEnd < lastEnd
              ? lunchEnd
              : lastEnd;

      if (lunchCreditEnd >
          lunchCreditStart) {
        final lunchCoveredBySessions =
            _calculateCoveredMinutes(
          validIntervals,
          lunchCreditStart,
          lunchCreditEnd,
        );

        final lunchWindowMinutes =
            lunchCreditEnd -
                lunchCreditStart;

        final missingLunchMinutes =
            lunchWindowMinutes -
                lunchCoveredBySessions;

        if (missingLunchMinutes > 0) {
          totalMinutes +=
              missingLunchMinutes;
        }
      }
    }

    // -------------------------------------------------------------------------
    // FINAL HOURS
    // -------------------------------------------------------------------------

    final netHours =
        totalMinutes / 60.0;

    final requiredHours =
        requiredMinutes / 60.0;

    final difference =
        netHours - requiredHours;

    // -------------------------------------------------------------------------
    // FULL DAY
    // -------------------------------------------------------------------------

    if (difference >= 0) {
      return AttendanceResult(
        dayType: DayType.fullDay,
        netHours: netHours,
        extraHours: difference,
        shortfallHours: 0,
        label: workFromHome
            ? 'Full Day (WFH)'
            : 'Full Day',
      );
    }

    // -------------------------------------------------------------------------
    // WORK-PENDING
    // -------------------------------------------------------------------------

    return AttendanceResult(
      dayType: DayType.workPending,
      netHours: netHours,
      shortfallHours: -difference,
      extraHours: 0,
      label: workFromHome
          ? 'Work-Pending (WFH)'
          : 'Work-Pending',
    );
  }

  // ===========================================================================
  // LUNCH COVERAGE
  // ===========================================================================

  /// Returns how many minutes inside [rangeStart, rangeEnd] are already
  /// covered by attendance sessions.
  ///
  /// This prevents double-counting lunch.
  static int _calculateCoveredMinutes(
    List<_TimeInterval> intervals,
    int rangeStart,
    int rangeEnd,
  ) {
    int covered = 0;

    for (final interval in intervals) {
      final start =
          interval.start > rangeStart
              ? interval.start
              : rangeStart;

      final end =
          interval.end < rangeEnd
              ? interval.end
              : rangeEnd;

      if (end > start) {
        covered += end - start;
      }
    }

    return covered;
  }

  // ===========================================================================
  // EXTRA HOURS
  // ===========================================================================

  static double calculateExtraHours(
    double workedHours,
  ) {
    final extra =
        workedHours -
            (requiredMinutes / 60.0);

    return extra > 0
        ? extra
        : 0;
  }

  // ===========================================================================
  // SHORTFALL
  // ===========================================================================

  static double calculateShortfallHours(
    double workedHours,
  ) {
    final shortfall =
        (requiredMinutes / 60.0) -
            workedHours;

    return shortfall > 0
        ? shortfall
        : 0;
  }

  // ===========================================================================
  // FORMAT HOURS
  // ===========================================================================

  static String formatHours(
    double hours,
  ) {
    final totalMinutes =
        (hours * 60).round();

    final hoursPart =
        totalMinutes ~/ 60;

    final minutesPart =
        totalMinutes % 60;

    return '$hoursPart hr $minutesPart min';
  }
}

// =============================================================================
// INTERNAL TIME INTERVAL
// =============================================================================

class _TimeInterval {
  final int start;
  final int end;

  const _TimeInterval({
    required this.start,
    required this.end,
  });
}