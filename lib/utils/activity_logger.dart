import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class ActivityLogger {
  static Future<void> log({
    required String adminId,
    required String adminName,
    required String action,
    String? details,
  }) async {
    try {
      final dbRef = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
      ).ref();

      await dbRef.child("AdminActivityLog").push().set({
        "adminId": adminId,
        "adminName": adminName,
        "action": action,
        "details": details ?? "",
        "timestamp": DateTime.now().toIso8601String(),
      });
    } catch (_) {
      // Logging failures should never block the actual action.
    }
  }
}