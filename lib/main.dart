import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'screens/login_screens.dart';
import 'screens/employee_shell.dart';
import 'screens/admin_shell.dart';
import 'screens/superadmin_shell.dart';
import 'utils/session_manager.dart';
import 'utils/workora_app_settings.dart';
import 'utils/notification_helper.dart';
import 'theme/app_theme.dart';


Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await WorkoraAppSettings.load();
  } catch (e) {
    debugPrint("APP SETTINGS LOAD ERROR: $e");
  }

  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  } catch (e) {
    debugPrint("INIT ERROR: $e");
  }

  // flutter_local_notifications has no web support at all — skip it
  // entirely on web rather than letting it fail and get caught below.
  if (!kIsWeb) {
    try {
      await NotificationHelper.init();
      await NotificationHelper.scheduleWorkdayReminders();
    } catch (e) {
      debugPrint("NOTIFICATION INIT ERROR: $e");
    }
  }

  runApp(const AttendanceApp());
}

class AttendanceApp extends StatefulWidget {
  const AttendanceApp({super.key});

  @override
  State<AttendanceApp> createState() => _AttendanceAppState();
}

class _AttendanceAppState extends State<AttendanceApp> {
  @override
  void initState() {
    super.initState();
    WorkoraAppSettings.isDarkMode.addListener(_onSettingsChanged);
    WorkoraAppSettings.locale.addListener(_onSettingsChanged);
  }

  @override
  void dispose() {
    WorkoraAppSettings.isDarkMode.removeListener(_onSettingsChanged);
    WorkoraAppSettings.locale.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  ThemeData _darkTheme() {
    final base = AppTheme.lightTheme;

    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0B1713),
      canvasColor: const Color(0xFF0B1713),
      cardColor: const Color(0xFF14251F),
      colorScheme: base.colorScheme.copyWith(
        brightness: Brightness.dark,
        surface: const Color(0xFF14251F),
        onSurface: Colors.white,
        surfaceContainerHighest: const Color(0xFF20342D),
        onSurfaceVariant: const Color(0xFFB7C6C0),
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: const Color(0xFF0F1F1A),
        foregroundColor: Colors.white,
      ),
      bottomNavigationBarTheme: base.bottomNavigationBarTheme.copyWith(
        backgroundColor: const Color(0xFF0F1F1A),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: const Color(0xFF14251F),
      ),
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: const Color(0xFF20342D),
        contentTextStyle: const TextStyle(color: Colors.white),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: "Workora",
      theme: AppTheme.lightTheme,
      darkTheme: _darkTheme(),
      themeMode: WorkoraAppSettings.isDarkMode.value
          ? ThemeMode.dark
          : ThemeMode.light,
      locale: WorkoraAppSettings.locale.value,
      supportedLocales: const [
        Locale('en', 'IN'),
        Locale('ml', 'IN'),
        Locale('hi', 'IN'),
        Locale('ta', 'IN'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const SessionGate(),
      builder: (context, child) {
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
      await SessionManager.clearSession();
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      return;
    }

    final employeeId = session["employeeId"]!;
    final role = (session["role"]?.toString() ?? "employee")
        .trim()
        .toLowerCase();
    final employeeName = session["employeeName"]?.toString();

    if (role == "superadmin") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => SuperAdminShell(
            superAdminId: employeeId,
            superAdminName: employeeName,
          ),
        ),
      );
      return;
    }

    if (role == "admin") {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => AdminShell(
            employeeId: employeeId,
            employeeName: employeeName,
            isSuperAdmin: false,
          ),
        ),
      );
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => EmployeeShell(employeeId: employeeId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xffF6F7FB),
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
