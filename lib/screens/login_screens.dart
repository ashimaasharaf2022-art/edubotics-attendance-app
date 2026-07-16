import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/session_manager.dart';
import '../utils/device_helper.dart';
import '../utils/email_alert_helper.dart';
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  Future<void> login() async {
    String empId = employeeIdController.text.trim().toUpperCase();
    String password = passwordController.text.trim();

    if (empId.isEmpty || password.isEmpty) {
      showMessage("Please enter Employee ID and Password");
      return;
    }

    setState(() => isLoggingIn = true);

    try {
      final snapshot = await dbRef.child("users").child(empId).get();

      if (!snapshot.exists) {
        setState(() => isLoggingIn = false);
        showMessage("Employee Not Found");
        return;
      }

      Map<dynamic, dynamic> user = snapshot.value as Map<dynamic, dynamic>;

      if (user["password"].toString() != password) {
        setState(() => isLoggingIn = false);
        showMessage("Wrong Password");
        return;
      }

      String role = user["role"].toString().toLowerCase();
      String? name = user["name"]?.toString();
     

      String? registeredDeviceId = user["registeredDeviceId"]?.toString();
      final currentDeviceId = await DeviceHelper.getDeviceId();

      if (registeredDeviceId == null) {
        await dbRef.child("users").child(empId).update({
          "registeredDeviceId": currentDeviceId,
        });
      } else if (registeredDeviceId != currentDeviceId) {
        if (!mounted) return;
        setState(() => isLoggingIn = false);

        final deviceModel = await DeviceHelper.getDeviceModel();
        final requestRef = dbRef.child("DeviceApprovalRequests").child(empId).push();

        await requestRef.set({
          "employeeId": empId,
          "employeeName": name ?? empId,
          "deviceId": currentDeviceId,
          "deviceModel": deviceModel,
          "status": "pending",
          "requestedAt": DateTime.now().toIso8601String(),
        });

        await EmailAlertHelper.sendAlert(
          subject: "New Device Login Request \u2014 ${name ?? empId}",
          message:
              "${name ?? empId} ($empId) is trying to log in from a new device: $deviceModel.\n\nOpen the app to generate an OTP for them.",
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

      if (role == "superadmin") {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => AdminShell(
        employeeId: empId,
        employeeName: name,
        isSuperAdmin: true,
      ),
    ),
  );
} else {
  // Everyone else is an employee \u2014 always lands on their own
  // dashboard. Admin access (if granted) is a switch inside
  // Settings, not a separate login destination.
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => EmployeeShell(employeeId: empId),
    ),
  );
}
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoggingIn = false);
      showMessage(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffF6F7FB),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(25),
          child: AutofillGroup(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Image.asset("assets/images/logo.jpeg", height: 120),
                const SizedBox(height: 20),
                const Text(
                  "EDUBOTICS GLOBAL",
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xffF26C23),
                  ),
                ),
                const SizedBox(height: 5),
                const Text(
                  "Leading way to the future",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 50),
                TextField(
                  controller: employeeIdController,
                  autofillHints: const [AutofillHints.username],
                  decoration: InputDecoration(
                    labelText: "Employee ID",
                    prefixIcon: const Icon(Icons.person),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => login(),
                  decoration: InputDecoration(
                    labelText: "Password",
                    prefixIcon: const Icon(Icons.lock),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                  ),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xffF26C23),
                    ),
                    onPressed: isLoggingIn ? null : login,
                    child: isLoggingIn
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            "LOGIN",
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 25),
                const Text(
                  "Employee Attendance Management System",
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}