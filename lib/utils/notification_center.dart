import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

class NotificationCenter {
  static DatabaseReference get _ref => FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
      ).ref();

  // ---- Per-employee notifications (leave decisions, WFH decisions, etc.) ----

  static Future<void> send({
    required String employeeId,
    required String title,
    required String message,
  }) async {
    try {
      await _ref.child("Notifications").child(employeeId).push().set({
        "title": title,
        "message": message,
        "read": false,
        "createdAt": DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Stream<int> unreadCount(String employeeId) {
    return _ref.child("Notifications").child(employeeId).onValue.map((event) {
      if (event.snapshot.value == null) return 0;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return data.values.where((v) {
        final entry = Map<dynamic, dynamic>.from(v as Map);
        return entry["read"] != true;
      }).length;
    });
  }

  static Future<void> markAllRead(String employeeId) async {
    final snapshot = await _ref.child("Notifications").child(employeeId).get();
    if (!snapshot.exists) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    for (final key in data.keys) {
      await _ref.child("Notifications").child(employeeId).child(key.toString()).update({"read": true});
    }
  }

  // ---- Admin-wide notifications (incoming requests from any employee) ----

  static Future<void> sendAdmin({
    required String title,
    required String message,
  }) async {
    try {
      await _ref.child("AdminNotifications").push().set({
        "title": title,
        "message": message,
        "read": false,
        "createdAt": DateTime.now().toIso8601String(),
      });
    } catch (_) {}
  }

  static Stream<int> adminUnreadCount() {
    return _ref.child("AdminNotifications").onValue.map((event) {
      if (event.snapshot.value == null) return 0;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      return data.values.where((v) {
        final entry = Map<dynamic, dynamic>.from(v as Map);
        return entry["read"] != true;
      }).length;
    });
  }

  static Future<void> markAllAdminRead() async {
    final snapshot = await _ref.child("AdminNotifications").get();
    if (!snapshot.exists) return;
    final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
    for (final key in data.keys) {
      await _ref.child("AdminNotifications").child(key.toString()).update({"read": true});
    }
  }
}