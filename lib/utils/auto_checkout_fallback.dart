import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'attendance_calculator.dart';

/// Free fallback for projects without scheduled Cloud Functions. It runs the
/// next time the employee opens the app and, if the previous day was left
/// with an open session (they forgot to check out), force-closes that LAST
/// session at the 11:59 PM boundary. Earlier sessions that day, if any,
/// are left untouched.
class AutoCheckoutFallback {
  static final DatabaseReference _db = FirebaseDatabase.instanceFor(
    app: Firebase.app(),
    databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
  ).ref();

  static String _key(DateTime date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  static Future<void> reconcilePreviousDay(String employeeId) async {
    final now = DateTime.now();
    final previous = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 1));
    final date = _key(previous);
    final ref = _db.child('Attendance').child(employeeId).child(date);
    final snapshot = await ref.get();
    if (!snapshot.exists) return;
    final record = Map<dynamic, dynamic>.from(snapshot.value as Map);
    if (record['status'] != 'Checked In') return;

    final rawSessions = record['sessions'];
    final sessions = rawSessions is List
        ? (rawSessions as List).map((s) => Map<String, dynamic>.from(s as Map)).toList()
        : (record['punchIn'] != null
            ? [
                <String, dynamic>{
                  'punchIn': record['punchIn'],
                  'workFromHome': record['workFromHome'],
                }
              ]
            : <Map<String, dynamic>>[]);
    if (sessions.isEmpty) return;

    final lastIndex = sessions.length - 1;
    if (sessions[lastIndex]['punchOut'] != null) return; // already closed somehow

    sessions[lastIndex] = {
      ...sessions[lastIndex],
      'punchOut': AttendanceCalculator.autoCheckoutTime,
    };

    // WFH stays automatic. Office attendance becomes a visible provisional
    // record which the employee can send to admin for verification.
    if (record['workFromHome'] == true) {
      await ref.update({
        'sessions': sessions,
        'punchOut': AttendanceCalculator.autoCheckoutTime,
        'status': 'Checked Out',
        'autoCheckedOutAt': DateTime.now().toIso8601String(),
        'attendanceStatus': 'Full Day (WFH auto checkout)',
      });
    } else {
      await ref.update({
        'sessions': sessions,
        'punchOut': AttendanceCalculator.autoCheckoutTime,
        'status': 'Auto Checked Out',
        'autoPunchOut': true,
        'autoCheckedOutAt': DateTime.now().toIso8601String(),
        'attendanceStatus': 'Auto punch-out — request verification',
      });
    }
  }
}