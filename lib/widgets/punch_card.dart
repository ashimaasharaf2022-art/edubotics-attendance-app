import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../utils/attendance_calculator.dart';
import '../utils/location_helper.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import '../utils/email_alert_helper.dart';

class PunchCard extends StatefulWidget {
  final String employeeId;
  final bool compact;
  final bool showWfhButton;

  const PunchCard({
    super.key,
    required this.employeeId,
    this.compact = false,
    this.showWfhButton = true,
  });

  @override
  State<PunchCard> createState() => _PunchCardState();
}

class _PunchCardState extends State<PunchCard> {
  late DatabaseReference attendanceRef;

  String punchInTime = "--:--";
  String punchOutTime = "--:--";
  String status = "Not Checked In";
  String workingHours = "0 hr 0 min";
  String? lastAddress;
  double? lastLat;
  double? lastLng;
  bool isWorkFromHome = false;
  String? wfhStatusToday;

  DayType? dayType;
  String? dayTypeLabel;

  bool isLoading = true;
  bool isSubmitting = false;

  LocationStatus locationStatus = LocationStatus.loading;
  LocationResult? currentLocation;

  @override
  void initState() {
    super.initState();
    attendanceRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _initData();
    _refreshLocation();
  }

  Future<void> _initData() async {
    await loadTodayAttendance();
    if (!mounted) return;
    setState(() => isLoading = false);
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

  String getDateKey() {
    DateTime now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
  }

  void _updateClassification() {
    if (punchInTime == "--:--" || punchOutTime == "--:--") {
      dayType = null;
      dayTypeLabel = null;
      workingHours = "0 hr 0 min";
      return;
    }
    final result = AttendanceCalculator.calculate(punchIn: punchInTime, punchOut: punchOutTime);
    dayType = result.dayType;
    dayTypeLabel = result.label;
    workingHours = AttendanceCalculator.formatHours(result.netHours);
  }

  Future<void> loadTodayAttendance() async {
    try {
      final snapshot = await attendanceRef.child("Attendance").child(widget.employeeId).child(getDateKey()).get();
      if (!mounted) return;

      if (snapshot.exists) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        setState(() {
          punchInTime = data["punchIn"] ?? "--:--";
          punchOutTime = data["punchOut"] ?? "--:--";
          status = data["status"] ?? "Not Checked In";
          isWorkFromHome = data["workFromHome"] == true;
          lastAddress = data["punchOutAddress"]?.toString() ?? data["punchInAddress"]?.toString();
          lastLat = double.tryParse((data["punchOutLat"] ?? data["punchInLat"] ?? "").toString());
          lastLng = double.tryParse((data["punchOutLng"] ?? data["punchInLng"] ?? "").toString());
          _updateClassification();
        });
      }

      final wfhSnap = await attendanceRef.child("WorkFromHomeRequests").child(widget.employeeId).child(getDateKey()).get();
      if (wfhSnap.exists) {
        final wfhData = Map<dynamic, dynamic>.from(wfhSnap.value as Map);
        if (!mounted) return;
        setState(() => wfhStatusToday = wfhData["status"]?.toString());
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _requestWfh() async {
    final date = getDateKey();

    final existingSnap = await attendanceRef.child("WorkFromHomeRequests").child(widget.employeeId).child(date).get();
    if (existingSnap.exists) {
      final data = Map<dynamic, dynamic>.from(existingSnap.value as Map);
      setState(() => wfhStatusToday = data["status"]?.toString());
      return;
    }

    await attendanceRef.child("WorkFromHomeRequests").child(widget.employeeId).child(date).set({
      "employeeId": widget.employeeId,
      "status": "pending",
      "requestedAt": DateTime.now().toIso8601String(),
    });

    await EmailAlertHelper.sendAlert(
      subject: "Work From Home Request",
      message: "${widget.employeeId} has requested to work from home today ($date).",
    );

    if (!mounted) return;
    setState(() => wfhStatusToday = "pending");
  }

  Future<void> punchIn() async {
    if (isSubmitting) return;
    if (status == "Checked In" || status == "Checked Out") {
      _showMessage(status == "Checked In" ? "You have already punched in today" : "You have already completed today's attendance");
      return;
    }

    final wfhApproved = wfhStatusToday == "approved";

    if (!wfhApproved && (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      _showMessage(
        currentLocation == null
            ? "Unable to verify your location. Please try again."
            : "You're ${distance}m away from the office. Move closer to check in.",
      );
      return;
    }

    setState(() => isSubmitting = true);

    final date = getDateKey();
    final time = TimeOfDay.now().format(context);
    final location = currentLocation;
    final dayRef = attendanceRef.child("Attendance").child(widget.employeeId).child(date);

    try {
      final result = await dayRef.runTransaction((Object? currentData) {
        final data = currentData == null ? <String, dynamic>{} : Map<String, dynamic>.from(currentData as Map);
        final currentStatus = data["status"] ?? "Not Checked In";

        if (currentStatus == "Checked In" || currentStatus == "Checked Out") {
          return Transaction.abort();
        }

        data["employeeId"] = widget.employeeId;
        data["date"] = date;
        data["punchIn"] = time;
        data["status"] = "Checked In";
        data["workFromHome"] = wfhApproved;

        if (wfhApproved) {
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
        await loadTodayAttendance();
        setState(() => isSubmitting = false);
        _showMessage("You have already punched in today");
        return;
      }

      setState(() {
        punchInTime = time;
        status = "Checked In";
        isWorkFromHome = wfhApproved;
        lastAddress = wfhApproved ? "Work From Home" : location?.address;
        lastLat = wfhApproved ? null : location?.latitude;
        lastLng = wfhApproved ? null : location?.longitude;
        isSubmitting = false;
      });

      _showMessage("Punch In Saved");
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      _showMessage("Error : $e");
    }
  }

  Future<void> punchOut() async {
    if (isSubmitting) return;
    if (status != "Checked In") {
      _showMessage(status == "Checked Out" ? "You have already punched out today" : "Please punch in first");
      return;
    }

    if (!isWorkFromHome && (currentLocation == null || !currentLocation!.isWithinOfficeRange)) {
      final distance = currentLocation?.distanceFromOffice.round() ?? 0;
      _showMessage(
        currentLocation == null
            ? "Unable to verify your location. Please try again."
            : "You're ${distance}m away from the office. Move closer to check out.",
      );
      return;
    }

    setState(() => isSubmitting = true);

    final date = getDateKey();
    final time = TimeOfDay.now().format(context);
    final location = currentLocation;
    final dayRef = attendanceRef.child("Attendance").child(widget.employeeId).child(date);

    try {
      final result = await dayRef.runTransaction((Object? currentData) {
        if (currentData == null) return Transaction.abort();
        final data = Map<String, dynamic>.from(currentData as Map);
        final currentStatus = data["status"] ?? "Not Checked In";
        if (currentStatus != "Checked In") return Transaction.abort();

        data["punchOut"] = time;
        data["status"] = "Checked Out";

        if (isWorkFromHome) {
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
        await loadTodayAttendance();
        setState(() => isSubmitting = false);
        _showMessage(status == "Checked Out" ? "You have already punched out today" : "Please punch in first");
        return;
      }

      setState(() {
        punchOutTime = time;
        status = "Checked Out";
        lastAddress = isWorkFromHome ? "Work From Home" : location?.address;
        lastLat = isWorkFromHome ? null : location?.latitude;
        lastLng = isWorkFromHome ? null : location?.longitude;
        _updateClassification();
        isSubmitting = false;
      });

      _showMessage("Punch Out Saved");
    } catch (e) {
      if (!mounted) return;
      setState(() => isSubmitting = false);
      _showMessage("Error : $e");
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Color _dayTypeColor() {
    switch (dayType) {
      case DayType.fullDay:
        return AppColors.success;
      case DayType.halfDay:
        return AppColors.warning;
      case DayType.absent:
        return AppColors.danger;
      default:
        return AppColors.textSecondary;
    }
  }

  Widget _wfhSection() {
  if (!widget.showWfhButton) {
    return const SizedBox.shrink();
  }

  if (status != "Not Checked In") {
    return const SizedBox.shrink();
  }

  if (wfhStatusToday == "approved") {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: AppColors.success.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.home_work, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text("Work From Home approved for today", style: TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      );
    }

    if (wfhStatusToday == "pending") {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: AppColors.warning.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.hourglass_top, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text("WFH request pending admin approval", style: TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      );
    }

    if (wfhStatusToday == "rejected") {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.25), borderRadius: BorderRadius.circular(12)),
        child: const Row(
          children: [
            Icon(Icons.block, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Expanded(child: Text("WFH request rejected \u2014 please punch in at office", style: TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _requestWfh,
          icon: const Icon(Icons.home_work_outlined, color: Colors.white70, size: 18),
          label: const Text("Request Work From Home", style: TextStyle(color: Colors.white70)),
        ),
      ),
    );
  }

  Widget _locationBanner() {
    switch (locationStatus) {
      case LocationStatus.loading:
        return _banner(icon: Icons.my_location, color: Colors.white54, text: "Checking your location...", showRetry: false);
      case LocationStatus.serviceDisabled:
        return _banner(icon: Icons.location_off, color: AppColors.danger, text: "Turn on location services to punch in/out.", showRetry: true);
      case LocationStatus.denied:
        return _banner(icon: Icons.location_off, color: AppColors.danger, text: "Location permission denied. Enable it in app settings.", showRetry: true);
      case LocationStatus.error:
        return _banner(icon: Icons.error_outline, color: AppColors.danger, text: "Couldn't get your location. Try again.", showRetry: true);
      case LocationStatus.granted:
        final inRange = currentLocation?.isWithinOfficeRange ?? false;
        final distance = currentLocation?.distanceFromOffice.round() ?? 0;
        return _banner(
          icon: inRange ? Icons.check_circle : Icons.location_on,
          color: inRange ? AppColors.success : AppColors.warning,
          text: inRange ? "You're at the office" : "${distance}m from office \u2014 move closer",
          showRetry: !inRange,
        );
    }
  }

  Widget _banner({required IconData icon, required Color color, required String text, required bool showRetry}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold))),
          if (showRetry)
            GestureDetector(
              onTap: _refreshLocation,
              child: Icon(Icons.refresh, color: color, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _actionButton() {
    final checkedIn = status == "Checked In";
    final done = status == "Checked Out";
    final wfhApproved = wfhStatusToday == "approved";
    final canAct = wfhApproved || (locationStatus == LocationStatus.granted && (currentLocation?.isWithinOfficeRange ?? false));

    return SizedBox(
      width: double.infinity,
      height: widget.compact ? 46 : 56,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: done
              ? Colors.white.withOpacity(0.25)
              : (!canAct ? Colors.white.withOpacity(0.2) : (checkedIn ? AppColors.danger : AppColors.success)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          elevation: 0,
        ),
        onPressed: (isLoading || isSubmitting || done || !canAct) ? null : (checkedIn ? punchOut : punchIn),
        child: isSubmitting
            ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(checkedIn ? Icons.logout : Icons.login, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    done ? "Completed" : (checkedIn ? "Check Out" : "Check In"),
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _mapPreview() {
    final centerLat = currentLocation?.latitude ?? lastLat ?? AppConstants.officeLat;
    final centerLng = currentLocation?.longitude ?? lastLng ?? AppConstants.officeLng;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 160,
        child: IgnorePointer(
          child: FlutterMap(
            options: MapOptions(initialCenter: LatLng(centerLat, centerLng), initialZoom: 16),
            children: [
              TileLayer(
                urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName: "com.example.punchin_app",
              ),
              CircleLayer(circles: [
                CircleMarker(
                  point: const LatLng(AppConstants.officeLat, AppConstants.officeLng),
                  radius: AppConstants.officeRadiusMeters,
                  useRadiusInMeter: true,
                  color: AppColors.primary.withOpacity(0.15),
                  borderColor: AppColors.primary,
                  borderStrokeWidth: 1.5,
                ),
              ]),
              MarkerLayer(markers: [
                Marker(
                  point: const LatLng(AppConstants.officeLat, AppConstants.officeLng),
                  width: 30,
                  height: 30,
                  child: const Icon(Icons.business, color: AppColors.primary, size: 26),
                ),
                if (currentLocation != null)
                  Marker(
                    point: LatLng(currentLocation!.latitude, currentLocation!.longitude),
                    width: 30,
                    height: 30,
                    child: Icon(
                      Icons.person_pin_circle,
                      color: currentLocation!.isWithinOfficeRange ? AppColors.success : AppColors.danger,
                      size: 30,
                    ),
                  ),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final wfhApproved = wfhStatusToday == "approved";

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppGradients.punchCard,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.hero,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Today's Attendance", style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                punchInTime == "--:--" ? "--:--" : (status == "Checked Out" ? punchOutTime : punchInTime),
                style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold),
              ),
              if (dayTypeLabel != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.2), borderRadius: BorderRadius.circular(20)),
                  child: Text(dayTypeLabel!, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                ),
            ],
          ),
          if (isWorkFromHome && status != "Not Checked In") ...[
            const SizedBox(height: 6),
            const Row(
              children: [
                Icon(Icons.home_work_outlined, size: 14, color: Colors.white70),
                SizedBox(width: 4),
                Text("Work From Home", style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ] else if (lastAddress != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.white70),
                const SizedBox(width: 4),
                Expanded(child: Text(lastAddress!, style: const TextStyle(color: Colors.white70, fontSize: 12), overflow: TextOverflow.ellipsis)),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _wfhSection(),
          if (!wfhApproved) _locationBanner(),
          if (!widget.compact && !wfhApproved) ...[
            const SizedBox(height: 12),
            _mapPreview(),
          ],
          const SizedBox(height: 14),
          _actionButton(),
          if (!widget.compact) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("Working Hours", style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Text(workingHours, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}