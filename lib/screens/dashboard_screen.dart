import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/location_helper.dart';
import '../utils/time_integrity_helper.dart';
import '../utils/work_schedule.dart';
import '../utils/auto_checkout_fallback.dart';
import '../utils/notification_center.dart';
import '../utils/progress_painters.dart';
import 'leave_screen.dart';
import 'notifications_screen.dart';
import 'history_screen.dart';
import 'personal_report_screen.dart';
import 'announcement_detail_screen.dart';
import 'payslip_request_screen.dart';
import 'live_location_screen.dart';
import 'profile_screen.dart';
import 'account_settings_screen.dart';

// Dark palette used only for this screen's hero header, to match the
// reference design without changing the app's global light theme.
const Color _kHeroDark1 = Color(0xFF0B0F1F);
const Color _kHeroDark2 = Color(0xFF171B3D);

class DashboardScreen extends StatefulWidget {
  final String employeeId;
  final void Function(String name)? onNameLoaded;

  const DashboardScreen({super.key, required this.employeeId, this.onNameLoaded});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DatabaseReference dbRef;

  String employeeName = "";
  String? employeePhotoBase64;

  bool showHomeTab = false;
  bool? checkedInAsWfh;
  bool isLoading = true;
  bool isSubmitting = false;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  String punchInTime = "--:--";
  String punchOutTime = "--:--";
  String status = "Not Checked In";
  List<AttendanceSession> _todaySessions = <AttendanceSession>[];
  String workingHours = "0 hr 0 min";
  DayType? dayType;

