import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/login_screens.dart';
import 'screens/employee_shell.dart';
import 'screens/admin_shell.dart';
import 'utils/session_manager.dart';
import 'utils/notification_helper.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("INIT ERROR: $e");
  }

  await NotificationHelper.init();
  await NotificationHelper.scheduleDailyPunchReminder();

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Edubotics Global",
      theme: ThemeData(primarySwatch: Colors.orange),
      home: const SessionGate(),
    );
  }
}

class SessionGate extends StatefulWidget {
  const SessionGate({super.key});

  @override
  State<SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<SessionGate> {
  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await SessionManager.getSession();

    if (!mounted) return;

    if (session == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }

    final role = session["role"];
    final employeeId = session["employeeId"]!;
    final employeeName = session["employeeName"];

    if (role == "admin" || role == "superadmin") {
  Navigator.pushReplacement(
    context,
    MaterialPageRoute(
      builder: (_) => AdminShell(
        employeeId: employeeId,
        employeeName: (employeeName == null || employeeName.isEmpty) ? null : employeeName,
        isSuperAdmin: role == "superadmin",
      ),
    ),
  );
} else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => EmployeeShell(employeeId: employeeId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xffF6F7FB),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}