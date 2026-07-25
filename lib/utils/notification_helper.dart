import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationHelper {
  static final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();

  static Future<void> init() async {
    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    await _plugin.initialize(initSettings);

    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  static Future<void> scheduleDailyPunchReminder() async {
    try {
      final now = tz.TZDateTime.now(tz.local);
      var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, 9, 25);
      if (scheduled.isBefore(now)) {
        scheduled = scheduled.add(const Duration(days: 1));
      }

      await _plugin.zonedSchedule(
        1001,
        "Time to Check In",
        "Don't forget to punch in for today!",
        scheduled,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            "punch_reminder_channel",
            "Punch Reminders",
            channelDescription: "Daily reminder to check in",
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      // Don't let a notification scheduling failure crash app startup.
      // ignore: avoid_print
      print("Failed to schedule punch reminder: $e");
    }
  }

  /// Device notifications continue to appear while Workora is closed. These
  /// are schedule reminders; server-originated admin notifications require an
  /// FCM server credential/backend and are handled separately from this app.
  static Future<void> scheduleWorkdayReminders() async {
    await scheduleDailyPunchReminder();
    await _scheduleDaily(1002, 'Lunch break', 'Lunch break is from 1:00 PM to 2:00 PM.', 12, 55);
    await _scheduleDaily(1003, 'Tea break', 'Tea break is from 4:30 PM to 5:00 PM.', 16, 25);
    await _scheduleDaily(1004, 'Checkout reminder', 'Remember to check out when your workday is complete.', 17, 55);
  }

  static Future<void> _scheduleDaily(int id, String title, String body, int hour, int minute) async {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduled.isBefore(now)) scheduled = scheduled.add(const Duration(days: 1));
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      scheduled,
      const NotificationDetails(android: AndroidNotificationDetails('workora_reminders', 'Workora reminders', importance: Importance.high, priority: Priority.high)),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}