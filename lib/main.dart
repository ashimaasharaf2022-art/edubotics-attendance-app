import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/login_screens.dart';
import 'screens/employee_shell.dart';
import 'screens/admin_shell.dart';
import 'utils/session_manager.dart';
import 'utils/notification_helper.dart';
import 'utils/app_colors.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("INIT ERROR: $e");
  }

  try {
    await NotificationHelper.init();
    await NotificationHelper.scheduleWorkdayReminders();
  } catch (e) {
    debugPrint("NOTIFICATION INIT ERROR: $e");
  }

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Workora",
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          primary: AppColors.primary,
          secondary: AppColors.indigo,
          surface: AppColors.surface,
        ),
        scaffoldBackgroundColor: AppColors.background,
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
        ),
      ),
      home: const SessionGate(),
      builder: (context, child) {
        // Use one app text scale on Android so cards, action buttons and
        // tab labels retain the same layout on devices with different system
        // font-size settings.
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.noScaling),
          child: child!,
        );
      },
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
