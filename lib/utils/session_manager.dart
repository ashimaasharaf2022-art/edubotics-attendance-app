import 'package:shared_preferences/shared_preferences.dart';

/// Handles persisting the logged-in user's session locally so they
/// don't have to log in every time they open the app.
class SessionManager {
  static const _keyEmployeeId = "employeeId";
  static const _keyEmployeeName = "employeeName";
  static const _keyRole = "role";
  static const _keyLoginTime = "loginTime";

  static Future<void> saveSession({
    required String employeeId,
    required String role,
    String? employeeName,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyEmployeeId, employeeId);
    await prefs.setString(_keyRole, role);
    await prefs.setString(_keyEmployeeName, employeeName ?? "");
    await prefs.setString(_keyLoginTime, DateTime.now().toIso8601String());
  }

  /// Returns the saved session, or null if no one is logged in.
  static Future<Map<String, String>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final employeeId = prefs.getString(_keyEmployeeId);
    final role = prefs.getString(_keyRole);

    if (employeeId == null || role == null) return null;

    return {
      "employeeId": employeeId,
      "role": role,
      "employeeName": prefs.getString(_keyEmployeeName) ?? "",
      "loginTime": prefs.getString(_keyLoginTime) ?? "",
    };
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyEmployeeId);
    await prefs.remove(_keyRole);
    await prefs.remove(_keyEmployeeName);
    await prefs.remove(_keyLoginTime);
  }
}