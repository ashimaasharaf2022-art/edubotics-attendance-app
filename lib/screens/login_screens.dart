import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/session_manager.dart';
import '../utils/device_helper.dart';
import '../utils/notification_center.dart';
import '../utils/email_alert_helper.dart';
import '../utils/app_colors.dart';
import 'employee_shell.dart';
import 'admin_shell.dart';
import 'device_approval_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController employeeIdController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  late DatabaseReference dbRef;

  bool isLoggingIn = false;

  @override
  void initState() {
    super.initState();

    // Use the same Realtime Database used by the rest of the app.
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  @override
  void dispose() {
    employeeIdController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  void showMessage(String msg) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  /// Finds a user in /users.
  ///
  /// Normally the Employee ID is also the Firebase child key:
  /// /users/EMPEG001
  ///
  /// As a fallback, this also searches the employeeId field. This makes
  /// login continue to work if an older record has a different Firebase
  /// child key but contains employeeId: "EMPEG001".
  Future<Map<dynamic, dynamic>?> _findUser(String empId) async {
    // 1. First try the Employee ID as the Firebase child key.
    final directSnapshot =
        await dbRef.child("users").child(empId).get();

    if (directSnapshot.exists && directSnapshot.value is Map) {
      return Map<dynamic, dynamic>.from(
        directSnapshot.value as Map,
      );
    }

    // 2. Fallback: search all /users records by employeeId.
    final usersSnapshot = await dbRef.child("users").get();

    if (!usersSnapshot.exists || usersSnapshot.value is! Map) {
      return null;
    }

    final users = Map<dynamic, dynamic>.from(
      usersSnapshot.value as Map,
    );

    for (final entry in users.entries) {
      if (entry.value is! Map) continue;

      final candidate = Map<dynamic, dynamic>.from(
        entry.value as Map,
      );

      final storedEmployeeId = candidate["employeeId"]
          ?.toString()
          .trim()
          .toUpperCase();

      if (storedEmployeeId == empId) {
        return candidate;
      }
    }

    return null;
  }

  Future<void> login() async {
    final empId = employeeIdController.text.trim().toUpperCase();
    final password = passwordController.text.trim();

    if (empId.isEmpty || password.isEmpty) {
      showMessage("Please enter Employee ID and Password");
      return;
    }

    setState(() => isLoggingIn = true);

    try {
      final user = await _findUser(empId);

      if (user == null) {
        if (!mounted) return;

        setState(() => isLoggingIn = false);
        showMessage("Employee Not Found");
        return;
      }

      final storedPassword = user["password"]?.toString() ?? "";

      if (storedPassword != password) {
        if (!mounted) return;

        setState(() => isLoggingIn = false);
        showMessage("Wrong Password");
        return;
      }

      final role =
          user["role"]?.toString().trim().toLowerCase() ?? "employee";

      final nameValue = user["name"]?.toString().trim();
      final name = (nameValue == null || nameValue.isEmpty)
          ? null
          : nameValue;

      final registeredDeviceValue =
          user["registeredDeviceId"]?.toString().trim();

      final registeredDeviceId =
          (registeredDeviceValue == null ||
                  registeredDeviceValue.isEmpty)
              ? null
              : registeredDeviceValue;

      final currentDeviceId = await DeviceHelper.getDeviceId();

      // Super Admin/Admin can log in normally on their first device.
      // Other employees also get their first device registered here.
      if (registeredDeviceId == null) {
        await dbRef.child("users").child(empId).update({
          "registeredDeviceId": currentDeviceId,
        });
      } else if (registeredDeviceId != currentDeviceId) {
        if (!mounted) return;

        setState(() => isLoggingIn = false);

        final deviceModel = await DeviceHelper.getDeviceModel();

        final requestRef =
            dbRef.child("DeviceApprovalRequests").child(empId).push();

        await requestRef.set({
          "employeeId": empId,
          "employeeName": name ?? empId,
          "deviceId": currentDeviceId,
          "deviceModel": deviceModel,
          "status": "pending",
          "requestedAt": DateTime.now().toIso8601String(),
        });

        await NotificationCenter.sendAdmin(
          title: "New Device Login Request",
          message:
              "${name ?? empId} is trying to log in from a new device: $deviceModel.",
        );

        await EmailAlertHelper.sendAlert(
          templateId: EmailAlertHelper.templateDeviceLogin,
          subject: "New Device Login Request — ${name ?? empId}",
          message:
              "${name ?? empId} ($empId) is trying to log in from a new device: $deviceModel.\n\n"
              "Open the app to generate an OTP for them.",
        );

        if (!mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => DeviceApprovalScreen(
              employeeId: empId,
              requestId: requestRef.key!,
              role: role,
              employeeName: name,
            ),
          ),
        );

        return;
      }

      await SessionManager.saveSession(
        employeeId: empId,
        role: role,
        employeeName: name,
      );

      TextInput.finishAutofillContext();

      if (!mounted) return;

      setState(() => isLoggingIn = false);

      // Both Admin and Super Admin go to the Admin Panel.
      // Only role == "superadmin" gets Super Admin privileges.
      if (role == "superadmin" || role == "admin") {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AdminShell(
              employeeId: empId,
              employeeName: name,
              isSuperAdmin: role == "superadmin",
            ),
          ),
        );
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => EmployeeShell(
              employeeId: empId,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => isLoggingIn = false);
      showMessage("Login failed: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: AppGradients.background,
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: AutofillGroup(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 22),

                  Center(
                    child: Image.asset(
                      "assets/images/workora_logo.png",
                      width: 210,
                      semanticLabel: "Workora",
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Center(
                    child: Text(
                      "Attendance workspace for Edubotics Global",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ),

                  const SizedBox(height: 34),

                  Container(
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          "Welcome back",
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),

                        const SizedBox(height: 5),

                        const Text(
                          "Sign in to manage your workday.",
                          style: TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),

                        const SizedBox(height: 24),

                        TextField(
                          controller: employeeIdController,
                          autofillHints: const [
                            AutofillHints.username,
                          ],
                          textCapitalization:
                              TextCapitalization.characters,
                          decoration: const InputDecoration(
                            labelText: "Employee ID",
                            prefixIcon:
                                Icon(Icons.badge_outlined),
                          ),
                        ),

                        const SizedBox(height: 16),

                        TextField(
                          controller: passwordController,
                          obscureText: true,
                          autofillHints: const [
                            AutofillHints.password,
                          ],
                          onSubmitted: (_) => login(),
                          decoration: const InputDecoration(
                            labelText: "Password",
                            prefixIcon:
                                Icon(Icons.lock_outline_rounded),
                          ),
                        ),

                        const SizedBox(height: 22),

                        SizedBox(
                          height: 54,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: AppGradients.brand,
                              borderRadius:
                                  BorderRadius.circular(16),
                              boxShadow: AppShadows.hero,
                            ),
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Colors.transparent,
                                foregroundColor: Colors.white,
                                shadowColor: Colors.transparent,
                                shape:
                                    RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                              ),
                              onPressed:
                                  isLoggingIn ? null : login,
                              child: isLoggingIn
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child:
                                          CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      "SIGN IN",
                                      style: TextStyle(
                                        fontWeight:
                                            FontWeight.w800,
                                        letterSpacing: .6,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const Center(
                    child: Text(
                      "Secure attendance, made simple",
                      style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
