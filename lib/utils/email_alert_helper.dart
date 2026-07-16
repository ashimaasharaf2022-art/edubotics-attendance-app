import 'dart:convert';
import 'package:http/http.dart' as http;

/// Sends alert emails via EmailJS (free tier, no backend needed).
/// Create a free account at emailjs.com, connect your Gmail as the
/// sending service, create a template, then fill in the three
/// values below from your EmailJS dashboard.
class EmailAlertHelper {
  static const String _serviceId = "YOUR_SERVICE_ID";
  static const String _templateId = "YOUR_TEMPLATE_ID";
  static const String _publicKey = "YOUR_PUBLIC_KEY";
  static const String _adminEmail = "yaseen@eduboticsglobal.com"; // where alerts go

  static Future<void> sendAlert({
    required String subject,
    required String message,
  }) async {
    try {
      await http.post(
        Uri.parse("https://api.emailjs.com/api/v1.0/email/send"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "service_id": _serviceId,
          "template_id": _templateId,
          "user_id": _publicKey,
          "template_params": {
            "to_email": _adminEmail,
            "subject": subject,
            "message": message,
          },
        }),
      );
    } catch (_) {
      // Email alerts are best-effort — never block the app flow
      // if the email fails to send (e.g. no internet).
    }
  }
}