  String? wfhStatusToday;
  String? pendingAutoCheckoutDate;
  String? lunchBreakStart;
  String? lunchBreakEnd;
  String? teaBreakStart;
  String? teaBreakEnd;
  LocationStatus locationStatus = LocationStatus.loading;
  LocationResult? currentLocation;

  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  Map<String, dynamic> allAttendance = {};
  int fullDayCount = 0;
  int halfDayCount = 0;
  int absentCount = 0;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });

    _loadEmployeeInfo();
    _loadTodayAttendance();
    AutoCheckoutFallback.reconcilePreviousDay(widget.employeeId).then((_) => _loadTodayAttendance());
    _refreshLocation();
    _loadMonthlyAttendance();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  void _openAccountSettings() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountSettingsScreen(
          employeeId: widget.employeeId,
        ),
      ),
    );
  }

  Future<void> _loadEmployeeInfo() async {
    try {
      final snapshot = await dbRef.child("users").child(widget.employeeId).get();
      if (!mounted) return;
      if (snapshot.exists) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final name = (data["name"] ?? widget.employeeId).toString();
        final photo = data["photoBase64"]?.toString();
        setState(() {
          employeeName = name;
          employeePhotoBase64 = photo;
        });
        widget.onNameLoaded?.call(name);
      }
    } catch (_) {}
  }

  String getDateKey([DateTime? d]) {
    final date = d ?? DateTime.now();
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _updateClassification() {
    if (_todaySessions.isEmpty) {
      dayType = null;
      workingHours = "0 hr 0 min";
      return;
    }

    final result = AttendanceCalculator.calculateFromSessions(
      _todaySessions,
      workFromHome: checkedInAsWfh ?? false,
    );
    dayType = result.dayType;
    workingHours = AttendanceCalculator.formatHours(result.netHours);
  }

  Future<void> _loadTodayAttendance() async {
    try {
      final snapshot = await dbRef
          .child("Attendance")
          .child(widget.employeeId)
          .child(getDateKey())
          .get();

      if (!mounted) return;

      if (!snapshot.exists) {
        setState(() {
          _todaySessions = <AttendanceSession>[];
          punchInTime = "--:--";
          punchOutTime = "--:--";
          status = "Not Checked In";
          checkedInAsWfh = null;
          lunchBreakStart = null;
          lunchBreakEnd = null;
          teaBreakStart = null;
          teaBreakEnd = null;
          dayType = null;
          workingHours = "0 hr 0 min";
        });
      } else {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);

        final sessions = <AttendanceSession>[];
        final rawSessions = data["sessions"];

        if (rawSessions is List) {
          for (final raw in rawSessions) {
            if (raw is Map && raw["punchIn"] != null) {
              sessions.add(
                AttendanceSession(
                  punchIn: raw["punchIn"].toString(),
                  punchOut: raw["punchOut"]?.toString(),
                ),
              );
            }
          }
        } else if (rawSessions is Map) {
          final entries = rawSessions.entries.toList()
            ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
          for (final entry in entries) {
            final raw = entry.value;
            if (raw is Map && raw["punchIn"] != null) {
              sessions.add(
                AttendanceSession(
                  punchIn: raw["punchIn"].toString(),
                  punchOut: raw["punchOut"]?.toString(),
                ),
              );
            }
          }
        }

        // Backward compatibility with old single-session records.
        if (sessions.isEmpty && data["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: data["punchIn"].toString(),
              punchOut: data["punchOut"]?.toString(),
            ),
          );
        }

        final last = sessions.isEmpty ? null : sessions.last;
        final hasOpenSession = last != null && last.punchOut == null;

        setState(() {
          _todaySessions = sessions;
          punchInTime = last?.punchIn ?? "--:--";
          punchOutTime = hasOpenSession ? "--:--" : (last?.punchOut ?? "--:--");
          status = sessions.isEmpty
              ? "Not Checked In"
              : (hasOpenSession ? "Checked In" : "Checked Out");

          lunchBreakStart = data["lunchBreakStart"]?.toString();
          lunchBreakEnd = data["lunchBreakEnd"]?.toString();
          teaBreakStart = data["teaBreakStart"]?.toString();
          teaBreakEnd = data["teaBreakEnd"]?.toString();

          if (data.containsKey("workFromHome") && sessions.isNotEmpty) {
            checkedInAsWfh = data["workFromHome"] == true;
            showHomeTab = checkedInAsWfh!;
          }

          _updateClassification();
        });
      }

      final wfhSnap = await dbRef
          .child("WorkFromHomeRequests")
          .child(widget.employeeId)
          .child(getDateKey())
          .get();

      if (wfhSnap.exists) {
        final wfhData = Map<dynamic, dynamic>.from(wfhSnap.value as Map);
        if (!mounted) return;
        setState(() {
          wfhStatusToday = wfhData["status"]?.toString();
          if (checkedInAsWfh == null &&
              (wfhStatusToday == "approved" || wfhStatusToday == "pending")) {
            showHomeTab = true;
          }
        });
      }

      if (!mounted) return;
      setState(() => isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => isLoading = false);
    }
  }

  Future<void> _refreshLocation() async {
    setState(() => locationStatus = LocationStatus.loading);
    final (status, result) = await LocationHelper.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      locationStatus = status;
      currentLocation = result;
    });
  }

  Future<void> _loadMonthlyAttendance() async {
    try {
      final snapshot = await dbRef.child("Attendance").child(widget.employeeId).get();
      if (!mounted) return;

      Map<String, dynamic> data = {};
      if (snapshot.exists) {
        final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);
        raw.forEach((k, v) => data[k.toString()] = Map<String, dynamic>.from(v as Map));
      }

      setState(() => allAttendance = data);
      _computeMonthStats();
    } catch (_) {}
  }

  void _computeMonthStats() {
    final monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final lastDay = monthEnd.isAfter(todayOnly) ? todayOnly : monthEnd;

    int full = 0, half = 0, absent = 0;

    for (DateTime d = monthStart; !d.isAfter(lastDay); d = d.add(const Duration(days: 1))) {
      final key = getDateKey(d);
      final record = allAttendance[key];
      final isToday = key == getDateKey();

      if (record == null) {
        absent++;
        continue;
      }

      final sessions = _sessionsFromRecord(record);
      if (sessions.isEmpty) {
        absent++;
        continue;
      }

      final hasOpen = sessions.last.punchOut == null;
      if (hasOpen) {
        if (!isToday) absent++;
        continue;
      }

      final result = AttendanceCalculator.calculateFromSessions(
        sessions,
        workFromHome: record['workFromHome'] == true,
      );

      if (result.dayType == DayType.fullDay) {
        full++;
      } else if (result.dayType == DayType.halfDay) {
        half++;
      } else {
        absent++;
      }
    }

    if (!mounted) return;
    setState(() {
      fullDayCount = full;
      halfDayCount = half;
      absentCount = absent;
    });
  }

  Future<void> _pickMonth() async {
    final months = List.generate(12, (i) => DateTime(DateTime.now().year, DateTime.now().month - i, 1));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: months
              .map((m) => ListTile(
                    title: Text(DateFormat("MMMM yyyy").format(m)),
                    onTap: () => Navigator.pop(context, m),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) {
      setState(() => selectedMonth = picked);
      _computeMonthStats();
    }
  }

  Future<void> _requestWfh() async {
    final date = getDateKey();
    final existingSnap = await dbRef.child("WorkFromHomeRequests").child(widget.employeeId).child(date).get();
    if (existingSnap.exists) {
      final data = Map<dynamic, dynamic>.from(existingSnap.value as Map);
      setState(() => wfhStatusToday = data["status"]?.toString());
      return;
    }

    if (currentLocation == null) {
      await _refreshLocation();
    }

    final location = currentLocation;

    await dbRef.child("WorkFromHomeRequests").child(widget.employeeId).child(date).set({
      "employeeId": widget.employeeId,
      "employeeName": employeeName,
      "status": "pending",
      "requestedAt": DateTime.now().toIso8601String(),
      if (location != null) "latitude": location.latitude,
      if (location != null) "longitude": location.longitude,
      if (location != null) "address": location.address,
    });

    await NotificationCenter.sendAdmin(
      title: "Work From Home Request",
      message: "$employeeName has requested to work from home today ($date).",
    );

    if (!mounted) return;
    setState(() => wfhStatusToday = "pending");
  }

  List<AttendanceSession> _sessionsFromRecord(Map<dynamic, dynamic> record) {
    final sessions = <AttendanceSession>[];
    final raw = record["sessions"];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item["punchIn"].toString(),
              punchOut: item["punchOut"]?.toString(),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item["punchIn"].toString(),
              punchOut: item["punchOut"]?.toString(),
            ),
          );
        }
      }
    }

    if (sessions.isEmpty && record["punchIn"] != null) {
      sessions.add(
        AttendanceSession(
          punchIn: record["punchIn"].toString(),
          punchOut: record["punchOut"]?.toString(),
        ),
      );
    }

    return sessions;
  }

  List<Map<String, dynamic>> _sessionMapsFromRecord(Map<dynamic, dynamic> record) {
    final raw = record["sessions"];
    final result = <Map<String, dynamic>>[];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item["punchIn"] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item["punchIn"] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (result.isEmpty && record["punchIn"] != null) {
      result.add({
        "punchIn": record["punchIn"],
        if (record["punchOut"] != null) "punchOut": record["punchOut"],
        "workFromHome": record["workFromHome"] == true,
      });
    }

    return result;
  }

  Future<bool> _passesIntegrityChecks() async {
    if (locationStatus == LocationStatus.mockDetected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Mock location detected. Disable fake GPS apps to check in.")),
      );
      return false;
    }

    final timeValid = await TimeIntegrityHelper.isDeviceTimeValid();
    if (!timeValid) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Your device's date & time looks incorrect. Enable automatic date & time and try again.")),
      );
      return false;
    }

    return true;
  }

  Future<void> _punchIn({required bool bypassGeofence}) async {
    if (isSubmitting) return;

    // Multiple sessions are allowed. Only an already-open session blocks
    // another check-in.
    if (status == "Checked In") return;

    if (!bypassGeofence && !WorkSchedule.canCheckIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Office check-in is available only from 8:00 AM to 12:00 AM.')),
      );
      return;
    }

    if (!bypassGeofence &&
        (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentLocation == null
                ? "Unable to verify location"
                : "You're ${distance}m from the office",
          ),
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);
    if (!await _passesIntegrityChecks()) {
      if (mounted) setState(() => isSubmitting = false);
      return;
    }

    final date = getDateKey();
    final time = TimeOfDay.now().format(context);
    final location = currentLocation;
    final dayRef = dbRef.child("Attendance").child(widget.employeeId).child(date);

    try {
      final result = await dayRef.runTransaction((Object? currentData) {
        final data = currentData == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(currentData as Map);

        final sessions = _sessionMapsFromRecord(data);

        // Never create two open sessions.
        if (sessions.isNotEmpty && sessions.last["punchOut"] == null) {
          return Transaction.abort();
        }

        sessions.add({
          "punchIn": time,
          "workFromHome": bypassGeofence,
          if (location != null && !bypassGeofence) ...{
            "punchInLat": location.latitude,
            "punchInLng": location.longitude,
            "punchInAddress": location.address,
          },
          if (bypassGeofence) "punchInAddress": "Work From Home",
        });

        data["employeeId"] = widget.employeeId;
        data["date"] = date;
        data["sessions"] = sessions;

        // Keep these legacy summary fields synchronized for existing screens,
        // reports, and backward compatibility. They represent the LAST session.
        data["punchIn"] = time;
        data["punchOut"] = null;
        data["status"] = "Checked In";
        data["workFromHome"] = bypassGeofence;
        data["shiftType"] = WorkSchedule.shiftName;

        return Transaction.success(data);
      });

      if (!mounted) return;
      if (!result.committed) {
        await _loadTodayAttendance();
        if (mounted) setState(() => isSubmitting = false);
        return;
      }

      setState(() {
        _todaySessions = [
          ..._todaySessions,
          AttendanceSession(punchIn: time),
        ];
        punchInTime = time;
        punchOutTime = "--:--";
        status = "Checked In";
        checkedInAsWfh = bypassGeofence;
        isSubmitting = false;
        _updateClassification();
      });

      await NotificationCenter.sendAdmin(
        title: "Employee Checked In",
        message: "$employeeName checked in at $time${bypassGeofence ? ' (Work From Home)' : ''}.",
      );
    } catch (_) {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _punchOut({required bool bypassGeofence}) async {
    if (isSubmitting) return;
    if (status != "Checked In") return;

    if (!bypassGeofence && !WorkSchedule.canCheckOut) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Office check-out is available only until 12:00 AM.')),
      );
      return;
    }

    if (!bypassGeofence &&
        (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentLocation == null
                ? "Unable to verify location"
                : "You're ${distance}m from the office",
          ),
        ),
      );
      return;
    }

    setState(() => isSubmitting = true);
    if (!await _passesIntegrityChecks()) {
      if (mounted) setState(() => isSubmitting = false);
      return;
    }

    final date = getDateKey();
    final time = TimeOfDay.now().format(context);
    final location = currentLocation;
    final dayRef = dbRef.child("Attendance").child(widget.employeeId).child(date);

    try {
      final result = await dayRef.runTransaction((Object? currentData) {
        if (currentData == null) return Transaction.abort();

        final data = Map<String, dynamic>.from(currentData as Map);
        final sessions = _sessionMapsFromRecord(data);

        if (sessions.isEmpty || sessions.last["punchOut"] != null) {
          return Transaction.abort();
        }

        final last = Map<String, dynamic>.from(sessions.last);
        last["punchOut"] = time;

        if (bypassGeofence) {
          last["punchOutAddress"] = "Work From Home";
        } else if (location != null) {
          last["punchOutLat"] = location.latitude;
          last["punchOutLng"] = location.longitude;
          last["punchOutAddress"] = location.address;
        }

        sessions[sessions.length - 1] = last;

        final attendanceSessions = sessions
            .map(
              (s) => AttendanceSession(
                punchIn: s["punchIn"].toString(),
                punchOut: s["punchOut"]?.toString(),
              ),
            )
            .toList();

        final attendance = AttendanceCalculator.calculateFromSessions(
          attendanceSessions,
          workFromHome: data["workFromHome"] == true,
        );

        data["sessions"] = sessions;

        // Legacy summary fields always represent the LAST completed session.
        data["punchIn"] = last["punchIn"];
        data["punchOut"] = last["punchOut"];
        data["status"] = "Checked Out";
        data["attendanceStatus"] = attendance.label;
        data["netWorkMinutes"] = (attendance.netHours * 60).round();
        data["shortfallMinutes"] = (attendance.shortfallHours * 60).round();
        data["extraWorkMinutes"] = (attendance.extraHours * 60).round();

        return Transaction.success(data);
      });

      if (!mounted) return;
      if (!result.committed) {
        await _loadTodayAttendance();
        if (mounted) setState(() => isSubmitting = false);
        return;
      }

      final updatedSessions = _todaySessions.isEmpty
          ? <AttendanceSession>[]
          : [
              ..._todaySessions.sublist(0, _todaySessions.length - 1),
              AttendanceSession(
                punchIn: _todaySessions.last.punchIn,
                punchOut: time,
              ),
            ];

      setState(() {
        _todaySessions = updatedSessions;
        punchOutTime = time;
        status = "Checked Out";
        isSubmitting = false;
        _updateClassification();
      });

      await _loadMonthlyAttendance();

      final attendance = AttendanceCalculator.calculateFromSessions(
        _todaySessions,
        workFromHome: checkedInAsWfh ?? false,
      );

      if (attendance.dayType == DayType.misPunch) {
        await dbRef
            .child('PunchRequests')
            .child(widget.employeeId)
            .child(date)
            .set({
          'employeeId': widget.employeeId,
          'date': date,
          'type': 'mis_punch',
          'status': 'pending',
          'shortfallMinutes': (attendance.shortfallHours * 60).round(),
          'message':
              'Worked ${AttendanceCalculator.formatHours(attendance.netHours)}; 9 hours are required.',
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      final requestsSnap =
          await dbRef.child('PunchRequests').child(widget.employeeId).get();
      if (requestsSnap.exists) {
        final requests = Map<dynamic, dynamic>.from(requestsSnap.value as Map);
        String? pendingDate;
        requests.forEach((dateKey, value) {
          final request = Map<dynamic, dynamic>.from(value as Map);
          if (request['type'] == 'auto_checkout' &&
              request['status'] == 'pending') {
            pendingDate = dateKey.toString();
          }
        });
        if (mounted) setState(() => pendingAutoCheckoutDate = pendingDate);
      }

      await _updateCompensationBalance(date);

      await NotificationCenter.sendAdmin(
        title: "Employee Checked Out",
        message: "$employeeName checked out at $time.",
      );
    } catch (_) {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  Future<void> _updateCompensationBalance(String currentDate) async {
    final snapshot =
        await dbRef.child('Attendance').child(widget.employeeId).get();
    if (!snapshot.exists) return;

    final records = Map<dynamic, dynamic>.from(snapshot.value as Map);
    final dates = records.keys.map((key) => key.toString()).toList()..sort();

    var balance = 0;

    for (final key in dates) {
      final record = Map<dynamic, dynamic>.from(records[key] as Map);
      final sessions = _sessionsFromRecord(record);

      if (sessions.isEmpty ||
          sessions.last.punchOut == null ||
          record['workFromHome'] == true ||
          record['attendanceOverride'] == 'Full Day Approved') {
        continue;
      }

      final result = AttendanceCalculator.calculateFromSessions(
        sessions,
        workFromHome: record['workFromHome'] == true,
      );

      balance = (balance +
              (result.shortfallHours * 60).round() -
              (result.extraHours * 60).round())
          .clamp(0, 1 << 30)
          .toInt();
    }

    await dbRef
        .child('AttendanceSummary')
        .child(widget.employeeId)
        .update({
      'outstandingMinutes': balance,
      'updatedAt': DateTime.now().toIso8601String(),
    });

    await dbRef
        .child('Attendance')
        .child(widget.employeeId)
        .child(currentDate)
        .update({'outstandingBalanceMinutes': balance});
  }

  Future<void> _recordBreak({required bool isLunch, required bool start}) async {
    if (status != "Checked In" || isSubmitting) return;
    final allowed = isLunch ? (start ? WorkSchedule.canStartLunch : WorkSchedule.canEndLunch) : (start ? WorkSchedule.canStartTea : WorkSchedule.canEndTea);
    if (!allowed) {
      final name = isLunch ? "Lunch" : "Tea";
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("$name ${start ? 'break' : 'return'} is not available at this time.")));
      return;
    }
    final field = isLunch ? (start ? "lunchBreakStart" : "lunchBreakEnd") : (start ? "teaBreakStart" : "teaBreakEnd");
    final time = TimeOfDay.now().format(context);
    setState(() => isSubmitting = true);
    try {
      await dbRef.child("Attendance").child(widget.employeeId).child(getDateKey()).update({field: time});
      if (!mounted) return;
      setState(() {
        if (isLunch) {
          if (start) lunchBreakStart = time; else lunchBreakEnd = time;
        } else {
          if (start) teaBreakStart = time; else teaBreakEnd = time;
        }
        isSubmitting = false;
      });
    } catch (_) {
      if (mounted) setState(() => isSubmitting = false);
    }
  }

  int? _parseTimeToMinutes(String? t) {
    if (t == null || t == "--:--") return null;
    try {
      final cleaned = t.trim().toUpperCase();
      final isPM = cleaned.contains("PM");
      final isAM = cleaned.contains("AM");
      final numeric = cleaned.replaceAll(RegExp(r'[AP]M'), '').trim();
      final parts = numeric.split(':');
      int hour = int.parse(parts[0].trim());
      final minute = int.parse(parts[1].trim());
      if (isPM && hour != 12) hour += 12;
      if (isAM && hour == 12) hour = 0;
      return hour * 60 + minute;
    } catch (_) {
      return null;
    }
  }

  int _timeOfDayMinutes(TimeOfDay t) => t.hour * 60 + t.minute;

  int get _shiftTotalMinutes => WorkSchedule.requiredWorkMinutes;

  int get _breakBudgetMinutes {
    final lunch = _timeOfDayMinutes(WorkSchedule.lunchEnd) - _timeOfDayMinutes(WorkSchedule.lunchStart);
    final tea = _timeOfDayMinutes(WorkSchedule.teaEnd) - _timeOfDayMinutes(WorkSchedule.teaStart);
    return lunch + tea;
  }

  int get _breakMinutesTaken {
    int total = 0;
    final nowMinutes = _now.hour * 60 + _now.minute;

    final ls = _parseTimeToMinutes(lunchBreakStart);
    final le = _parseTimeToMinutes(lunchBreakEnd);
    if (ls != null) {
      if (le != null) {
        total += (le - ls).clamp(0, 1000);
      } else if (status == "Checked In") {
        total += (nowMinutes - ls).clamp(0, 1000);
      }
    }

    final ts = _parseTimeToMinutes(teaBreakStart);
    final te = _parseTimeToMinutes(teaBreakEnd);
    if (ts != null) {
      if (te != null) {
        total += (te - ts).clamp(0, 1000);
      } else if (status == "Checked In") {
        total += (nowMinutes - ts).clamp(0, 1000);
      }
    }

    return total;
  }

  int get _workingMinutesLive {
    if (_todaySessions.isEmpty) return 0;

    final sessions = <AttendanceSession>[];

    for (final session in _todaySessions) {
      sessions.add(session);
    }

    // If the current session is open, calculate through the current minute
    // for the live dashboard only. The saved attendance is still closed only
    // when the employee explicitly checks out.
    if (status == "Checked In" && sessions.last.punchOut == null) {
      final nowText = TimeOfDay.fromDateTime(_now).format(context);
      final liveSessions = [
        ...sessions.sublist(0, sessions.length - 1),
        AttendanceSession(
          punchIn: sessions.last.punchIn,
          punchOut: nowText,
        ),
      ];

      final result = AttendanceCalculator.calculateFromSessions(
        liveSessions,
        workFromHome: checkedInAsWfh ?? false,
      );
      return (result.netHours * 60).round();
    }

    final result = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: checkedInAsWfh ?? false,
    );
    return (result.netHours * 60).round();
  }

  double get _shiftProgress => _shiftTotalMinutes <= 0 ? 0 : (_workingMinutesLive / _shiftTotalMinutes).clamp(0.0, 1.0);
  double get _breakProgress => _breakBudgetMinutes <= 0 ? 0 : (_breakMinutesTaken / _breakBudgetMinutes).clamp(0.0, 1.0);

  String _formatMinutes(int minutes) {
    final m = minutes < 0 ? 0 : minutes;
    final h = m ~/ 60;
    final mm = m % 60;
    return "${h}h ${mm.toString().padLeft(2, '0')}m";
  }

  String get _greeting {
    final h = _now.hour;
    if (h < 12) return "Good Morning";
    if (h < 17) return "Good Afternoon";
    return "Good Evening";
  }

  Widget _logoMark({double size = 22}) {
    return Image.asset(
      'assets/images/workora_logo.png',
      height: size,
      width: size,
      errorBuilder: (_, __, ___) => Icon(Icons.blur_circular_rounded, color: AppColors.brightBlue, size: size),
    );
  }

  String get _initials {
    final name = employeeName.isEmpty ? widget.employeeId : employeeName;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kHeroDark1,
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : RefreshIndicator(
                      onRefresh: () async {
                        await _loadTodayAttendance();
                        await _loadMonthlyAttendance();
                        await _refreshLocation();
                      },
                      child: ListView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
                        children: [
                          _buildTabSwitcher(),
                          if (pendingAutoCheckoutDate != null) ...[
                            const SizedBox(height: 12),
                            _autoCheckoutBanner(),
                          ],
                          const SizedBox(height: 14),
                          _buildHeroCard(),
                          const SizedBox(height: 16),
                          _buildQuickActions(),
                          const SizedBox(height: 16),
                          _buildAnnouncementCarousel(),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    ImageProvider? avatarImage;
    if (employeePhotoBase64 != null && employeePhotoBase64!.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(employeePhotoBase64!));
      } catch (_) {
        avatarImage = null;
      }
    }

    return Container(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [_kHeroDark1, _kHeroDark2])),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _logoMark(),
                  const SizedBox(width: 6),
                  const Text("workora", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -.6)),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: _openAccountSettings,
                    child: Stack(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(shape: BoxShape.circle, gradient: avatarImage == null ? AppGradients.punchCard : null),
                          child: avatarImage != null
                              ? ClipOval(child: Image(image: avatarImage, width: 52, height: 52, fit: BoxFit.cover))
                              : Center(child: Text(_initials, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18))),
                        ),
                        Positioned(
                          right: 1,
                          bottom: 1,
                          child: Container(
                            width: 13,
                            height: 13,
                            decoration: BoxDecoration(color: AppColors.success, shape: BoxShape.circle, border: Border.all(color: _kHeroDark2, width: 2)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("$_greeting,", style: const TextStyle(color: Colors.white60, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text(
                          "${employeeName.isEmpty ? widget.employeeId : employeeName} \u{1F44B}",
                          style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                          child: Text("ID: ${widget.employeeId}", style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: widget.employeeId))),
                    child: StreamBuilder<int>(
                      stream: NotificationCenter.unreadCount(widget.employeeId),
                      builder: (context, snapshot) {
                        final count = snapshot.data ?? 0;
                        return Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(14)),
                          child: Badge(
                            isLabelVisible: count > 0,
                            label: Text("$count"),
                            backgroundColor: AppColors.danger,
                            child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 20),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final checkedIn = status == "Checked In";
    final done = false;
    final hasSessions = _todaySessions.isNotEmpty;
    final isWfh = showHomeTab && wfhStatusToday == "approved";
    final canAct = isWfh || (locationStatus == LocationStatus.granted && (currentLocation?.isWithinOfficeRange ?? false));
    final statusLabel = done ? "YOU ARE\nCOMPLETED" : (checkedIn ? "YOU ARE\nCHECKED IN" : "READY TO\nCHECK IN");
    final focalTime = checkedIn || done ? punchInTime : DateFormat("hh:mm a").format(_now);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppGradients.punchCard, borderRadius: BorderRadius.circular(28), boxShadow: AppShadows.hero),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("CURRENT TIME", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: .5)),
                    const SizedBox(height: 6),
                    Text(DateFormat("hh:mm a").format(_now), style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(DateFormat("EEE, dd MMM yyyy").format(_now), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              SizedBox(
                width: 168,
                height: 168,
                child: CustomPaint(
                  painter: ShiftRingPainter(progress: _shiftProgress),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(statusLabel, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: .5, height: 1.3)),
                        const SizedBox(height: 6),
                        Text(focalTime, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 10),
                        _buildActionPill(checkedIn: checkedIn, done: done, canAct: canAct, isWfh: isWfh),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.work_outline_rounded, color: Colors.white, size: 14)),
                      const SizedBox(width: 6),
                      const Expanded(child: Text("Today's Work", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 6),
                    Text(_formatMinutes(_workingMinutesLive), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text("of ${_formatMinutes(_shiftTotalMinutes)}", style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _shiftProgress, minHeight: 5, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white))),
                    const SizedBox(height: 16),
                    Row(children: [
                      Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: const Icon(Icons.local_cafe_outlined, color: Colors.white, size: 14)),
                      const SizedBox(width: 6),
                      const Expanded(child: Text("Break Time", style: TextStyle(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 6),
                    Text(_formatMinutes(_breakMinutesTaken), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w800)),
                    Text("of ${_formatMinutes(_breakBudgetMinutes)}", style: const TextStyle(color: Colors.white60, fontSize: 10)),
                    const SizedBox(height: 6),
                    ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: _breakProgress, minHeight: 5, backgroundColor: Colors.white24, valueColor: const AlwaysStoppedAnimation(Colors.white))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(children: [
            const Icon(Icons.location_on_outlined, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Expanded(child: Text(isWfh ? "Work From Home" : (currentLocation?.address ?? "Checking your location..."), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 12))),
            if (!isWfh) ...[const Icon(Icons.verified_rounded, color: Color(0xFFA7F3D0), size: 16), const SizedBox(width: 4), const Text("GPS Verified", style: TextStyle(color: Color(0xFFA7F3D0), fontSize: 11, fontWeight: FontWeight.w700))],
          ]),
          if (checkedIn && !done && (WorkSchedule.isLunchBreak || WorkSchedule.isTeaBreak)) ...[
            const SizedBox(height: 14),
            _buildBreakStatus(),
          ],
          if (showHomeTab && wfhStatusToday != "approved" && !checkedIn) ...[
            const SizedBox(height: 12),
            TextButton.icon(onPressed: wfhStatusToday == null ? _requestWfh : null, icon: const Icon(Icons.home_work_outlined, color: Colors.white, size: 17), label: Text(wfhStatusToday == "pending" ? "WFH approval pending" : "Request Work From Home", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ],
        ],
      ),
    );
  }

  Widget _buildActionPill({required bool checkedIn, required bool done, required bool canAct, required bool isWfh}) {
    if (done) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(20)),
        child: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.check_circle_outline, color: Colors.white, size: 14), SizedBox(width: 6), Text("Completed", style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))]),
      );
    }

    final isCheckOut = checkedIn;
    final enabled = !isSubmitting && canAct;

    return SizedBox(
      height: 34,
      child: ElevatedButton(
        onPressed: !enabled
            ? null
            : () => isCheckOut ? _punchOut(bypassGeofence: isWfh) : _punchIn(bypassGeofence: isWfh),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
        child: isSubmitting
            ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(isCheckOut ? "CHECK OUT" : "CHECK IN", style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_forward_rounded, size: 14),
                ],
              ),
      ),
    );
  }

  Widget _buildBreakStatus() {
    final isLunch = WorkSchedule.isLunchBreak;
    return Container(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(isLunch ? Icons.restaurant_outlined : Icons.coffee_outlined, color: Colors.white, size: 18), const SizedBox(width: 8), Text(isLunch ? 'Lunch break \u00b7 1:00 PM \u2013 2:00 PM' : 'Tea break \u00b7 4:30 PM \u2013 5:00 PM', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))]));
  }

  Widget _buildStatsRow() {
    final total = fullDayCount + halfDayCount + absentCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text("Attendance for this month", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            OutlinedButton.icon(
              onPressed: _pickMonth,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.calendar_today, size: 14),
              label: Text(DateFormat("MMM").format(selectedMonth).toUpperCase()),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildStatCard(Icons.event_available_outlined, "Full Day", fullDayCount, total, AppColors.success, AppColors.successLight)),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(Icons.event_note_outlined, "Half Day", halfDayCount, total, AppColors.warning, AppColors.warningLight)),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(Icons.event_busy_outlined, "Absent", absentCount, total, AppColors.danger, AppColors.dangerLight)),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(IconData icon, String label, int value, int total, Color color, Color bg) {
    final percent = total == 0 ? 0.0 : value / total;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(padding: const EdgeInsets.all(7), decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, color: color, size: 15)),
              SizedBox(
                width: 30,
                height: 30,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(size: const Size(30, 30), painter: PercentRingPainter(percent: percent, color: color)),
                    Text("${(percent * 100).round()}%", style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text("$value", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const Text("Days", style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildQuickActions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Quick Actions", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(children: [
            Expanded(child: _quickAction("assets/icons/leave.png", "Request\nLeave", AppColors.violet, () => Navigator.push(context, MaterialPageRoute(builder: (_) => LeaveScreen(employeeId: widget.employeeId, employeeName: employeeName.isEmpty ? widget.employeeId : employeeName))))),
            const SizedBox(width: 10),
            Expanded(child: _quickAction("assets/icons/payslip.png", "Payslip\n", AppColors.indigo, () => Navigator.push(context, MaterialPageRoute(builder: (_) => PayslipRequestScreen(employeeId: widget.employeeId, employeeName: employeeName.isEmpty ? widget.employeeId : employeeName))))),
            const SizedBox(width: 10),
            Expanded(child: _quickAction("assets/icons/live_location.png", "Live\nLocation", AppColors.success, () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LiveLocationScreen())))),
            const SizedBox(width: 10),
            Expanded(child: _quickAction("assets/icons/attendance_history.png", "Attendance\nHistory", AppColors.warning, () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(employeeId: widget.employeeId, employeeName: employeeName.isEmpty ? widget.employeeId : employeeName))))),
          ]),
        ),
      ],
    );
  }

  Widget _quickAction(String iconAsset, String label, Color color, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(14)),
                child: Image.asset(
                  iconAsset,
                  width: 32,
                  height: 32,
                  errorBuilder: (_, __, ___) => Icon(Icons.image_not_supported_outlined, color: color, size: 26),
                ),
              ),
              const SizedBox(height: 14),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, height: 1.2, color: AppColors.textPrimary)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: Container(padding: const EdgeInsets.all(4), decoration: BoxDecoration(color: color.withOpacity(.12), shape: BoxShape.circle), child: Icon(Icons.arrow_forward_rounded, size: 12, color: color))),
            ],
          ),
        ),
      );

  List<_ActivityItem> _buildActivityItems() {
    final items = <_ActivityItem>[];
    final isWfh = showHomeTab && wfhStatusToday == "approved";

    for (int i = 0; i < _todaySessions.length; i++) {
      final session = _todaySessions[i];

      items.add(
        _ActivityItem(
          time: session.punchIn,
          label: "Checked In",
          status: isWfh ? "Work From Home" : "Office",
          icon: Icons.login_rounded,
          color: AppColors.success,
          bg: AppColors.successLight,
        ),
      );

      if (session.punchOut != null) {
        items.add(
          _ActivityItem(
            time: session.punchOut!,
            label: "Checked Out",
            status: "Completed",
            icon: Icons.logout_rounded,
            color: AppColors.violet,
            bg: AppColors.background,
          ),
        );
      } else {
        items.add(
          _ActivityItem(
            time: "--:--",
            label: "Check Out",
            status: "Pending",
            icon: Icons.logout_rounded,
            color: AppColors.textSecondary,
            bg: AppColors.background,
          ),
        );
      }
    }

    if (lunchBreakStart != null) {
      items.add(
        _ActivityItem(
          time: lunchBreakStart!,
          label: "Lunch Break",
          status: lunchBreakEnd != null ? "Completed" : "In Progress",
          icon: Icons.restaurant_outlined,
          color: AppColors.warning,
          bg: AppColors.warningLight,
        ),
      );
    }

    if (teaBreakStart != null) {
      items.add(
        _ActivityItem(
          time: teaBreakStart!,
          label: "Tea Break",
          status: teaBreakEnd != null ? "Completed" : "In Progress",
          icon: Icons.coffee_outlined,
          color: AppColors.warning,
          bg: AppColors.warningLight,
        ),
      );
    }

    return items;
  }

  Widget _buildTodayActivity() {
    final items = _buildActivityItems();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Today's activity", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(employeeId: widget.employeeId, employeeName: employeeName.isEmpty ? widget.employeeId : employeeName))),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [Text("View Timeline", style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700)), Icon(Icons.chevron_right, color: AppColors.primary, size: 16)]),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (items.isEmpty)
            const Text("Your check-in and check-out activity will appear here.", style: TextStyle(color: AppColors.textSecondary, fontSize: 12))
          else
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(items.length, (i) => _timelineItem(items[i], isFirst: i == 0, isLast: i == items.length - 1)),
            ),
        ],
      ),
    );
  }

  Widget _timelineItem(_ActivityItem item, {required bool isFirst, required bool isLast}) {
    return Expanded(
      child: Column(
        children: [
          SizedBox(
            height: 32,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (!isFirst) Positioned(left: 0, right: 16, child: Container(height: 2, color: AppColors.divider)),
                if (!isLast) Positioned(left: 16, right: 0, child: Container(height: 2, color: AppColors.divider)),
                Container(width: 30, height: 30, decoration: BoxDecoration(color: item.bg, shape: BoxShape.circle), child: Icon(item.icon, size: 14, color: item.color)),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(item.time, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
          const SizedBox(height: 2),
          Text(item.label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 9, color: AppColors.textSecondary)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: item.color.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
            child: Text(item.status, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: item.color)),
          ),
        ],
      ),
    );
  }

  Widget _buildAnnouncementCarousel() {
    return StreamBuilder<DatabaseEvent>(
      stream: dbRef.child('Announcements').onValue,
      builder: (context, snapshot) {
        final announcements = <Map<String, String>>[];
        if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
          final value = snapshot.data!.snapshot.value;
          if (value is Map) {
            final raw = Map<dynamic, dynamic>.from(value);
            raw.forEach((_, value) {
              if (value is Map) {
                final item = Map<dynamic, dynamic>.from(value);
                announcements.add({'title': item['title']?.toString() ?? 'Announcement', 'createdAt': item['createdAt']?.toString() ?? ''});
              }
            });
            announcements.sort((a, b) => b['createdAt']!.compareTo(a['createdAt']!));
          }
        }
        return _announcementTitleList(announcements);
      },
    );
  }

  Widget _autoCheckoutBanner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.warning.withOpacity(.14), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.warning.withOpacity(.45))),
    child: Row(children: [
      const Icon(Icons.pending_actions, color: AppColors.warning),
      const SizedBox(width: 10),
      Expanded(child: Text('Punchout request sent for $pendingAutoCheckoutDate. It is waiting for admin verification and checkout-time approval.', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]),
  );

  Widget _announcementTitleList(List<Map<String, String>> announcements) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.hero),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Row(children: [Icon(Icons.campaign_rounded, color: Colors.white, size: 28), SizedBox(width: 10), Text('Announcements', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))]),
        const SizedBox(height: 12),
        if (announcements.isEmpty)
          const Text('No announcements yet!', style: TextStyle(color: Colors.white70))
        else
          ...announcements.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Material(
              color: Colors.white.withOpacity(.14),
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementDetailScreen())),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                  child: Row(children: [const Icon(Icons.article_outlined, color: Colors.white, size: 18), const SizedBox(width: 9), Expanded(child: Text(item['title']!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))), const Icon(Icons.chevron_right, color: Colors.white)]),
                ),
              ),
            ),
          )),
      ]),
    );
  }

  Widget _announcementCard(Map<String, dynamic>? data) {
    final hasAnnouncement = data != null;
    final title = data?["title"]?.toString() ?? "";
    final message = data?["message"]?.toString() ?? "";
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(22), boxShadow: AppShadows.hero),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.campaign_rounded, color: Colors.white, size: 34),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Company announcement', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                if (hasAnnouncement) ...[
                  Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 34,
                    child: ElevatedButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AnnouncementDetailScreen())),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary, padding: const EdgeInsets.symmetric(horizontal: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                      child: const Row(mainAxisSize: MainAxisSize.min, children: [Text("View Details", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)), SizedBox(width: 3), Icon(Icons.chevron_right, size: 15)]),
                    ),
                  ),
                ] else
                  const Text("No announcements yet!", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    final locked = status == "Checked In";
    final homeLocked = locked && checkedInAsWfh == false;
    final officeLocked = locked && checkedInAsWfh == true;

    void lockedTap() {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("You checked in via ${checkedInAsWfh! ? 'Work From Home' : 'Office'} today. Check out first to switch.")),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(30), boxShadow: AppShadows.card),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              "Home",
              Icons.home_outlined,
              showHomeTab,
              homeLocked ? lockedTap : () => setState(() => showHomeTab = true),
              disabled: homeLocked,
            ),
          ),
          Expanded(
            child: _tabButton(
              "Office",
              Icons.apartment_outlined,
              !showHomeTab,
              officeLocked ? lockedTap : () => setState(() => showHomeTab = false),
              disabled: officeLocked,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, IconData icon, bool selected, VoidCallback onTap, {bool disabled = false}) {
    final iconColor = selected ? Colors.white : (disabled ? AppColors.divider : AppColors.textSecondary);
    final textColor = selected ? Colors.white : (disabled ? AppColors.divider : AppColors.textSecondary);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: iconColor),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
            if (disabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.lock_outline, size: 12, color: iconColor),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActivityItem {
  final String time;
  final String label;
  final String status;
  final IconData icon;
  final Color color;
  final Color bg;

  _ActivityItem({required this.time, required this.label, required this.status, required this.icon, required this.color, required this.bg});
}