import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Admin/Super Admin editor for one employee's attendance day.
///
/// Rules:
/// - Supports unlimited sessions.
/// - Supports old single punchIn/punchOut records.
/// - Preserves session-specific locations.
/// - Never creates or changes GPS locations.
/// - Does not use temporary MIS-PUNCH punch-out as real punch-out.
/// - An open session remains Checked In.
/// - Closed sessions are classified as FULL DAY / WORK-PENDING / ABSENT.
/// - No half-day classification.
///
class AdminAttendanceEditorScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  final String? date;
  final DateTime? initialDate;

  final String adminId;
  final String adminName;

  const AdminAttendanceEditorScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.date,
    this.initialDate,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<AdminAttendanceEditorScreen> createState() =>
      _AdminAttendanceEditorScreenState();
}

class _AdminAttendanceEditorScreenState
    extends State<AdminAttendanceEditorScreen> {
  late final DatabaseReference _recordRef;

  final List<_EditableSession> _sessions = [];

  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> _original = {};

  String get _dateKey {
    if (widget.date != null && widget.date!.trim().isNotEmpty) {
      return widget.date!.trim();
    }

    return DateFormat('yyyy-MM-dd').format(
      widget.initialDate ?? DateTime.now(),
    );
  }

  DateTime get _selectedDate =>
      DateTime.tryParse(_dateKey) ?? DateTime.now();

  @override
  void initState() {
    super.initState();

    final database = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    );

    _recordRef = database
        .ref()
        .child('Attendance')
        .child(widget.employeeId)
        .child(_dateKey);

    _load();
  }

  // ===========================================================================
  // HELPERS
  // ===========================================================================

  Map<String, dynamic> _map(dynamic value) {
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

  String? _stringValue(dynamic value) {
    if (value == null) {
      return null;
    }

    final text = value.toString().trim();

    if (text.isEmpty) {
      return null;
    }

    return text;
  }

  bool _hasValue(dynamic value) {
    if (value == null) {
      return false;
    }

    if (value is String) {
      return value.trim().isNotEmpty;
    }

    return true;
  }

  // ===========================================================================
  // LOAD
  // ===========================================================================

  Future<void> _load() async {
    try {
      final snapshot = await _recordRef.get();

      _original = _map(snapshot.value);

      _sessions.clear();

      final raw = _original['sessions'];

      // -----------------------------------------------------------------------
      // MULTIPLE SESSION LIST
      // -----------------------------------------------------------------------

      if (raw is List) {
        for (final item in raw) {
          final session = _map(item);

          if (!_hasValue(session['punchIn'])) {
            continue;
          }

          _sessions.add(
            _EditableSession(
              punchIn: session['punchIn'].toString(),
              punchOut: _stringValue(
                session['punchOut'],
              ),
              punchInLat: session['punchInLat'],
              punchInLng: session['punchInLng'],
              punchInAddress:
                  _stringValue(session['punchInAddress']),
              punchOutLat: session['punchOutLat'],
              punchOutLng: session['punchOutLng'],
              punchOutAddress:
                  _stringValue(session['punchOutAddress']),
            ),
          );
        }
      }

      // -----------------------------------------------------------------------
      // MULTIPLE SESSION MAP
      // -----------------------------------------------------------------------

      else if (raw is Map) {
        final entries = raw.entries.toList()
          ..sort(
            (a, b) => a.key.toString().compareTo(
                  b.key.toString(),
                ),
          );

        for (final entry in entries) {
          final session = _map(entry.value);

          if (!_hasValue(session['punchIn'])) {
            continue;
          }

          _sessions.add(
            _EditableSession(
              punchIn: session['punchIn'].toString(),
              punchOut: _stringValue(
                session['punchOut'],
              ),
              punchInLat: session['punchInLat'],
              punchInLng: session['punchInLng'],
              punchInAddress:
                  _stringValue(session['punchInAddress']),
              punchOutLat: session['punchOutLat'],
              punchOutLng: session['punchOutLng'],
              punchOutAddress:
                  _stringValue(session['punchOutAddress']),
            ),
          );
        }
      }

      // -----------------------------------------------------------------------
      // OLD SINGLE SESSION FORMAT
      // -----------------------------------------------------------------------

      if (_sessions.isEmpty && _hasValue(_original['punchIn'])) {
        _sessions.add(
          _EditableSession(
            punchIn: _original['punchIn'].toString(),
            punchOut: _stringValue(
              _original['punchOut'],
            ),
            punchInLat: _original['punchInLat'],
            punchInLng: _original['punchInLng'],
            punchInAddress:
                _stringValue(_original['punchInAddress']),
            punchOutLat: _original['punchOutLat'],
            punchOutLng: _original['punchOutLng'],
            punchOutAddress:
                _stringValue(_original['punchOutAddress']),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError(
          'Could not load attendance: $e',
        );
      }
    }

    if (mounted) {
      setState(() {
        _loading = false;
      });
    }
  }

  // ===========================================================================
  // TIME HELPERS
  // ===========================================================================

  int? _minutes(String value) {
    final text = value.trim();

    try {
      final dt = DateFormat('hh:mm a').parse(text);
      return dt.hour * 60 + dt.minute;
    } catch (_) {}

    try {
      final dt = DateFormat('HH:mm').parse(text);
      return dt.hour * 60 + dt.minute;
    } catch (_) {}

    final match = RegExp(
      r'^(\d{1,2}):(\d{2})\s*([AaPp][Mm])?',
    ).firstMatch(text);

    if (match != null) {
      var hour = int.tryParse(
            match.group(1)!,
          ) ??
          0;

      final minute = int.tryParse(
            match.group(2)!,
          ) ??
          0;

      final period = match.group(3)?.toLowerCase();

      if (period == 'pm' && hour < 12) {
        hour += 12;
      }

      if (period == 'am' && hour == 12) {
        hour = 0;
      }

      if (hour >= 0 &&
          hour < 24 &&
          minute >= 0 &&
          minute < 60) {
        return hour * 60 + minute;
      }
    }

    return null;
  }

  String _formatTimeOfDay(TimeOfDay time) {
    final hour =
        time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;

    final minute =
        time.minute.toString().padLeft(2, '0');

    final suffix =
        time.period == DayPeriod.am ? 'AM' : 'PM';

    return '${hour.toString().padLeft(2, '0')}:$minute $suffix';
  }

  TimeOfDay _timeOfDay(
    String? value, {
    bool end = false,
  }) {
    if (value != null) {
      final mins = _minutes(value);

      if (mins != null) {
        return TimeOfDay(
          hour: mins ~/ 60,
          minute: mins % 60,
        );
      }
    }

    return TimeOfDay(
      hour: end ? 17 : 9,
      minute: 0,
    );
  }

  Future<String?> _pickTime(
    String? current, {
    required String title,
    bool end = false,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _timeOfDay(
        current,
        end: end,
      ),
      helpText: title,
    );

    if (picked == null) {
      return null;
    }

    return _formatTimeOfDay(picked);
  }

  // ===========================================================================
  // SESSION MANAGEMENT
  // ===========================================================================

  void _addSession() {
    setState(() {
      _sessions.add(
        _EditableSession(
          punchIn: '09:00 AM',
          punchOut: '06:00 PM',
        ),
      );
    });
  }

  Future<void> _editPunchIn(int index) async {
    final value = await _pickTime(
      _sessions[index].punchIn,
      title: 'Select punch-in time',
    );

    if (value != null && mounted) {
      setState(() {
        _sessions[index].punchIn = value;
      });
    }
  }

  Future<void> _editPunchOut(int index) async {
    final value = await _pickTime(
      _sessions[index].punchOut,
      title: 'Select punch-out time',
      end: true,
    );

    if (value != null && mounted) {
      setState(() {
        _sessions[index].punchOut = value;
      });
    }
  }

  // ===========================================================================
  // VALIDATION
  // ===========================================================================

  bool _validate() {
    if (_sessions.isEmpty) {
      return true;
    }

    for (var i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];

      final inMinutes = _minutes(
        session.punchIn,
      );

      final outMinutes = session.punchOut == null
          ? null
          : _minutes(
              session.punchOut!,
            );

      if (inMinutes == null) {
        _showError(
          'Session ${i + 1}: invalid punch-in time.',
        );

        return false;
      }

      if (outMinutes != null &&
          outMinutes <= inMinutes) {
        _showError(
          'Session ${i + 1}: punch-out must be after punch-in.',
        );

        return false;
      }

      if (i > 0) {
        final previous = _sessions[i - 1];

        final previousOut = previous.punchOut == null
            ? null
            : _minutes(
                previous.punchOut!,
              );

        if (previousOut == null) {
          _showError(
            'Close Session $i before starting Session ${i + 1}.',
          );

          return false;
        }

        if (inMinutes <= previousOut) {
          _showError(
            'Session ${i + 1} overlaps Session $i.',
          );

          return false;
        }
      }
    }

    return true;
  }

  // ===========================================================================
  // CLASSIFICATION
  // ===========================================================================

  String _classificationFromResult(
    AttendanceResult result,
  ) {
    switch (result.dayType) {
      case DayType.fullDay:
        return 'FULL DAY';

      case DayType.workPending:
        return 'WORK-PENDING';

      case DayType.absent:
        return 'ABSENT';
    }
  }

  // ===========================================================================
  // SAVE
  // ===========================================================================

  Future<void> _save() async {
    if (_saving || !_validate()) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      // -----------------------------------------------------------------------
      // REMOVE DAY
      // -----------------------------------------------------------------------

      if (_sessions.isEmpty) {
        await _recordRef.remove();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Attendance removed successfully.',
            ),
          ),
        );

        Navigator.pop(
          context,
          true,
        );

        return;
      }

      // -----------------------------------------------------------------------
      // BUILD SESSIONS
      // -----------------------------------------------------------------------

      final sessionMaps = _sessions.map(
        (session) {
          final map = <String, dynamic>{
            'punchIn': session.punchIn,
          };

          if (session.punchOut != null &&
              session.punchOut!.trim().isNotEmpty) {
            map['punchOut'] = session.punchOut;
          }

          // ---------------------------------------------------------------
          // PUNCH-IN LOCATION
          // ---------------------------------------------------------------

          if (session.punchInLat != null) {
            map['punchInLat'] = session.punchInLat;
          }

          if (session.punchInLng != null) {
            map['punchInLng'] = session.punchInLng;
          }

          if (session.punchInAddress != null &&
              session.punchInAddress!.trim().isNotEmpty) {
            map['punchInAddress'] =
                session.punchInAddress;
          }

          // ---------------------------------------------------------------
          // PUNCH-OUT LOCATION
          // ---------------------------------------------------------------

          if (session.punchOutLat != null) {
            map['punchOutLat'] = session.punchOutLat;
          }

          if (session.punchOutLng != null) {
            map['punchOutLng'] = session.punchOutLng;
          }

          if (session.punchOutAddress != null &&
              session.punchOutAddress!.trim().isNotEmpty) {
            map['punchOutAddress'] =
                session.punchOutAddress;
          }

          return map;
        },
      ).toList();

      final allClosed = _sessions.every(
        (session) =>
            session.punchOut != null &&
            session.punchOut!.trim().isNotEmpty,
      );

      final firstSession = _sessions.first;
      final lastSession = _sessions.last;

      final update = <String, dynamic>{
        ..._original,

        'employeeId': widget.employeeId,
        'date': _dateKey,

        'sessions': sessionMaps,

        // Legacy compatibility.
        'punchIn': firstSession.punchIn,

        'manualEdited': true,
        'manualEditedBy': widget.adminId,
        'manualEditedByName': widget.adminName,
        'manualEditedAt':
            DateTime.now().toIso8601String(),

        'status': allClosed
            ? 'Checked Out'
            : 'Checked In',
      };

      // -----------------------------------------------------------------------
      // TOP LEVEL PUNCH-OUT
      // -----------------------------------------------------------------------

      if (allClosed) {
        update['punchOut'] =
            lastSession.punchOut;

        // The record is now a normal attendance record.
        update.remove('temporaryPunchOut');
        update.remove('autoPunchOut');
        update.remove('approvedAutoCheckout');
        update.remove('misPunch');
        update.remove('misPunchDetectedAt');
        update.remove('punchoutRequestStatus');
      } else {
        // Open attendance is NOT final attendance.
        //
        // Never manufacture a punch-out.
        update.remove('punchOut');
      }

      // -----------------------------------------------------------------------
      // TOP LEVEL LOCATION COMPATIBILITY
      //
      // These are compatibility fields only.
      // Session-specific locations remain the source of truth.
      // -----------------------------------------------------------------------

      if (firstSession.punchInLat != null) {
        update['punchInLat'] =
            firstSession.punchInLat;
      } else {
        update.remove('punchInLat');
      }

      if (firstSession.punchInLng != null) {
        update['punchInLng'] =
            firstSession.punchInLng;
      } else {
        update.remove('punchInLng');
      }

      if (firstSession.punchInAddress != null &&
          firstSession.punchInAddress!.trim().isNotEmpty) {
        update['punchInAddress'] =
            firstSession.punchInAddress;
      } else {
        update.remove('punchInAddress');
      }

      if (lastSession.punchOutLat != null) {
        update['punchOutLat'] =
            lastSession.punchOutLat;
      } else {
        update.remove('punchOutLat');
      }

      if (lastSession.punchOutLng != null) {
        update['punchOutLng'] =
            lastSession.punchOutLng;
      } else {
        update.remove('punchOutLng');
      }

      if (lastSession.punchOutAddress != null &&
          lastSession.punchOutAddress!.trim().isNotEmpty) {
        update['punchOutAddress'] =
            lastSession.punchOutAddress;
      } else {
        update.remove('punchOutAddress');
      }

      // -----------------------------------------------------------------------
      // FINAL ATTENDANCE CLASSIFICATION
      // -----------------------------------------------------------------------

      if (allClosed) {
        final calculatorSessions = sessionMaps.map(
          (session) {
            return AttendanceSession(
              punchIn: session['punchIn'].toString(),
              punchOut:
                  session['punchOut']?.toString(),
            );
          },
        ).toList();

        final result =
            AttendanceCalculator.calculateFromSessions(
          calculatorSessions,
          workFromHome:
              update['workFromHome'] == true,
        );

        final classification =
            _classificationFromResult(result);

        update['attendanceStatus'] =
            classification;

        update['dayType'] =
            result.dayType.name;

        update['workingHours'] =
            result.netHours;

        update['netHours'] =
            result.netHours;

        update['shortfallHours'] =
            result.shortfallHours;

        update['extraHours'] =
            result.extraHours;
      } else {
        // ---------------------------------------------------------------
        // OPEN SESSION
        // ---------------------------------------------------------------
        //
        // An open session is not:
        // FULL DAY
        // WORK-PENDING
        // ABSENT
        //
        // It remains Checked In until the employee punches out.
        //

        update.remove('attendanceStatus');
        update.remove('dayType');
        update.remove('workingHours');
        update.remove('netHours');
        update.remove('shortfallHours');
        update.remove('extraHours');
      }

      // -----------------------------------------------------------------------
      // SAVE
      // -----------------------------------------------------------------------

      await _recordRef.set(
        update,
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Attendance updated successfully.',
          ),
        ),
      );

      Navigator.pop(
        context,
        true,
      );
    } catch (e) {
      if (mounted) {
        _showError(
          'Could not save attendance: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  // ===========================================================================
  // REMOVE SESSION
  // ===========================================================================

  Future<void> _removeSession(
    int index,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) {
        return AlertDialog(
          title: const Text(
            'Remove session?',
          ),
          content: Text(
            'Remove Session ${index + 1} from this attendance day?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  false,
                );
              },
              child: const Text(
                'Cancel',
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(
                  context,
                  true,
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text(
                'Remove',
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      setState(() {
        _sessions.removeAt(index);
      });
    }
  }

  // ===========================================================================
  // ERROR
  // ===========================================================================

  void _showError(
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
  // WORKING HOURS PREVIEW
  // ===========================================================================

  String _workingHoursPreview() {
    if (_sessions.isEmpty) {
      return '0 hr 0 min';
    }

    try {
      final result =
          AttendanceCalculator.calculateFromSessions(
        _sessions.map(
          (session) {
            return AttendanceSession(
              punchIn: session.punchIn,
              punchOut: session.punchOut,
            );
          },
        ).toList(),
        workFromHome:
            _original['workFromHome'] == true,
      );

      return AttendanceCalculator.formatHours(
        result.netHours,
      );
    } catch (_) {
      return '--';
    }
  }

  // ===========================================================================
  // BUILD
  // ===========================================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final dateLabel = DateFormat(
      'EEE, dd MMM yyyy',
    ).format(_selectedDate);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text(
          'Edit Attendance',
        ),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(
              Icons.check,
            ),
            tooltip: 'Save',
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // =============================================================
                // EMPLOYEE HEADER
                // =============================================================

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius:
                        BorderRadius.circular(16),
                    boxShadow: AppShadows.card,
                  ),
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.employeeName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${widget.employeeId} • $dateLabel',
                        style: const TextStyle(
                          color:
                              AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(
                            Icons.timer_outlined,
                            color: AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'Working hours',
                            style: TextStyle(
                              color: AppColors
                                  .textSecondary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            _workingHoursPreview(),
                            style: const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                const Text(
                  'Attendance Sessions',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                if (_sessions.isEmpty)
                  Container(
                    padding:
                        const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'No sessions recorded. Add a session below to mark attendance.',
                    ),
                  ),

                ..._sessions
                    .asMap()
                    .entries
                    .map(
                      (entry) => _sessionCard(
                        entry.key,
                        entry.value,
                      ),
                    ),

                const SizedBox(height: 8),

                // =============================================================
                // ADD SESSION
                // =============================================================

                OutlinedButton.icon(
                  onPressed:
                      _saving ? null : _addSession,
                  icon: const Icon(Icons.add),
                  label: const Text(
                    'Add Session',
                  ),
                  style:
                      OutlinedButton.styleFrom(
                    foregroundColor:
                        AppColors.primary,
                    side: const BorderSide(
                      color: AppColors.primary,
                    ),
                    minimumSize:
                        const Size.fromHeight(48),
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(14),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                // =============================================================
                // ADMIN NOTICE
                // =============================================================

                Container(
                  padding:
                      const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(
                      alpha: .10,
                    ),
                    borderRadius:
                        BorderRadius.circular(12),
                  ),
                  child: const Row(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons
                            .admin_panel_settings_outlined,
                        color: Colors.amber,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Admin edit: changes are recorded as a manual attendance edit. The employee history screen remains read-only.',
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // =============================================================
                // SAVE
                // =============================================================

                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed:
                        _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child:
                                CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(
                            Icons.save_outlined,
                          ),
                    label: Text(
                      _saving
                          ? 'Saving...'
                          : 'Save Changes',
                    ),
                    style:
                        ElevatedButton.styleFrom(
                      backgroundColor:
                          AppColors.primary,
                      foregroundColor: Colors.white,
                      shape:
                          RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // ===========================================================================
  // SESSION CARD
  // ===========================================================================

  Widget _sessionCard(
    int index,
    _EditableSession session,
  ) {
    return Container(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Session ${index + 1}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed:
                    _saving
                        ? null
                        : () =>
                            _removeSession(index),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
                tooltip: 'Remove session',
              ),
            ],
          ),

          const SizedBox(height: 4),

          // ===============================================================
          // TIMES
          // ===============================================================

          Row(
            children: [
              Expanded(
                child: _timeTile(
                  label: 'Punch In',
                  value: session.punchIn,
                  icon: Icons.login,
                  onTap: () =>
                      _editPunchIn(index),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _timeTile(
                  label: 'Punch Out',
                  value:
                      session.punchOut ?? '--',
                  icon: Icons.logout,
                  onTap: () =>
                      _editPunchOut(index),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ===============================================================
          // SESSION LOCATIONS
          // ===============================================================

          _locationSection(session),
        ],
      ),
    );
  }

  // ===========================================================================
  // LOCATION SECTION
  // ===========================================================================

  Widget _locationSection(
    _EditableSession session,
  ) {
    final hasPunchInLocation =
        session.punchInLat != null ||
            session.punchInLng != null ||
            (session.punchInAddress != null &&
                session.punchInAddress!
                    .trim()
                    .isNotEmpty);

    final hasPunchOutLocation =
        session.punchOutLat != null ||
            session.punchOutLng != null ||
            (session.punchOutAddress != null &&
                session.punchOutAddress!
                    .trim()
                    .isNotEmpty);

    if (!hasPunchInLocation &&
        !hasPunchOutLocation) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.divider,
          ),
        ),
        child: const Row(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_off_outlined,
              size: 18,
              color: AppColors.textSecondary,
            ),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'No location recorded for this session.',
                style: TextStyle(
                  color:
                      AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius:
            BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                size: 18,
                color: AppColors.primary,
              ),
              SizedBox(width: 7),
              Text(
                'Session Locations',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          if (hasPunchInLocation)
            _locationRow(
              icon: Icons.login_outlined,
              title: 'Punch-in location',
              latitude: session.punchInLat,
              longitude: session.punchInLng,
              address:
                  session.punchInAddress,
            ),

          if (hasPunchInLocation &&
              hasPunchOutLocation)
            const Divider(height: 18),

          if (hasPunchOutLocation)
            _locationRow(
              icon: Icons.logout_outlined,
              title: 'Punch-out location',
              latitude: session.punchOutLat,
              longitude: session.punchOutLng,
              address:
                  session.punchOutAddress,
            ),
        ],
      ),
    );
  }

  Widget _locationRow({
    required IconData icon,
    required String title,
    dynamic latitude,
    dynamic longitude,
    String? address,
  }) {
    final hasCoordinates =
        latitude != null &&
            longitude != null;

    final cleanAddress =
        address?.trim();

    return Row(
      crossAxisAlignment:
          CrossAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 17,
          color: AppColors.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color:
                      AppColors.textSecondary,
                ),
              ),

              if (cleanAddress != null &&
                  cleanAddress.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  cleanAddress,
                  style: const TextStyle(
                    fontSize: 12,
                  ),
                ),
              ],

              if (hasCoordinates) ...[
                const SizedBox(height: 2),
                Text(
                  '${latitude.toString()}, ${longitude.toString()}',
                  style: const TextStyle(
                    fontSize: 10,
                    color:
                        AppColors.textSecondary,
                  ),
                ),
              ],

              if ((cleanAddress == null ||
                      cleanAddress.isEmpty) &&
                  !hasCoordinates)
                const Text(
                  'Location unavailable',
                  style: TextStyle(
                    fontSize: 11,
                    color:
                        AppColors.textSecondary,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ===========================================================================
  // TIME TILE
  // ===========================================================================

  Widget _timeTile({
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _saving ? null : onTap,
      borderRadius:
          BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius:
              BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.divider,
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 17,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: const TextStyle(
                    color:
                        AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// EDITABLE SESSION
// =============================================================================

class _EditableSession {
  String punchIn;
  String? punchOut;

  dynamic punchInLat;
  dynamic punchInLng;
  String? punchInAddress;

  dynamic punchOutLat;
  dynamic punchOutLng;
  String? punchOutAddress;

  _EditableSession({
    required this.punchIn,
    required this.punchOut,
    this.punchInLat,
    this.punchInLng,
    this.punchInAddress,
    this.punchOutLat,
    this.punchOutLng,
    this.punchOutAddress,
  });
}