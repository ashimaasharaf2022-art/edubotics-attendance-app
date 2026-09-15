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
  State<PunchCard> createState() =>
      _PunchCardState();
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

  int outstandingMinutes = 0;

  DayType? dayType;
  String? dayTypeLabel;

  bool isLoading = true;
  bool isSubmitting = false;

  LocationStatus locationStatus =
      LocationStatus.loading;

  LocationResult? currentLocation;

  // All sessions for today.
  List<AttendanceSession> todaySessions = [];

  @override
  void initState() {
    super.initState();

    attendanceRef =
        FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _initData();
    _refreshLocation();
  }

  Future<void> _initData() async {
    await loadTodayAttendance();

    if (!mounted) return;

    setState(() {
      isLoading = false;
    });
  }

  Future<void> _refreshLocation() async {
    if (!mounted) return;

    setState(() {
      locationStatus =
          LocationStatus.loading;
    });

    final (status, result) =
        await LocationHelper.getCurrentLocation();

    if (!mounted) return;

    setState(() {
      locationStatus = status;
      currentLocation = result;
    });
  }

  String getDateKey() {
    final now = DateTime.now();

    return "${now.year}-"
        "${now.month.toString().padLeft(2, '0')}-"
        "${now.day.toString().padLeft(2, '0')}";
  }

  // ===========================================================================
  // SESSION EXTRACTION
  // ===========================================================================

  List<AttendanceSession> _sessionsFromData(
    Map data,
  ) {
    final sessions =
        <AttendanceSession>[];

    final rawSessions =
        data["sessions"];

    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is Map &&
            item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn:
                  item["punchIn"].toString(),
              punchOut:
                  item["punchOut"]?.toString(),
            ),
          );
        }
      }
    } else if (rawSessions is Map) {
      final entries =
          rawSessions.entries.toList()
            ..sort(
              (a, b) => a.key
                  .toString()
                  .compareTo(
                    b.key.toString(),
                  ),
            );

      for (final entry in entries) {
        final item = entry.value;

        if (item is Map &&
            item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn:
                  item["punchIn"].toString(),
              punchOut:
                  item["punchOut"]?.toString(),
            ),
          );
        }
      }
    }

    // ---------------------------------------------------------------
    // OLD SINGLE-SESSION DATA
    // ---------------------------------------------------------------
    //
    // Existing records that don't have sessions are converted
    // in memory so old attendance continues to work.
    // ---------------------------------------------------------------

    if (sessions.isEmpty &&
        data["punchIn"] != null) {
      sessions.add(
        AttendanceSession(
          punchIn:
              data["punchIn"].toString(),
          punchOut:
              data["punchOut"]?.toString(),
        ),
      );
    }

    return sessions;
  }

  // ===========================================================================
  // UPDATE UI FROM SESSIONS
  // ===========================================================================

  void _updateFromSessions(
    Map data,
  ) {
    todaySessions =
        _sessionsFromData(data);

    isWorkFromHome =
        data["workFromHome"] == true;

    if (todaySessions.isEmpty) {
      punchInTime = "--:--";
      punchOutTime = "--:--";

      status =
          data["status"]?.toString() ??
              "Not Checked In";

      dayType = null;
      dayTypeLabel = null;
      workingHours = "0 hr 0 min";

      return;
    }

    final firstSession =
        todaySessions.first;

    final lastSession =
        todaySessions.last;

    punchInTime =
        firstSession.punchIn;

    punchOutTime =
        lastSession.punchOut ??
            "--:--";

    final hasOpenSession =
        lastSession.punchOut == null ||
            lastSession.punchOut!
                .trim()
                .isEmpty;

    if (hasOpenSession) {
      status = "Checked In";

      dayType = null;
      dayTypeLabel = null;

      workingHours =
          _calculateCurrentWorkingHours();

      return;
    }

    status =
        data["status"]?.toString() ??
            "Checked Out";

    final misPunch =
        status.toUpperCase() ==
                "MIS-PUNCH" ||
            data["misPunch"] == true ||
            data["mis_punch"] == true;

    if (misPunch) {
      dayType = null;
      dayTypeLabel = "MIS-PUNCH";
      workingHours = "Pending checkout";
      return;
    }

    _updateClassification();
  }

  // ===========================================================================
  // ATTENDANCE CLASSIFICATION
  // ===========================================================================

  void _updateClassification() {
    if (todaySessions.isEmpty) {
      dayType = null;
      dayTypeLabel = null;
      workingHours = "0 hr 0 min";
      return;
    }

    final lastSession =
        todaySessions.last;

    // Current session is still open.
    if (lastSession.punchOut == null ||
        lastSession.punchOut!
            .trim()
            .isEmpty) {
      dayType = null;
      dayTypeLabel = null;
      workingHours =
          _calculateCurrentWorkingHours();
      return;
    }

    final result =
        AttendanceCalculator
            .calculateFromSessions(
      todaySessions,
      workFromHome:
          isWorkFromHome,
    );

    dayType =
        result.dayType;

    switch (result.dayType) {
      case DayType.fullDay:
        dayTypeLabel = "FULL DAY";
        break;

      case DayType.workPending:
        dayTypeLabel = "WORK-PENDING";
        break;

      case DayType.absent:
        dayTypeLabel = "ABSENT";
        break;
    }

    workingHours =
        AttendanceCalculator.formatHours(
      result.netHours,
    );
  }

  // ===========================================================================
  // CURRENT WORKING HOURS
  // ===========================================================================

  String _calculateCurrentWorkingHours() {
    if (todaySessions.isEmpty) {
      return "0 hr 0 min";
    }

    int totalMinutes = 0;

    for (final session in todaySessions) {
      final inMinutes =
          AttendanceCalculator.toMinutes(
        session.punchIn,
      );

      if (inMinutes == null) {
        continue;
      }

      int? outMinutes =
          AttendanceCalculator.toMinutes(
        session.punchOut,
      );

      // The current open session runs until now.
      outMinutes ??=
          TimeOfDay.now().hour * 60 +
              TimeOfDay.now().minute;

      if (outMinutes >= inMinutes) {
        totalMinutes +=
            outMinutes - inMinutes;
      }
    }

    // Credit lunch if the employee's attended
    // period spans the lunch interval.
    final firstIn =
        AttendanceCalculator.toMinutes(
      todaySessions.first.punchIn,
    );

    if (firstIn != null) {
      int? lastOut;

      for (final session in todaySessions) {
        final out =
            AttendanceCalculator.toMinutes(
          session.punchOut,
        );

        if (out != null) {
          if (lastOut == null ||
              out > lastOut) {
            lastOut = out;
          }
        }
      }

      lastOut ??=
          TimeOfDay.now().hour * 60 +
              TimeOfDay.now().minute;

      if (firstIn <
              AttendanceCalculator.lunchEnd &&
          lastOut >
              AttendanceCalculator.lunchStart) {
        final lunchStart =
            AttendanceCalculator.lunchStart >
                    firstIn
                ? AttendanceCalculator
                    .lunchStart
                : firstIn;

        final lunchEnd =
            AttendanceCalculator.lunchEnd <
                    lastOut
                ? AttendanceCalculator
                    .lunchEnd
                : lastOut;

        if (lunchEnd > lunchStart) {
          int lunchCovered = 0;

          for (final session
              in todaySessions) {
            final sessionIn =
                AttendanceCalculator
                    .toMinutes(
              session.punchIn,
            );

            final sessionOut =
                AttendanceCalculator
                    .toMinutes(
                  session.punchOut,
                ) ??
                (session ==
                        todaySessions.last
                    ? TimeOfDay.now().hour *
                            60 +
                        TimeOfDay.now().minute
                    : null);

            if (sessionIn == null ||
                sessionOut == null) {
              continue;
            }

            final overlapStart =
                sessionIn > lunchStart
                    ? sessionIn
                    : lunchStart;

            final overlapEnd =
                sessionOut < lunchEnd
                    ? sessionOut
                    : lunchEnd;

            if (overlapEnd >
                overlapStart) {
              lunchCovered +=
                  overlapEnd -
                      overlapStart;
            }
          }

          final lunchWindow =
              lunchEnd - lunchStart;

          final missingLunch =
              lunchWindow -
                  lunchCovered;

          if (missingLunch > 0) {
            totalMinutes +=
                missingLunch;
          }
        }
      }
    }

    return AttendanceCalculator
        .formatHours(
      totalMinutes / 60,
    );
  }

  // ===========================================================================
  // LOAD TODAY
  // ===========================================================================

  Future<void> loadTodayAttendance() async {
    try {
      final date =
          getDateKey();

      final snapshot =
          await attendanceRef
              .child("Attendance")
              .child(widget.employeeId)
              .child(date)
              .get();

      if (!mounted) return;

      if (snapshot.exists &&
          snapshot.value is Map) {
        final data =
            Map<dynamic, dynamic>.from(
          snapshot.value as Map,
        );

        setState(() {
          _updateFromSessions(data);

          lastAddress =
              data["punchOutAddress"]
                      ?.toString() ??
                  data["punchInAddress"]
                      ?.toString();

          lastLat =
              double.tryParse(
            (data["punchOutLat"] ??
                    data["punchInLat"] ??
                    "")
                .toString(),
          );

          lastLng =
              double.tryParse(
            (data["punchOutLng"] ??
                    data["punchInLng"] ??
                    "")
                .toString(),
          );
        });
      } else {
        if (!mounted) return;

        setState(() {
          todaySessions = [];
          punchInTime = "--:--";
          punchOutTime = "--:--";
          status = "Not Checked In";
          workingHours = "0 hr 0 min";
          dayType = null;
          dayTypeLabel = null;
          lastAddress = null;
          lastLat = null;
          lastLng = null;
        });
      }

      // -----------------------------------------------------------------------
      // WFH STATUS
      // -----------------------------------------------------------------------

      final wfhSnap =
          await attendanceRef
              .child("WorkFromHomeRequests")
              .child(widget.employeeId)
              .child(date)
              .get();

      if (wfhSnap.exists &&
          wfhSnap.value is Map) {
        final wfhData =
            Map<dynamic, dynamic>.from(
          wfhSnap.value as Map,
        );

        if (!mounted) return;

        setState(() {
          wfhStatusToday =
              wfhData["status"]
                  ?.toString();
        });
      }

      // -----------------------------------------------------------------------
      // OUTSTANDING BALANCE
      // -----------------------------------------------------------------------

      final balanceSnap =
          await attendanceRef
              .child("AttendanceSummary")
              .child(widget.employeeId)
              .child("outstandingMinutes")
              .get();

      if (balanceSnap.exists &&
          mounted) {
        setState(() {
          outstandingMinutes =
              int.tryParse(
                    balanceSnap.value
                        .toString(),
                  ) ??
                  0;
        });
      }
    } catch (e) {
      debugPrint(
        "loadTodayAttendance error: $e",
      );
    }
  }

  // ===========================================================================
  // WFH REQUEST
  // ===========================================================================

  Future<void> _requestWfh() async {
    final date =
        getDateKey();

    try {
      final existingSnap =
          await attendanceRef
              .child(
                "WorkFromHomeRequests",
              )
              .child(widget.employeeId)
              .child(date)
              .get();

      if (existingSnap.exists &&
          existingSnap.value is Map) {
        final data =
            Map<dynamic, dynamic>.from(
          existingSnap.value as Map,
        );

        if (!mounted) return;

        setState(() {
          wfhStatusToday =
              data["status"]?.toString();
        });

        return;
      }

      await attendanceRef
          .child("WorkFromHomeRequests")
          .child(widget.employeeId)
          .child(date)
          .set({
        "employeeId":
            widget.employeeId,
        "status":
            "pending",
        "requestedAt":
            DateTime.now()
                .toIso8601String(),
      });

      await EmailAlertHelper.sendAlert(
        subject:
            "Work From Home Request",
        message:
            "${widget.employeeId} has requested to work from home today ($date).",
        templateId:
            EmailAlertHelper
                .templateLeaveRequest,
      );

      if (!mounted) return;

      setState(() {
        wfhStatusToday =
            "pending";
      });
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        "Unable to submit WFH request: $e",
      );
    }
  }

  // ===========================================================================
  // PUNCH IN
  // ===========================================================================

  Future<void> punchIn() async {
    if (isSubmitting) return;

    // ---------------------------------------------------------------
    // IMPORTANT:
    //
    // We only block if there is an OPEN session.
    //
    // A completed session does NOT prevent another punch-in.
    // ---------------------------------------------------------------

    if (todaySessions.isNotEmpty) {
      final last =
          todaySessions.last;

      if (last.punchOut == null ||
          last.punchOut!
              .trim()
              .isEmpty) {
        _showMessage(
          "You are already punched in. Please punch out first.",
        );
        return;
      }
    }

    final wfhApproved =
        wfhStatusToday ==
            "approved";

    // ---------------------------------------------------------------
    // LOCATION
    // ---------------------------------------------------------------

    if (currentLocation == null ||
        locationStatus !=
            LocationStatus.granted) {
      await _refreshLocation();

      if (!mounted) return;

      if (currentLocation == null ||
          locationStatus !=
              LocationStatus.granted) {
        _showMessage(
          "Unable to get your current location. Please enable location permission and try again.",
        );
        return;
      }
    }

    setState(() {
      isSubmitting = true;
    });

    final date =
        getDateKey();

    final time =
        TimeOfDay.now()
            .format(context);

    final location =
        currentLocation;

    final dayRef =
        attendanceRef
            .child("Attendance")
            .child(widget.employeeId)
            .child(date);

    try {
      final result =
          await dayRef.runTransaction(
        (Object? currentData) {
          final data =
              currentData == null
                  ? <String, dynamic>{}
                  : Map<String, dynamic>.from(
                      currentData as Map,
                    );

          // ---------------------------------------------------------
          // EXISTING SESSIONS
          // ---------------------------------------------------------

          final sessions =
              <dynamic>[];

          final rawSessions =
              data["sessions"];

          if (rawSessions is List) {
            sessions.addAll(
              rawSessions,
            );
          } else if (rawSessions is Map) {
            final entries =
                rawSessions.entries.toList()
                  ..sort(
                    (a, b) => a.key
                        .toString()
                        .compareTo(
                          b.key.toString(),
                        ),
                  );

            for (final entry
                in entries) {
              sessions.add(
                entry.value,
              );
            }
          } else if (data["punchIn"] !=
              null) {
            // Convert old single-session
            // record into session format.
            sessions.add({
              "punchIn":
                  data["punchIn"],
              "punchOut":
                  data["punchOut"],
            });
          }

          // ---------------------------------------------------------
          // PREVENT OPEN SESSION
          // ---------------------------------------------------------

          if (sessions.isNotEmpty) {
            final last =
                sessions.last;

            if (last is Map) {
              final lastPunchOut =
                  last["punchOut"]
                      ?.toString();

              if (lastPunchOut ==
                      null ||
                  lastPunchOut
                      .trim()
                      .isEmpty) {
                return Transaction.abort();
              }
            }
          }

          // ---------------------------------------------------------
          // CREATE NEW SESSION
          // ---------------------------------------------------------

          sessions.add({
            "punchIn": time,
            "punchOut": null,
            "punchInLat":
                location?.latitude,
            "punchInLng":
                location?.longitude,
            "punchInAddress":
                location == null
                    ? null
                    : (wfhApproved
                        ? "Work From Home — ${location.address}"
                        : location.address),
          });

          data["employeeId"] =
              widget.employeeId;

          data["date"] =
              date;

          // ---------------------------------------------------------
          // TOP-LEVEL COMPATIBILITY FIELDS
          // ---------------------------------------------------------

          data["punchIn"] =
              sessions.first["punchIn"];

          data["punchOut"] =
              null;

          data["status"] =
              "Checked In";

          // Keep WFH if already true,
          // or use today's approved WFH.
          data["workFromHome"] =
              data["workFromHome"] == true ||
                  wfhApproved;

          // ---------------------------------------------------------
          // SAVE ALL SESSIONS
          // ---------------------------------------------------------

          data["sessions"] =
              sessions;

          // ---------------------------------------------------------
          // CURRENT PUNCH-IN LOCATION
          // ---------------------------------------------------------

          if (location != null) {
            data["punchInLat"] =
                location.latitude;

            data["punchInLng"] =
                location.longitude;

            data["punchInAddress"] =
                wfhApproved
                    ? "Work From Home — ${location.address}"
                    : location.address;
          }

          // ---------------------------------------------------------
          // CLEAR TEMPORARY MIS-PUNCH FIELDS
          // ---------------------------------------------------------

          data["misPunch"] = null;
          data["mis_punch"] = null;
          data["temporaryPunchOut"] =
              null;
          data["misPunchDetectedAt"] =
              null;

          data["autoPunchOut"] = null;
          data["autoCheckedOutAt"] =
              null;
          data["approvedAutoCheckout"] =
              null;

          data["punchoutRequestStatus"] =
              null;

          data["attendanceStatus"] =
              "Checked In";

          return Transaction.success(
            data,
          );
        },
      );

      if (!mounted) return;

      if (!result.committed) {
        await loadTodayAttendance();

        if (!mounted) return;

        setState(() {
          isSubmitting = false;
        });

        _showMessage(
          "You are already punched in. Please punch out first.",
        );

        return;
      }

      setState(() {
        todaySessions.add(
          AttendanceSession(
            punchIn: time,
            punchOut: null,
          ),
        );

        punchInTime =
            todaySessions.first
                .punchIn;

        punchOutTime =
            "--:--";

        status =
            "Checked In";

        isWorkFromHome =
            isWorkFromHome ||
                wfhApproved;

        lastAddress =
            location?.address;

        lastLat =
            location?.latitude;

        lastLng =
            location?.longitude;

        dayType = null;
        dayTypeLabel = null;

        workingHours =
            _calculateCurrentWorkingHours();

        isSubmitting = false;
      });

      _showMessage(
        "Punch In Saved",
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      _showMessage(
        "Error : $e",
      );
    }
  }

  // ===========================================================================
  // PUNCH OUT
  // ===========================================================================

  Future<void> punchOut() async {
    if (isSubmitting) return;

    // ---------------------------------------------------------------
    // Must have an open session.
    // ---------------------------------------------------------------

    if (todaySessions.isEmpty) {
      _showMessage(
        "Please punch in first",
      );
      return;
    }

    final lastSession =
        todaySessions.last;

    if (lastSession.punchOut != null &&
        lastSession.punchOut!
            .trim()
            .isNotEmpty) {
      _showMessage(
        "Please punch in before punching out again.",
      );
      return;
    }

    // ---------------------------------------------------------------
    // LOCATION
    // ---------------------------------------------------------------

    if (currentLocation == null ||
        locationStatus !=
            LocationStatus.granted) {
      await _refreshLocation();

      if (!mounted) return;

      if (currentLocation == null ||
          locationStatus !=
              LocationStatus.granted) {
        _showMessage(
          "Unable to get your current location. Please enable location permission and try again.",
        );
        return;
      }
    }

    setState(() {
      isSubmitting = true;
    });

    final date =
        getDateKey();

    final time =
        TimeOfDay.now()
            .format(context);

    final location =
        currentLocation;

    final dayRef =
        attendanceRef
            .child("Attendance")
            .child(widget.employeeId)
            .child(date);

    AttendanceResult? finalAttendance;

    try {
      final result =
          await dayRef.runTransaction(
        (Object? currentData) {
          if (currentData == null) {
            return Transaction.abort();
          }

          final data =
              Map<String, dynamic>.from(
            currentData as Map,
          );

          // ---------------------------------------------------------
          // READ EXISTING SESSIONS
          // ---------------------------------------------------------

          final sessions =
              <Map<String, dynamic>>[];

          final rawSessions =
              data["sessions"];

          if (rawSessions is List) {
            for (final item
                in rawSessions) {
              if (item is Map) {
                sessions.add(
                  Map<String, dynamic>.from(
                    item,
                  ),
                );
              }
            }
          } else if (rawSessions is Map) {
            final entries =
                rawSessions.entries.toList()
                  ..sort(
                    (a, b) => a.key
                        .toString()
                        .compareTo(
                          b.key.toString(),
                        ),
                  );

            for (final entry
                in entries) {
              if (entry.value
                  is Map) {
                sessions.add(
                  Map<String, dynamic>.from(
                    entry.value as Map,
                  ),
                );
              }
            }
          } else if (data["punchIn"] !=
              null) {
            sessions.add({
              "punchIn":
                  data["punchIn"],
              "punchOut":
                  data["punchOut"],
            });
          }

          if (sessions.isEmpty) {
            return Transaction.abort();
          }

          // ---------------------------------------------------------
          // FIND LAST OPEN SESSION
          // ---------------------------------------------------------

          int openIndex = -1;

          for (int i = 0;
              i < sessions.length;
              i++) {
            final session =
                sessions[i];

            final sessionOut =
                session["punchOut"]
                    ?.toString();

            if (sessionOut == null ||
                sessionOut
                    .trim()
                    .isEmpty) {
              openIndex = i;
            }
          }

          if (openIndex == -1) {
            return Transaction.abort();
          }

          // ---------------------------------------------------------
          // SAVE REAL PUNCH-OUT
          // ---------------------------------------------------------

          final openSession =
              sessions[openIndex];

          openSession["punchOut"] =
              time;

          if (location != null) {
            openSession["punchOutLat"] =
                location.latitude;

            openSession["punchOutLng"] =
                location.longitude;

            openSession["punchOutAddress"] =
                data["workFromHome"] ==
                        true
                    ? "Work From Home — ${location.address}"
                    : location.address;
          }

          // ---------------------------------------------------------
          // CALCULATE ENTIRE DAY
          // ---------------------------------------------------------

          final calculationSessions =
              sessions.map(
            (session) {
              return AttendanceSession(
                punchIn:
                    session["punchIn"]
                        .toString(),
                punchOut:
                    session["punchOut"]
                        ?.toString(),
              );
            },
          ).toList();

          final attendance =
              AttendanceCalculator
                  .calculateFromSessions(
            calculationSessions,
            workFromHome:
                data["workFromHome"] ==
                    true,
          );

          finalAttendance =
              attendance;

          // ---------------------------------------------------------
          // TOP-LEVEL FIELDS
          // ---------------------------------------------------------

          data["punchIn"] =
              sessions.first["punchIn"];

          data["punchOut"] =
              sessions.last["punchOut"];

          data["status"] =
              "Checked Out";

          data["sessions"] =
              sessions;

          // ---------------------------------------------------------
          // CLASSIFICATION
          // ---------------------------------------------------------

          switch (attendance.dayType) {
            case DayType.fullDay:
              data["attendanceStatus"] =
                  "FULL DAY";
              break;

            case DayType.workPending:
              data["attendanceStatus"] =
                  "WORK-PENDING";
              break;

            case DayType.absent:
              data["attendanceStatus"] =
                  "ABSENT";
              break;
          }

          data["netWorkMinutes"] =
              (attendance.netHours *
                      60)
                  .round();

          data["shortfallMinutes"] =
              (attendance
                          .shortfallHours *
                      60)
                  .round();

          data["extraWorkMinutes"] =
              (attendance
                          .extraHours *
                      60)
                  .round();

          // ---------------------------------------------------------
          // TOP-LEVEL CHECKOUT LOCATION
          // ---------------------------------------------------------

          if (location != null) {
            data["punchOutLat"] =
                location.latitude;

            data["punchOutLng"] =
                location.longitude;

            data["punchOutAddress"] =
                data["workFromHome"] ==
                        true
                    ? "Work From Home — ${location.address}"
                    : location.address;
          }

          // ---------------------------------------------------------
          // REMOVE TEMPORARY STATES
          // ---------------------------------------------------------

          data["autoPunchOut"] = null;
          data["autoCheckedOutAt"] =
              null;
          data["approvedAutoCheckout"] =
              null;

          data["temporaryPunchOut"] =
              null;

          data["misPunch"] = null;
          data["mis_punch"] = null;

          data["misPunchDetectedAt"] =
              null;

          data["punchoutRequestStatus"] =
              null;

          return Transaction.success(
            data,
          );
        },
      );

      if (!mounted) return;

      if (!result.committed) {
        await loadTodayAttendance();

        if (!mounted) return;

        setState(() {
          isSubmitting = false;
        });

        _showMessage(
          "Unable to punch out. Please make sure you are currently punched in.",
        );

        return;
      }

      final attendance =
          finalAttendance ??
              AttendanceCalculator
                  .calculateFromSessions(
            [
              ...todaySessions,
              AttendanceSession(
                punchIn:
                    todaySessions
                        .last
                        .punchIn,
                punchOut: time,
              ),
            ],
            workFromHome:
                isWorkFromHome,
          );

      // Reload from Firebase so the local session
      // state exactly matches the database.
      await loadTodayAttendance();

      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      // ---------------------------------------------------------------
      // COMPENSATION
      // ---------------------------------------------------------------

      await _updateCompensationBalance(
        date,
      );

      if (!mounted) return;

      if (attendance.dayType ==
          DayType.fullDay) {
        _showMessage(
          "Punch Out Saved — FULL DAY",
        );
      } else if (attendance.dayType ==
          DayType.workPending) {
        _showMessage(
          "Punch Out Saved — WORK-PENDING. "
          "${AttendanceCalculator.formatHours(attendance.shortfallHours)} "
          "remains to be compensated.",
        );
      } else {
        _showMessage(
          "Punch Out Saved",
        );
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isSubmitting = false;
      });

      _showMessage(
        "Error : $e",
      );
    }
  }

  // ===========================================================================
  // COMPENSATION
  // ===========================================================================

  Future<void> _updateCompensationBalance(
    String currentDate,
  ) async {
    try {
      final snapshot =
          await attendanceRef
              .child("Attendance")
              .child(widget.employeeId)
              .get();

      if (!snapshot.exists ||
          snapshot.value is! Map) {
        return;
      }

      final records =
          Map<dynamic, dynamic>.from(
        snapshot.value as Map,
      );

      final pendingDays =
          <_PendingCompensationDay>[];

      final extraMinutesPool =
          <_ExtraCompensationDay>[];

      for (final entry
          in records.entries) {
        final dateKey =
            entry.key.toString();

        if (entry.value is! Map) {
          continue;
        }

        final record =
            Map<dynamic, dynamic>.from(
          entry.value as Map,
        );

        final status =
            record["status"]
                ?.toString()
                .toUpperCase();

        // Temporary MIS-PUNCH is excluded.
        if (status == "MIS-PUNCH" ||
            record["misPunch"] == true ||
            record["mis_punch"] == true) {
          continue;
        }

        final sessions =
            _sessionsFromData(record);

        if (sessions.isEmpty) {
          continue;
        }

        // Any open session means this day is
        // not ready for compensation.
        final hasOpenSession =
            sessions.any(
          (session) =>
              session.punchOut ==
                  null ||
              session.punchOut!
                  .trim()
                  .isEmpty,
        );

        if (hasOpenSession) {
          continue;
        }

        final result =
            AttendanceCalculator
                .calculateFromSessions(
          sessions,
          workFromHome:
              record["workFromHome"] ==
                  true,
        );

        final shortfallMinutes =
            (result.shortfallHours *
                    60)
                .round();

        final extraMinutes =
            (result.extraHours *
                    60)
                .round();

        if (shortfallMinutes > 0) {
          pendingDays.add(
            _PendingCompensationDay(
              date: dateKey,
              deficitMinutes:
                  shortfallMinutes,
            ),
          );
        }

        if (extraMinutes > 0) {
          extraMinutesPool.add(
            _ExtraCompensationDay(
              date: dateKey,
              extraMinutes:
                  extraMinutes,
            ),
          );
        }
      }

      // ---------------------------------------------------------------
      // LEAST DEFICIT FIRST
      // ---------------------------------------------------------------

      pendingDays.sort(
        (a, b) =>
            a.deficitMinutes
                .compareTo(
              b.deficitMinutes,
            ),
      );

      var totalOutstanding = 0;

      for (final pending
          in pendingDays) {
        var remaining =
            pending.deficitMinutes;

        for (final extra
            in extraMinutesPool) {
          if (remaining <= 0) {
            break;
          }

          if (extra.extraMinutes <= 0) {
            continue;
          }

          final applied =
              remaining <
                      extra.extraMinutes
                  ? remaining
                  : extra.extraMinutes;

          remaining -=
              applied;

          extra.extraMinutes -=
              applied;
        }

        pending.remainingMinutes =
            remaining;

        totalOutstanding +=
            remaining;
      }

      // ---------------------------------------------------------------
      // SAVE GLOBAL BALANCE
      // ---------------------------------------------------------------

      await attendanceRef
          .child("AttendanceSummary")
          .child(widget.employeeId)
          .update({
        "outstandingMinutes":
            totalOutstanding,
        "updatedAt":
            DateTime.now()
                .toIso8601String(),
      });

      // ---------------------------------------------------------------
      // SAVE CURRENT-DAY BALANCE
      // ---------------------------------------------------------------

      await attendanceRef
          .child("Attendance")
          .child(widget.employeeId)
          .child(currentDate)
          .update({
        "outstandingBalanceMinutes":
            totalOutstanding,
      });

      if (!mounted) return;

      setState(() {
        outstandingMinutes =
            totalOutstanding;
      });
    } catch (e) {
      debugPrint(
        "_updateCompensationBalance error: $e",
      );
    }
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
        .showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ===========================================================================
  // DAY TYPE COLOR
  // ===========================================================================

  Color _dayTypeColor() {
    switch (dayType) {
      case DayType.fullDay:
        return AppColors.success;

      case DayType.workPending:
        return AppColors.warning;

      case DayType.absent:
        return AppColors.danger;

      default:
        return AppColors.textSecondary;
    }
  }

  // ===========================================================================
  // WFH SECTION
  // ===========================================================================

  Widget _wfhSection() {
    if (!widget.showWfhButton) {
      return const SizedBox.shrink();
    }

    if (status !=
        "Not Checked In") {
      return const SizedBox.shrink();
    }

    if (wfhStatusToday ==
        "approved") {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),
        decoration:
            BoxDecoration(
          color: AppColors.success
              .withOpacity(0.25),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.home_work,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "Work From Home approved for today",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (wfhStatusToday ==
        "pending") {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),
        decoration:
            BoxDecoration(
          color: AppColors.warning
              .withOpacity(0.25),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.hourglass_top,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "WFH request pending admin approval",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (wfhStatusToday ==
        "rejected") {
      return Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        margin:
            const EdgeInsets.only(
          bottom: 10,
        ),
        decoration:
            BoxDecoration(
          color: AppColors.danger
              .withOpacity(0.25),
          borderRadius:
              BorderRadius.circular(12),
        ),
        child: const Row(
          children: [
            Icon(
              Icons.block,
              color: Colors.white,
              size: 18,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                "WFH request rejected — please punch in at office",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 10,
      ),
      child: Align(
        alignment:
            Alignment.centerLeft,
        child: TextButton.icon(
          onPressed:
              _requestWfh,
          icon: const Icon(
            Icons.home_work_outlined,
            color: Colors.white70,
            size: 18,
          ),
          label: const Text(
            "Request Work From Home",
            style: TextStyle(
              color: Colors.white70,
            ),
          ),
        ),
      ),
    );
  }

  // ===========================================================================
  // LOCATION BANNER
  // ===========================================================================

  Widget _locationBanner() {
    switch (locationStatus) {
      case LocationStatus.loading:
        return _banner(
          icon:
              Icons.my_location,
          color:
              Colors.white54,
          text:
              "Checking your location...",
          showRetry: false,
        );

      case LocationStatus.serviceDisabled:
        return _banner(
          icon:
              Icons.location_off,
          color:
              AppColors.danger,
          text:
              "Turn on location services to punch in/out.",
          showRetry: true,
        );

      case LocationStatus.denied:
        return _banner(
          icon:
              Icons.location_off,
          color:
              AppColors.danger,
          text:
              "Location permission denied. Enable it in app settings.",
          showRetry: true,
        );

      case LocationStatus.error:
        return _banner(
          icon:
              Icons.error_outline,
          color:
              AppColors.danger,
          text:
              "Couldn't get your location. Try again.",
          showRetry: true,
        );

      case LocationStatus.mockDetected:
        return _banner(
          icon:
              Icons.security,
          color:
              AppColors.danger,
          text:
              "Mock location detected. Disable mock location apps to punch.",
          showRetry: true,
        );

      case LocationStatus.granted:
        final distance =
            currentLocation
                    ?.distanceFromOffice
                    .round() ??
                0;

        return _banner(
          icon:
              Icons.location_on,
          color:
              AppColors.success,
          text:
              "Location recorded • ${distance}m from office",
          showRetry: true,
        );
    }
  }

  Widget _banner({
    required IconData icon,
    required Color color,
    required String text,
    required bool showRetry,
  }) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 10,
      ),
      decoration:
          BoxDecoration(
        color:
            color.withOpacity(0.15),
        borderRadius:
            BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight:
                    FontWeight.bold,
              ),
            ),
          ),
          if (showRetry)
            GestureDetector(
              onTap:
                  _refreshLocation,
              child: Icon(
                Icons.refresh,
                color: color,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  // ===========================================================================
  // ACTION BUTTON
  // ===========================================================================

  Widget _actionButton() {
    final checkedIn =
        status == "Checked In";

    final canPunch =
        locationStatus ==
                LocationStatus.granted &&
            currentLocation != null;

    final canAct =
        !isSubmitting &&
        canPunch;

    return SizedBox(
      width: double.infinity,
      height:
          widget.compact
              ? 46
              : 56,
      child:
          ElevatedButton(
        style:
            ElevatedButton.styleFrom(
          backgroundColor:
              !canAct
                  ? Colors.white
                      .withOpacity(
                    0.2,
                  )
                  : (checkedIn
                      ? AppColors.danger
                      : AppColors.success),
          shape:
              RoundedRectangleBorder(
            borderRadius:
                BorderRadius.circular(
              30,
            ),
          ),
          elevation: 0,
        ),
        onPressed:
            (isLoading ||
                    isSubmitting ||
                    !canAct)
                ? null
                : (checkedIn
                    ? punchOut
                    : punchIn),
        child:
            isSubmitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child:
                        CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          Colors.white,
                    ),
                  )
                : Row(
                    mainAxisAlignment:
                        MainAxisAlignment
                            .center,
                    children: [
                      Icon(
                        checkedIn
                            ? Icons.logout
                            : Icons.login,
                        color:
                            Colors.white,
                        size: 18,
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      Text(
                        checkedIn
                            ? "Check Out"
                            : "Check In",
                        style:
                            const TextStyle(
                          color:
                              Colors.white,
                          fontWeight:
                              FontWeight
                                  .bold,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }

  // ===========================================================================
  // MAP
  // ===========================================================================

  Widget _mapPreview() {
    final centerLat =
        currentLocation
                ?.latitude ??
            lastLat ??
            AppConstants.officeLat;

    final centerLng =
        currentLocation
                ?.longitude ??
            lastLng ??
            AppConstants.officeLng;

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(14),
      child: SizedBox(
        height: 160,
        child: IgnorePointer(
          child: FlutterMap(
            options:
                MapOptions(
              initialCenter:
                  LatLng(
                centerLat,
                centerLng,
              ),
              initialZoom: 16,
            ),
            children: [
              TileLayer(
                urlTemplate:
                    "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
                userAgentPackageName:
                    "com.example.punchin_app",
              ),
              CircleLayer(
                circles: [
                  CircleMarker(
                    point:
                        const LatLng(
                      AppConstants
                          .officeLat,
                      AppConstants
                          .officeLng,
                    ),
                    radius:
                        AppConstants
                            .officeRadiusMeters,
                    useRadiusInMeter:
                        true,
                    color:
                        AppColors
                            .primary
                            .withOpacity(
                      0.15,
                    ),
                    borderColor:
                        AppColors
                            .primary,
                    borderStrokeWidth:
                        1.5,
                  ),
                ],
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point:
                        const LatLng(
                      AppConstants
                          .officeLat,
                      AppConstants
                          .officeLng,
                    ),
                    width: 30,
                    height: 30,
                    child:
                        const Icon(
                      Icons.business,
                      color:
                          AppColors
                              .primary,
                      size: 26,
                    ),
                  ),
                  if (currentLocation !=
                      null)
                    Marker(
                      point:
                          LatLng(
                        currentLocation!
                            .latitude,
                        currentLocation!
                            .longitude,
                      ),
                      width: 30,
                      height: 30,
                      child:
                          const Icon(
                        Icons
                            .person_pin_circle,
                        color:
                            AppColors
                                .success,
                        size: 30,
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

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final wfhApproved =
        wfhStatusToday ==
            "approved";

    return Container(
      padding:
          const EdgeInsets.all(18),
      decoration:
          BoxDecoration(
        gradient:
            AppGradients.punchCard,
        borderRadius:
            BorderRadius.circular(
          20,
        ),
        boxShadow:
            AppShadows.hero,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            "Today's Attendance",
            style:
                TextStyle(
              color:
                  Colors.white70,
              fontSize: 13,
            ),
          ),

          const SizedBox(
            height: 6,
          ),

          Row(
            mainAxisAlignment:
                MainAxisAlignment
                    .spaceBetween,
            children: [
              Text(
                punchInTime ==
                        "--:--"
                    ? "--:--"
                    : (status ==
                            "Checked Out"
                        ? punchOutTime
                        : punchInTime),
                style:
                    const TextStyle(
                  color:
                      Colors.white,
                  fontSize: 30,
                  fontWeight:
                      FontWeight.bold,
                ),
              ),

              if (dayTypeLabel !=
                  null)
                Container(
                  padding:
                      const EdgeInsets
                          .symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration:
                      BoxDecoration(
                    color:
                        _dayTypeColor()
                            .withOpacity(
                      0.25,
                    ),
                    borderRadius:
                        BorderRadius
                            .circular(
                      20,
                    ),
                  ),
                  child:
                      Text(
                    dayTypeLabel!,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight
                              .bold,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),

          if (isWorkFromHome &&
              status !=
                  "Not Checked In") ...[
            const SizedBox(
              height: 6,
            ),
            const Row(
              children: [
                Icon(
                  Icons
                      .home_work_outlined,
                  size: 14,
                  color:
                      Colors.white70,
                ),
                SizedBox(
                  width: 4,
                ),
                Text(
                  "Work From Home",
                  style:
                      TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ] else if (lastAddress !=
              null) ...[
            const SizedBox(
              height: 6,
            ),
            Row(
              children: [
                const Icon(
                  Icons.location_on,
                  size: 14,
                  color:
                      Colors.white70,
                ),
                const SizedBox(
                  width: 4,
                ),
                Expanded(
                  child:
                      Text(
                    lastAddress!,
                    style:
                        const TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 12,
                    ),
                    overflow:
                        TextOverflow
                            .ellipsis,
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(
            height: 12,
          ),

          _wfhSection(),

          if (!wfhApproved)
            _locationBanner(),

          if (!widget.compact &&
              !wfhApproved) ...[
            const SizedBox(
              height: 12,
            ),
            _mapPreview(),
          ],

          const SizedBox(
            height: 14,
          ),

          _actionButton(),

          if (!widget.compact) ...[
            const SizedBox(
              height: 14,
            ),

            Container(
              padding:
                  const EdgeInsets
                      .symmetric(
                vertical: 12,
                horizontal: 16,
              ),
              decoration:
                  BoxDecoration(
                color: Colors.white
                    .withOpacity(
                  0.15,
                ),
                borderRadius:
                    BorderRadius.circular(
                  14,
                ),
              ),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment
                        .spaceBetween,
                children: [
                  const Text(
                    "Working Hours",
                    style:
                        TextStyle(
                      color:
                          Colors.white70,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    workingHours,
                    style:
                        const TextStyle(
                      color:
                          Colors.white,
                      fontWeight:
                          FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),

            if (outstandingMinutes >
                0) ...[
              const SizedBox(
                height: 8,
              ),
              Text(
                "Time to compensate: "
                "${AttendanceCalculator.formatHours(outstandingMinutes / 60)}",
                style:
                    const TextStyle(
                  color:
                      Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// COMPENSATION CLASSES
// =============================================================================

class _PendingCompensationDay {
  final String date;
  final int deficitMinutes;

  int remainingMinutes;

  _PendingCompensationDay({
    required this.date,
    required this.deficitMinutes,
  }) : remainingMinutes =
            deficitMinutes;
}

class _ExtraCompensationDay {
  final String date;

  int extraMinutes;

  _ExtraCompensationDay({
    required this.date,
    required this.extraMinutes,
  });
}