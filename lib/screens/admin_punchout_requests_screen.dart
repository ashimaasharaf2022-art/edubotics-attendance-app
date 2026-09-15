import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Admin / Super Admin screen for correcting employee MIS-PUNCH records.
///
/// Workflow:
///
/// Employee:
///   Punch In
///      ↓
///   Forgets Punch Out
///      ↓
///   Next day → MIS-PUNCH
///      ↓
///   Employee opens History
///      ↓
///   Send request to admin
///
/// Admin:
///   Punchout Requests
///      ↓
///   Select actual punch-out time
///      ↓
///   Attendance is recalculated
///      ↓
///   MIS-PUNCH temporary fields are removed
///      ↓
///   Record becomes normal attendance
///
/// Important:
/// - No Firebase Scheduled Functions are used.
/// - temporaryPunchOut is NEVER used as the real punch-out.
/// - No punch-out location is invented.
/// - Existing session-specific locations are preserved.
/// - Multiple sessions are supported.
/// - Final classification is only FULL DAY / WORK-PENDING / ABSENT.
/// - 9 hours is required.
/// - Lunch 1 PM–2 PM counts as working time through AttendanceCalculator.
class AdminPunchoutRequestsScreen extends StatefulWidget {
  final String adminId;
  final String? adminName;

  const AdminPunchoutRequestsScreen({
    super.key,
    required this.adminId,
    this.adminName,
  });

  @override
  State<AdminPunchoutRequestsScreen> createState() =>
      _AdminPunchoutRequestsScreenState();
}

