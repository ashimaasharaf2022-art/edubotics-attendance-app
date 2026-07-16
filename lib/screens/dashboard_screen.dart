import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/location_helper.dart';
import '../utils/time_integrity_helper.dart';
import '../utils/notification_center.dart';
import 'leave_screen.dart';
import 'notifications_screen.dart';

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

  bool showHomeTab = false;
  bool isLoading = true;
  bool isSubmitting = false;

  Timer? _clockTimer;
  DateTime _now = DateTime.now();

  String punchInTime = "--:--";
  String punchOutTime = "--:--";
  String status = "Not Checked In";
  String workingHours = "0 hr 0 min";
  DayType? dayType;

  String? wfhStatusToday;
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
    _refreshLocation();
    _loadMonthlyAttendance();
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadEmployeeInfo() async {
    try {
      final snapshot = await dbRef.child("users").child(widget.employeeId).get();
      if (!mounted) return;
      if (snapshot.exists) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final name = (data["name"] ?? widget.employeeId).toString();
        setState(() => employeeName = name);
        widget.onNameLoaded?.call(name);
      }
    } catch (_) {}
  }

  String getDateKey([DateTime? d]) {
    final date = d ?? DateTime.now();
    return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
  }

  void _updateClassification() {
    if (punchInTime == "--:--" || punchOutTime == "--:--") {
      dayType = null;
      workingHours = "0 hr 0 min";
      return;
    }
    final result = AttendanceCalculator.calculate(punchIn: punchInTime, punchOut: punchOutTime);
    dayType = result.dayType;
    workingHours = AttendanceCalculator.formatHours(result.netHours);
  }

  Future<void> _loadTodayAttendance() async {
    try {
      final snapshot = await dbRef.child("Attendance").child(widget.employeeId).child(getDateKey()).get();
      if (!mounted) return;

      if (snapshot.exists) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        setState(() {
          punchInTime = data["punchIn"] ?? "--:--";
          punchOutTime = data["punchOut"] ?? "--:--";
          status = data["status"] ?? "Not Checked In";
          _updateClassification();
        });
      }

      final wfhSnap = await dbRef.child("WorkFromHomeRequests").child(widget.employeeId).child(getDateKey()).get();
      if (wfhSnap.exists) {
        final wfhData = Map<dynamic, dynamic>.from(wfhSnap.value as Map);
        if (!mounted) return;
        setState(() {
          wfhStatusToday = wfhData["status"]?.toString();
          if (wfhStatusToday == "approved" || wfhStatusToday == "pending") showHomeTab = true;
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

    // Every calendar day counts as a working day \u2014 no weekends
    // or holidays are excluded from this calculation.
    for (DateTime d = monthStart; !d.isAfter(lastDay); d = d.add(const Duration(days: 1))) {
      final key = getDateKey(d);
      final record = allAttendance[key];
      final isToday = getDateKey(d) == getDateKey();

      if (record == null || record["punchIn"] == null) {
        absent++;
        continue;
      }
      final punchOut = record["punchOut"]?.toString();
      if (punchOut == null) {
        if (isToday) continue;
        absent++;
        continue;
      }
      final result = AttendanceCalculator.calculate(punchIn: record["punchIn"].toString(), punchOut: punchOut);
      if (result.dayType == DayType.fullDay) {
        full++;
      } else if (result.dayType == DayType.halfDay) {
        half++;
      } else {
        absent++;
      }
    }

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

    // Make sure we have a fresh location fix to attach to the request
    // so the admin can see where the employee is asking to work from.
    if (currentLocation == null) {
      await _refreshLocation();
    }

    final location = currentLocation;

    await dbRef.child("WorkFromHomeRequests").child(widget.employeeId).child(date).set({
      "employeeId": widget.employeeId,
      "status": "pending",
      "requestedAt": DateTime.now().toIso8601String(),
      if (location != null) "latitude": location.latitude,
      if (location != null) "longitude": location.longitude,
      if (location != null) "address": location.address,
    });

    if (!mounted) return;
    setState(() => wfhStatusToday = "pending");
  }

  Future<bool> _passesIntegrityChecks({required bool bypassGeofence}) async {
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
    if (status == "Checked In" || status == "Checked Out") return;

    if (!bypassGeofence && (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentLocation == null ? "Unable to verify location" : "You're ${distance}m from the office")),
      );
      return;
    }

    setState(() => isSubmitting = true);
    if (!await _passesIntegrityChecks(bypassGeofence: bypassGeofence)) {
      setState(() => isSubmitting = false);
      return;
    }

    final date = getDateKey();
    final time = TimeOfDay.now().format(context);
    final location = currentLocation;
    final dayRef = dbRef.child("Attendance").child(widget.employeeId).child(date);

    try {
      final result = await dayRef.runTransaction((Object? currentData) {
        final data = currentData == null ? <String, dynamic>{} : Map<String, dynamic>.from(currentData as Map);
        final currentStatus = data["status"] ?? "Not Checked In";
        if (currentStatus == "Checked In" || currentStatus == "Checked Out") return Transaction.abort();

        data["employeeId"] = widget.employeeId;
        data["date"] = date;
        data["punchIn"] = time;
        data["status"] = "Checked In";
        data["workFromHome"] = bypassGeofence;

        if (bypassGeofence) {
          data["punchInAddress"] = "Work From Home";
        } else if (location != null) {
          data["punchInLat"] = location.latitude;
          data["punchInLng"] = location.longitude;
          data["punchInAddress"] = location.address;
        }
        return Transaction.success(data);
      });

      if (!mounted) return;
      if (!result.committed) {
        await _loadTodayAttendance();
        setState(() => isSubmitting = false);
        return;
      }

      setState(() {
        punchInTime = time;
        status = "Checked In";
        isSubmitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
    }
  }

  Future<void> _punchOut({required bool bypassGeofence}) async {
    if (isSubmitting) return;
    if (status != "Checked In") return;

    if (!bypassGeofence && (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(currentLocation == null ? "Unable to verify location" : "You're ${distance}m from the office")),
      );
      return;
    }

    setState(() => isSubmitting = true);
    if (!await _passesIntegrityChecks(bypassGeofence: bypassGeofence)) {
      setState(() => isSubmitting = false);
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
        if (data["status"] != "Checked In") return Transaction.abort();

        data["punchOut"] = time;
        data["status"] = "Checked Out";
        if (bypassGeofence) {
          data["punchOutAddress"] = "Work From Home";
        } else if (location != null) {
          data["punchOutLat"] = location.latitude;
          data["punchOutLng"] = location.longitude;
          data["punchOutAddress"] = location.address;
        }
        return Transaction.success(data);
      });

      if (!mounted) return;
      if (!result.committed) {
        await _loadTodayAttendance();
        setState(() => isSubmitting = false);
        return;
      }

      setState(() {
        punchOutTime = time;
        status = "Checked Out";
        _updateClassification();
        isSubmitting = false;
      });
      _loadMonthlyAttendance();
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat("EEE, dd MMMM yyyy").format(DateTime.now()),
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => NotificationsScreen(employeeId: widget.employeeId)),
                          );
                        },
                        child: StreamBuilder<int>(
                          stream: NotificationCenter.unreadCount(widget.employeeId),
                          builder: (context, snapshot) {
                            final count = snapshot.data ?? 0;
                            return Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
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
                  const SizedBox(height: 18),
                  Text(
                    "Welcome, ${employeeName.isEmpty ? widget.employeeId : employeeName}",
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text("ID: ${widget.employeeId}", style: const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            ),
          ),
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
                        padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                        children: [
                          _buildTabSwitcher(),
                          const SizedBox(height: 16),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                              decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(20)),
                              child: const Text(
                                "GENERAL SHIFT",
                                style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 0.5),
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: AppShadows.card,
                            ),
                            child: showHomeTab ? _buildHomeTabContent() : _buildOfficeTabContent(),
                          ),
                          const SizedBox(height: 28),
                          _buildMonthSection(),
                          const SizedBox(height: 20),
                          _buildRequestLeaveButton(),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabSwitcher() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(30), boxShadow: AppShadows.card),
      child: Row(
        children: [
          Expanded(child: _tabButton("Home", Icons.home_outlined, showHomeTab, () => setState(() => showHomeTab = true))),
          Expanded(child: _tabButton("Office", Icons.apartment_outlined, !showHomeTab, () => setState(() => showHomeTab = false))),
        ],
      ),
    );
  }

  Widget _tabButton(String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(24)),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _liveClockRow({required bool bypassGeofence}) {
    final checkedIn = status == "Checked In";
    final done = status == "Checked Out";
    final canAct = bypassGeofence || (locationStatus == LocationStatus.granted && (currentLocation?.isWithinOfficeRange ?? false));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(DateFormat("hh:mm:ss a").format(_now), style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
        SizedBox(
          height: 44,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: done ? AppColors.textSecondary.withOpacity(0.3) : AppColors.primary,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              padding: const EdgeInsets.symmetric(horizontal: 24),
            ),
            onPressed: (isSubmitting || done || !canAct)
                ? null
                : () => checkedIn ? _punchOut(bypassGeofence: bypassGeofence) : _punchIn(bypassGeofence: bypassGeofence),
            child: isSubmitting
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Text(
                    done ? "Done" : (checkedIn ? "Check Out" : "Check In"),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _locationLine() {
    if (locationStatus == LocationStatus.mockDetected) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(10)),
        child: const Row(
          children: [
            Icon(Icons.gpp_bad, color: AppColors.danger, size: 16),
            SizedBox(width: 6),
            Expanded(child: Text("Mock location detected", style: TextStyle(color: AppColors.danger, fontSize: 12, fontWeight: FontWeight.bold))),
          ],
        ),
      );
    }

    final inRange = currentLocation?.isWithinOfficeRange ?? false;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Icon(Icons.location_on, size: 14, color: inRange ? AppColors.success : AppColors.warning),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              currentLocation?.address ?? "Locating...",
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: inRange ? AppColors.success : AppColors.warning, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfficeTabContent() {
    final wfhApproved = wfhStatusToday == "approved";

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wfhApproved)
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(12)),
            child: const Text(
              "You're approved for Work From Home today \u2014 switch to the Home tab to check in.",
              style: TextStyle(color: AppColors.warning, fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
        _liveClockRow(bypassGeofence: false),
        _locationLine(),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _statColumn(Icons.login, punchInTime, "Check In")),
            Expanded(child: _statColumn(Icons.logout, punchOutTime, "Check Out")),
            Expanded(child: _statColumn(Icons.access_time, workingHours, "Working Hrs")),
          ],
        ),
      ],
    );
  }

  Widget _buildHomeTabContent() {
    if (wfhStatusToday == "approved") {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.successLight, borderRadius: BorderRadius.circular(12)),
            child: const Text("Work From Home approved for today", style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold, fontSize: 12)),
          ),
          _liveClockRow(bypassGeofence: true),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _statColumn(Icons.login, punchInTime, "Check In")),
              Expanded(child: _statColumn(Icons.logout, punchOutTime, "Check Out")),
              Expanded(child: _statColumn(Icons.access_time, workingHours, "Working Hrs")),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wfhStatusToday == "pending")
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.warningLight, borderRadius: BorderRadius.circular(12)),
            child: const Text("WFH request pending admin approval", style: TextStyle(color: AppColors.warning, fontWeight: FontWeight.bold, fontSize: 12)),
          )
        else if (wfhStatusToday == "rejected")
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.dangerLight, borderRadius: BorderRadius.circular(12)),
            child: const Text("WFH request rejected \u2014 please check in from the office", style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold, fontSize: 12)),
          )
        else
          SizedBox(
            height: 50,
            child: OutlinedButton.icon(
              onPressed: _requestWfh,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
              ),
              icon: const Icon(Icons.home_outlined),
              label: const Text("Request Work From Home", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 10),
        const Text("Share Your Location", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.location_on, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                currentLocation?.address ?? "Fetching location...",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            TextButton(onPressed: _refreshLocation, child: const Text("Update Location")),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(12)),
          child: const Row(
            children: [
              Icon(Icons.info_outline, color: AppColors.primary, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Your location is shared with the request. If the admin approves it, you can check in.",
                  style: TextStyle(color: AppColors.primary, fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statColumn(IconData icon, String value, String label) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 22),
        const SizedBox(height: 6),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
      ],
    );
  }

  Widget _buildMonthSection() {
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
            Expanded(child: _monthStatCard("Full Day", fullDayCount, AppColors.success, AppColors.successLight)),
            const SizedBox(width: 10),
            Expanded(child: _monthStatCard("Half Day", halfDayCount, AppColors.warning, AppColors.warningLight)),
            const SizedBox(width: 10),
            Expanded(child: _monthStatCard("Absent", absentCount, AppColors.danger, AppColors.dangerLight)),
          ],
        ),
      ],
    );
  }

  Widget _monthStatCard(String label, int value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border(top: BorderSide(color: color, width: 3))),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary)),
          const SizedBox(height: 6),
          Text("$value", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildRequestLeaveButton() {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => LeaveScreen(
                employeeId: widget.employeeId,
                employeeName: employeeName.isEmpty ? widget.employeeId : employeeName,
              ),
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
        ),
        icon: const Icon(Icons.add),
        label: const Text("Request Leave", style: TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}