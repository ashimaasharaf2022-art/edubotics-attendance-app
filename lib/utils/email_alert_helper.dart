import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sends alert emails via EmailJS (free tier, no backend needed).
class EmailAlertHelper {
  static const String _serviceId = "service_c1adwo7";
  static const String _publicKey = "wHFlW5QhdXymKZ3HR";
  static const String _adminEmail = "admin@edubotics.example"; // TODO: replace with your real admin inbox

  static const String templateLeaveRequest = "template_p6tsj4k";
  static const String templateDeviceLogin = "template_9a98rq9";

  static Future<void> sendAlert({
    required String subject,
    required String message,
    required String templateId,
  }) async {
    try {
      await http.post(
        Uri.parse("https://api.emailjs.com/api/v1.0/email/send"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "service_id": _serviceId,
          "template_id": templateId,
          "user_id": _publicKey,
          "template_params": {
            "to_email": _adminEmail,
            "subject": subject,
            "message": message,
          },
        }),
      );
    } catch (_) {
      // Email alerts are best-effort \u2014 never block the app flow
      // if the email fails to send (e.g. no internet).
    }
  }
}