class _AdminPunchoutRequestsScreenState
    extends State<AdminPunchoutRequestsScreen> {
  late final DatabaseReference _database;

  bool _isLoading = true;

  List<Map<String, dynamic>> _requests = [];

  @override
  void initState() {
    super.initState();

    _database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadRequests();
  }

  // ===========================================================================
  // GENERIC HELPERS
  // ===========================================================================

  Map<String, dynamic> _toMap(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(
          key.toString(),
          value,
        ),
      );
    }

    return <String, dynamic>{};
  }

  bool _hasText(dynamic value) {
    if (value == null) {
      return false;
    }

    return value.toString().trim().isNotEmpty;
  }

  String? _cleanString(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  // ===========================================================================
  // LOAD PENDING REQUESTS
  // ===========================================================================

  Future<void> _loadRequests() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final snapshot =
          await _database.child('PunchRequests').get();

      final loadedRequests =
          <Map<String, dynamic>>[];

      if (snapshot.exists &&
          snapshot.value != null) {
        final rawData = snapshot.value;

        if (rawData is Map) {
          rawData.forEach(
            (employeeId, employeeRequests) {
              if (employeeRequests is! Map) {
                return;
              }

              employeeRequests.forEach(
                (date, requestData) {
                  if (requestData is! Map) {
                    return;
                  }

                  final request =
                      _toMap(requestData);

                  final type = request['type']
                          ?.toString()
                          .trim()
                          .toLowerCase() ??
                      '';

                  final status = request['status']
                          ?.toString()
                          .trim()
                          .toLowerCase() ??
                      '';

                  // Only MIS-PUNCH requests waiting for admin.
                  if (type != 'mis_punch' ||
                      status != 'pending') {
                    return;
                  }

                  request['employeeId'] =
                      employeeId.toString();

                  request['date'] =
                      date.toString();

                  loadedRequests.add(request);
                },
              );
            },
          );
        }
      }

      // Newest requests first.
      loadedRequests.sort(
        (a, b) {
          final aCreated =
              DateTime.tryParse(
                    a['createdAt']?.toString() ?? '',
                  ) ??
                  DateTime(2000);

          final bCreated =
              DateTime.tryParse(
                    b['createdAt']?.toString() ?? '',
                  ) ??
                  DateTime(2000);

          return bCreated.compareTo(
            aCreated,
          );
        },
      );

      if (mounted) {
        setState(() {
          _requests = loadedRequests;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint(
        'Error loading punch-out requests: $e',
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
        });

        _showMessage(
          'Unable to load punch-out requests: $e',
        );
      }
    }
  }

  // ===========================================================================
  // EMPLOYEE NAME
  // ===========================================================================

  Future<String> _getEmployeeName(
    String employeeId,
  ) async {
    try {
      // Primary user path.
      final userSnapshot =
          await _database
              .child('users')
              .child(employeeId)
              .get();

      if (userSnapshot.exists &&
          userSnapshot.value is Map) {
        final data =
            _toMap(userSnapshot.value);

        final name =
            _cleanString(data['name']);

        if (name != null) {
          return name;
        }

        final employeeName =
            _cleanString(
          data['employeeName'],
        );

        if (employeeName != null) {
          return employeeName;
        }
      }

      // Backward-compatible Employees path.
      final employeeSnapshot =
          await _database
              .child('Employees')
              .child(employeeId)
              .get();

      if (employeeSnapshot.exists &&
          employeeSnapshot.value is Map) {
        final data =
            _toMap(employeeSnapshot.value);

        final name =
            _cleanString(data['name']);

        if (name != null) {
          return name;
        }

        final employeeName =
            _cleanString(
          data['employeeName'],
        );

        if (employeeName != null) {
          return employeeName;
        }
      }
    } catch (e) {
      debugPrint(
        'Error loading employee name for '
        '$employeeId: $e',
      );
    }

    return employeeId;
  }

  // ===========================================================================
  // TIME PICKER
  // ===========================================================================

  Future<TimeOfDay?> _selectPunchOutTime(
    BuildContext context,
    String? existingPunchOut,
  ) async {
    TimeOfDay initialTime =
        TimeOfDay.now();

    if (_hasText(existingPunchOut)) {
      final parsed =
          _parseTime(existingPunchOut!);

      if (parsed != null) {
        initialTime = parsed;
      }
    }

    return showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText:
          'SELECT ACTUAL PUNCH-OUT TIME',
      cancelText: 'CANCEL',
      confirmText: 'SELECT',
    );
  }

  TimeOfDay? _parseTime(
    String value,
  ) {
    final text = value.trim();

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])$',
    ).firstMatch(text);

    if (match != null) {
      var hour =
          int.tryParse(match.group(1)!) ?? -1;

      final minute =
          int.tryParse(match.group(2)!) ?? -1;

      final period =
          match.group(3)!.toUpperCase();

      if (hour < 1 ||
          hour > 12 ||
          minute < 0 ||
          minute > 59) {
        return null;
      }

      if (period == 'PM' &&
          hour != 12) {
        hour += 12;
      }

      if (period == 'AM' &&
          hour == 12) {
        hour = 0;
      }

      return TimeOfDay(
        hour: hour,
        minute: minute,
      );
    }

    // Also support 24-hour values if an old record has them.
    final twentyFourHour =
        RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(text);

    if (twentyFourHour != null) {
      final hour =
          int.tryParse(
                twentyFourHour.group(1)!,
              ) ??
              -1;

      final minute =
          int.tryParse(
                twentyFourHour.group(2)!,
              ) ??
              -1;

      if (hour >= 0 &&
          hour < 24 &&
          minute >= 0 &&
          minute < 60) {
        return TimeOfDay(
          hour: hour,
          minute: minute,
        );
      }
    }

    return null;
  }

  String _formatTime(
    TimeOfDay time,
  ) {
    final hour =
        time.hourOfPeriod == 0
            ? 12
            : time.hourOfPeriod;

    final minute =
        time.minute
            .toString()
            .padLeft(2, '0');

    final period =
        time.period == DayPeriod.am
            ? 'AM'
            : 'PM';

    return '$hour:$minute $period';
  }

  // ===========================================================================
  // READ SESSIONS
  // ===========================================================================

  List<Map<String, dynamic>> _readSessions(
    Map<String, dynamic> attendance,
  ) {
    final result =
        <Map<String, dynamic>>[];

    final rawSessions =
        attendance['sessions'];

    // -------------------------------------------------------------------------
    // LIST
    // -------------------------------------------------------------------------

    if (rawSessions is List) {
      for (final item in rawSessions) {
        if (item is Map) {
          result.add(
            _toMap(item),
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // MAP
    // -------------------------------------------------------------------------

    else if (rawSessions is Map) {
      final entries =
          rawSessions.entries.toList();

      entries.sort(
        (a, b) {
          final aSession =
              _toMap(a.value);

          final bSession =
              _toMap(b.value);

          final aIn =
              aSession['punchIn']
                  ?.toString() ??
                  '';

          final bIn =
              bSession['punchIn']
                  ?.toString() ??
                  '';

          return aIn.compareTo(
            bIn,
          );
        },
      );

      for (final entry in entries) {
        if (entry.value is Map) {
          result.add(
            _toMap(entry.value),
          );
        }
      }
    }

    // -------------------------------------------------------------------------
    // OLD SINGLE SESSION
    // -------------------------------------------------------------------------

    if (result.isEmpty &&
        _hasText(attendance['punchIn'])) {
      final oldSession =
          <String, dynamic>{
        'punchIn':
            attendance['punchIn'],
      };

      if (_hasText(
        attendance['punchOut'],
      )) {
        oldSession['punchOut'] =
            attendance['punchOut'];
      }

      // Preserve old top-level location.
      if (attendance['punchInLat'] != null) {
        oldSession['punchInLat'] =
            attendance['punchInLat'];
      }

      if (attendance['punchInLng'] != null) {
        oldSession['punchInLng'] =
            attendance['punchInLng'];
      }

      if (_hasText(
        attendance['punchInAddress'],
      )) {
        oldSession['punchInAddress'] =
            attendance['punchInAddress'];
      }

      if (attendance['punchOutLat'] != null) {
        oldSession['punchOutLat'] =
            attendance['punchOutLat'];
      }

      if (attendance['punchOutLng'] != null) {
        oldSession['punchOutLng'] =
            attendance['punchOutLng'];
      }

      if (_hasText(
        attendance['punchOutAddress'],
      )) {
        oldSession['punchOutAddress'] =
            attendance['punchOutAddress'];
      }

      result.add(
        oldSession,
      );
    }

    return result;
  }

  // ===========================================================================
  // FIND OPEN SESSION
  // ===========================================================================

  int _findOpenSession(
    List<Map<String, dynamic>> sessions,
  ) {
    // The MIS-PUNCH belongs to the current/latest
    // open session.
    //
    // We search backwards so that if old malformed
    // data contains more than one open session,
    // the latest one is corrected.
    for (var i =
            sessions.length - 1;
        i >= 0;
        i--) {
      final session =
          sessions[i];

      final hasPunchIn =
          _hasText(
        session['punchIn'],
      );

      final hasPunchOut =
          _hasText(
        session['punchOut'],
      );

      if (hasPunchIn &&
          !hasPunchOut) {
        return i;
      }
    }

    return -1;
  }

  // ===========================================================================
  // CORRECT MIS-PUNCH
  // ===========================================================================

  Future<void> _correctAttendance(
    Map<String, dynamic> request,
  ) async {
    final employeeId =
        request['employeeId']
                ?.toString()
                .trim() ??
            '';

    final date =
        request['date']
                ?.toString()
                .trim() ??
            '';

    if (employeeId.isEmpty ||
        date.isEmpty) {
      _showMessage(
        'Invalid punch-out request.',
      );
      return;
    }

    try {
      // -----------------------------------------------------------------------
      // LOAD ATTENDANCE
      // -----------------------------------------------------------------------

      final attendanceRef =
          _database
              .child('Attendance')
              .child(employeeId)
              .child(date);

      final attendanceSnapshot =
          await attendanceRef.get();

      if (!attendanceSnapshot.exists ||
          attendanceSnapshot.value == null) {
        _showMessage(
          'Attendance record not found.',
        );
        return;
      }

      final attendance =
          _toMap(
        attendanceSnapshot.value,
      );

      if (attendance.isEmpty) {
        _showMessage(
          'Invalid attendance record.',
        );
        return;
      }

      // -----------------------------------------------------------------------
      // VERIFY THIS IS ACTUALLY MIS-PUNCH
      // -----------------------------------------------------------------------

      final attendanceStatus =
          attendance['status']
                  ?.toString()
                  .trim()
                  .toUpperCase() ??
              '';

      final isMisPunch =
          attendance['misPunch'] == true ||
              attendanceStatus ==
                  'MIS-PUNCH' ||
              attendanceStatus
                  .contains('MIS-PUNCH');

      if (!isMisPunch) {
        _showMessage(
          'This attendance record is no longer marked as MIS-PUNCH.',
        );

        // Refresh because another admin may already
        // have processed it.
        await _loadRequests();
        return;
      }

      // -----------------------------------------------------------------------
      // READ SESSIONS
      // -----------------------------------------------------------------------

      final sessions =
          _readSessions(attendance);

      if (sessions.isEmpty) {
        _showMessage(
          'No attendance session found.',
        );
        return;
      }

      // -----------------------------------------------------------------------
      // FIND OPEN SESSION
      // -----------------------------------------------------------------------

      final openSessionIndex =
          _findOpenSession(
        sessions,
      );

      if (openSessionIndex == -1) {
        _showMessage(
          'No open punch-in session was found for this MIS-PUNCH.',
        );
        return;
      }

      final openSession =
          sessions[openSessionIndex];

      // -----------------------------------------------------------------------
      // SELECT ACTUAL PUNCH-OUT
      // -----------------------------------------------------------------------

      final existingPunchOut =
          _cleanString(
        openSession['punchOut'],
      );

      final selectedTime =
          await _selectPunchOutTime(
        context,
        existingPunchOut,
      );

      if (selectedTime == null) {
        return;
      }

      final punchOutText =
          _formatTime(
        selectedTime,
      );

      // -----------------------------------------------------------------------
      // GET EMPLOYEE NAME
      // -----------------------------------------------------------------------

      final requestedEmployeeName =
          _cleanString(
        request['employeeName'],
      );

      final employeeName =
          requestedEmployeeName ??
              await _getEmployeeName(
                employeeId,
              );

      if (!mounted) {
        return;
      }

      // -----------------------------------------------------------------------
      // CONFIRM
      // -----------------------------------------------------------------------

      final confirmed =
          await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text(
              'Confirm Punch-Out',
            ),
            content: Text(
              'Set the actual punch-out time for '
              '$employeeName ($employeeId) on '
              '$date to $punchOutText?',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(false);
                },
                child: const Text(
                  'CANCEL',
                ),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop(true);
                },
                child: const Text(
                  'CONFIRM',
                ),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }

      // -----------------------------------------------------------------------
      // UPDATE ONLY THE OPEN SESSION
      // -----------------------------------------------------------------------

      final correctedSession =
          Map<String, dynamic>.from(
        openSession,
      );

      correctedSession['punchOut'] =
          punchOutText;

      // Temporary MIS-PUNCH fields must not
      // remain inside the session either.
      correctedSession.remove(
        'temporaryPunchOut',
      );

      correctedSession.remove(
        'misPunch',
      );

      correctedSession.remove(
        'misPunchDetectedAt',
      );

      sessions[openSessionIndex] =
          correctedSession;

      // -----------------------------------------------------------------------
      // VERIFY ALL SESSIONS ARE NOW CLOSED
      // -----------------------------------------------------------------------

      final allClosed =
          sessions.every(
        (session) {
          return _hasText(
                session['punchIn'],
              ) &&
              _hasText(
                session['punchOut'],
              );
        },
      );

      if (!allClosed) {
        _showMessage(
          'All attendance sessions must be closed before completing the MIS-PUNCH correction.',
        );
        return;
      }

      // -----------------------------------------------------------------------
      // BUILD CALCULATOR SESSIONS
      // -----------------------------------------------------------------------

      final calculatorSessions =
          <AttendanceSession>[];

      for (final session in sessions) {
        final punchIn =
            _cleanString(
          session['punchIn'],
        );

        final punchOut =
            _cleanString(
          session['punchOut'],
        );

        if (punchIn == null ||
            punchOut == null) {
          continue;
        }

        calculatorSessions.add(
          AttendanceSession(
            punchIn: punchIn,
            punchOut: punchOut,
          ),
        );
      }

      if (calculatorSessions.isEmpty) {
        _showMessage(
          'Unable to calculate corrected attendance.',
        );
        return;
      }

      // -----------------------------------------------------------------------
      // CENTRAL ATTENDANCE CALCULATOR
      //
      // This is important:
      // Do NOT manually calculate hours here.
      //
      // AttendanceCalculator handles:
      // - 9-hour requirement
      // - lunch 1 PM–2 PM counts as work
      // - multiple sessions
      // - extra hours
      // - shortfall
      // -----------------------------------------------------------------------

      final calculation =
          AttendanceCalculator.calculateFromSessions(
        calculatorSessions,
        workFromHome:
            attendance['workFromHome'] == true,
      );

      // -----------------------------------------------------------------------
      // FINAL CLASSIFICATION
      // -----------------------------------------------------------------------

      String finalClassification;

      switch (calculation.dayType) {
        case DayType.fullDay:
          finalClassification =
              'FULL DAY';
          break;

        case DayType.workPending:
          finalClassification =
              'WORK-PENDING';
          break;

        case DayType.absent:
          finalClassification =
              'ABSENT';
          break;
      }

      // -----------------------------------------------------------------------
      // REMOVE ALL MIS-PUNCH TEMPORARY DATA
      // -----------------------------------------------------------------------

      attendance.remove(
        'temporaryPunchOut',
      );

      attendance.remove(
        'misPunch',
      );

      attendance.remove(
        'misPunchDetectedAt',
      );

      attendance.remove(
        'punchoutRequestStatus',
      );

      // Old automatic checkout fields.
      attendance.remove(
        'automaticCheckout',
      );

      attendance.remove(
        'autoCheckout',
      );

      attendance.remove(
        'autoCheckoutTime',
      );

      attendance.remove(
        'autoPunchOut',
      );

      attendance.remove(
        'approvedAutoCheckout',
      );

      // -----------------------------------------------------------------------
      // SAVE SESSIONS
      // -----------------------------------------------------------------------

      attendance['sessions'] =
          sessions;

      // -----------------------------------------------------------------------
      // TOP LEVEL COMPATIBILITY
      //
      // Session-specific locations remain untouched.
      // These fields are only for old screens/reports.
      // -----------------------------------------------------------------------

      final firstSession =
          sessions.first;

      final lastSession =
          sessions.last;

      attendance['punchIn'] =
          firstSession['punchIn'];

      attendance['punchOut'] =
          lastSession['punchOut'];

      // -----------------------------------------------------------------------
      // FIRST SESSION PUNCH-IN LOCATION
      // -----------------------------------------------------------------------

      if (firstSession['punchInLat'] != null) {
        attendance['punchInLat'] =
            firstSession['punchInLat'];
      } else {
        attendance.remove(
          'punchInLat',
        );
      }

      if (firstSession['punchInLng'] != null) {
        attendance['punchInLng'] =
            firstSession['punchInLng'];
      } else {
        attendance.remove(
          'punchInLng',
        );
      }

      final firstInAddress =
          _cleanString(
        firstSession['punchInAddress'],
      );

      if (firstInAddress != null) {
        attendance['punchInAddress'] =
            firstInAddress;
      } else {
        attendance.remove(
          'punchInAddress',
        );
      }

      // -----------------------------------------------------------------------
      // LAST SESSION PUNCH-OUT LOCATION
      //
      // IMPORTANT:
      // We do NOT create a location here.
      // If the employee never recorded one,
      // these fields stay absent.
      // -----------------------------------------------------------------------

      if (lastSession['punchOutLat'] != null) {
        attendance['punchOutLat'] =
            lastSession['punchOutLat'];
      } else {
        attendance.remove(
          'punchOutLat',
        );
      }

      if (lastSession['punchOutLng'] != null) {
        attendance['punchOutLng'] =
            lastSession['punchOutLng'];
      } else {
        attendance.remove(
          'punchOutLng',
        );
      }

      final lastOutAddress =
          _cleanString(
        lastSession['punchOutAddress'],
      );

      if (lastOutAddress != null) {
        attendance['punchOutAddress'] =
            lastOutAddress;
      } else {
        attendance.remove(
          'punchOutAddress',
        );
      }

      // -----------------------------------------------------------------------
      // NORMAL ATTENDANCE STATUS
      // -----------------------------------------------------------------------

      attendance['status'] =
          'Checked Out';

      attendance['attendanceStatus'] =
          finalClassification;

      attendance['dayType'] =
          calculation.dayType.name;

      attendance['netHours'] =
          calculation.netHours;

      attendance['workingHours'] =
          calculation.netHours;

      attendance['shortfallHours'] =
          calculation.shortfallHours;

      attendance['extraHours'] =
          calculation.extraHours;

      attendance['updatedAt'] =
          DateTime.now().toIso8601String();

      // Record that an admin manually corrected
      // the MIS-PUNCH.
      attendance['manualEdited'] =
          true;

      attendance['manualEditedBy'] =
          widget.adminId;

      attendance['manualEditedByName'] =
          widget.adminName ??
              widget.adminId;

      attendance['manualEditedAt'] =
          DateTime.now().toIso8601String();

      // -----------------------------------------------------------------------
      // SAVE ATTENDANCE
      // -----------------------------------------------------------------------

      await attendanceRef.set(
        attendance,
      );

      // -----------------------------------------------------------------------
      // UPDATE REQUEST
      // -----------------------------------------------------------------------

      await _database
          .child('PunchRequests')
          .child(employeeId)
          .child(date)
          .update({
        'status': 'approved',
        'processedBy': widget.adminId,
        'processedByName':
            widget.adminName ??
                widget.adminId,
        'processedAt':
            DateTime.now()
                .toIso8601String(),
        'actualPunchOut':
            punchOutText,
        'finalAttendanceStatus':
            finalClassification,
        'finalNetHours':
            calculation.netHours,
      });

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Punch-out corrected successfully for '
            '$employeeName. Final status: '
            '$finalClassification.',
          ),
        ),
      );

      await _loadRequests();
    } catch (e) {
      debugPrint(
        'Error correcting MIS-PUNCH: $e',
      );

      if (mounted) {
        _showMessage(
          'Could not correct punch-out: $e',
        );
      }
    }
  }

  // ===========================================================================
  // MESSAGE
  // ===========================================================================

  void _showMessage(
    String message,
  ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      ),
    );
  }

  // ===========================================================================
  // REQUEST CARD
  // ===========================================================================

  Widget _buildRequestCard(
    Map<String, dynamic> request,
  ) {
    final employeeId =
        request['employeeId']
                ?.toString() ??
            '';

    final date =
        request['date']
                ?.toString() ??
            '';

    final storedEmployeeName =
        _cleanString(
      request['employeeName'],
    );

    final message =
        _cleanString(
      request['message'],
    );

    final punchIn =
        _cleanString(
      request['punchIn'],
    );

    return FutureBuilder<String>(
      future:
          storedEmployeeName == null
              ? _getEmployeeName(
                  employeeId,
                )
              : Future.value(
                  storedEmployeeName,
                ),
      builder: (
        context,
        snapshot,
      ) {
        final displayName =
            snapshot.data ??
                storedEmployeeName ??
                employeeId;

        return Card(
          margin: const EdgeInsets.only(
            bottom: 12,
          ),
          elevation: 2,
          child: Padding(
            padding:
                const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // =============================================================
                // EMPLOYEE
                // =============================================================

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      child: Text(
                        displayName.isNotEmpty
                            ? displayName[0]
                                .toUpperCase()
                            : '?',
                      ),
                    ),
                    const SizedBox(
                      width: 12,
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            style:
                                const TextStyle(
                              fontSize: 17,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const SizedBox(
                            height: 3,
                          ),
                          Text(
                            employeeId,
                            style:
                                TextStyle(
                              color: Colors
                                  .grey
                                  .shade600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding:
                          const EdgeInsets
                              .symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration:
                          BoxDecoration(
                        color: Colors.orange
                            .withOpacity(
                          0.12,
                        ),
                        borderRadius:
                            BorderRadius.circular(
                          20,
                        ),
                      ),
                      child:
                          const Text(
                        'MIS-PUNCH',
                        style:
                            TextStyle(
                          color:
                              Colors.orange,
                          fontSize: 11,
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(
                  height: 16,
                ),

                // =============================================================
                // DATE
                // =============================================================

                _infoRow(
                  Icons
                      .calendar_today_outlined,
                  'Date',
                  date,
                ),

                // =============================================================
                // PUNCH IN
                // =============================================================

                if (punchIn != null &&
                    punchIn.isNotEmpty)
                  _infoRow(
                    Icons.login_outlined,
                    'Punch In',
                    punchIn,
                  ),

                // =============================================================
                // EMPLOYEE MESSAGE
                // =============================================================

                if (message != null &&
                    message.isNotEmpty) ...[
                  const SizedBox(
                    height: 8,
                  ),
                  Container(
                    width: double.infinity,
                    padding:
                        const EdgeInsets.all(
                      12,
                    ),
                    decoration:
                        BoxDecoration(
                      color:
                          Colors.grey.shade100,
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        const Text(
                          'Employee Message',
                          style:
                              TextStyle(
                            fontWeight:
                                FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(
                          height: 5,
                        ),
                        Text(
                          message,
                          style:
                              const TextStyle(
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(
                  height: 16,
                ),

                // =============================================================
                // CORRECT BUTTON
                // =============================================================

                SizedBox(
                  width: double.infinity,
                  child:
                      ElevatedButton.icon(
                    onPressed: () {
                      _correctAttendance(
                        request,
                      );
                    },
                    icon: const Icon(
                      Icons.access_time,
                    ),
                    label: const Text(
                      'SELECT ACTUAL PUNCH-OUT',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _infoRow(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 7,
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: AppColors.primary,
          ),
          const SizedBox(
            width: 9,
          ),
          Text(
            '$label: ',
            style:
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
          Expanded(
            child: Text(
              value,
              overflow:
                  TextOverflow.ellipsis,
            ),
          ),
        ],
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
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Punchout Requests',
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed:
                _isLoading
                    ? null
                    : _loadRequests,
            icon: const Icon(
              Icons.refresh,
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRequests,
        child: _isLoading
            ? const Center(
                child:
                    CircularProgressIndicator(),
              )
            : _requests.isEmpty
                ? ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(
                        height: 180,
                      ),
                      Center(
                        child: Icon(
                          Icons
                              .check_circle_outline,
                          size: 60,
                          color: Colors.grey,
                        ),
                      ),
                      SizedBox(
                        height: 16,
                      ),
                      Center(
                        child: Text(
                          'No pending punch-out requests',
                          style:
                              TextStyle(
                            fontSize: 16,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 8,
                      ),
                      Center(
                        child: Text(
                          'MIS-PUNCH requests from employees will appear here.',
                          textAlign:
                              TextAlign.center,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.all(
                      16,
                    ),
                    itemCount:
                        _requests.length,
                    itemBuilder:
                        (context, index) {
                      return _buildRequestCard(
                        _requests[index],
                      );
                    },
                  ),
      ),
    );
  }
}