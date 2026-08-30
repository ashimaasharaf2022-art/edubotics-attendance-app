import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Admin/Super Admin only editor for one employee's attendance day.
///
/// IMPORTANT:
/// - Employee HistoryScreen never opens this screen.
/// - HistoryScreen opens this screen only when viewerIsAdmin == true.
/// - Supports unlimited attendance sessions in one day.
/// - Also supports old single punchIn/punchOut records.
///
/// This constructor accepts BOTH:
///   date: '2026-08-26'
/// and:
///   initialDate: DateTime(2026, 8, 26)
///
/// This keeps it compatible with the existing screens in the project.
class AdminAttendanceEditorScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  /// Existing callers may pass the Firebase date key.
  final String? date;

  /// HistoryScreen may pass the DateTime of the tapped day.
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

  /// Firebase attendance date key.
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

    _recordRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    )
        .ref()
        .child('Attendance')
        .child(widget.employeeId)
        .child(_dateKey);

    _load();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }

    return <String, dynamic>{};
  }

  Future<void> _load() async {
    try {
      final snapshot = await _recordRef.get();

      _original = _map(snapshot.value);
      final raw = _original['sessions'];

      _sessions.clear();

      // New multiple-session format.
      if (raw is List) {
        for (final item in raw) {
          final session = _map(item);

          if (session['punchIn'] != null) {
            _sessions.add(
              _EditableSession(
                punchIn: session['punchIn'].toString(),
                punchOut: session['punchOut']?.toString(),
              ),
            );
          }
        }
      }

      // Firebase can sometimes return an indexed object/map.
      else if (raw is Map) {
        final entries = raw.entries.toList()
          ..sort(
            (a, b) => a.key.toString().compareTo(
                  b.key.toString(),
                ),
          );

        for (final entry in entries) {
          final session = _map(entry.value);

          if (session['punchIn'] != null) {
            _sessions.add(
              _EditableSession(
                punchIn: session['punchIn'].toString(),
                punchOut: session['punchOut']?.toString(),
              ),
            );
          }
        }
      }

      // Backward compatibility with old single-session records.
      if (_sessions.isEmpty && _original['punchIn'] != null) {
        _sessions.add(
          _EditableSession(
            punchIn: _original['punchIn'].toString(),
            punchOut: _original['punchOut']?.toString(),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        _showError('Could not load attendance: $e');
      }
    }

    if (mounted) {
      setState(() => _loading = false);
    }
  }

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
      var hour = int.tryParse(match.group(1)!) ?? 0;
      final minute = int.tryParse(match.group(2)!) ?? 0;
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
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
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
      initialTime: _timeOfDay(current, end: end),
      helpText: title,
    );

    if (picked == null) {
      return null;
    }

    return _formatTimeOfDay(picked);
  }

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

  bool _validate() {
    if (_sessions.isEmpty) {
      return true;
    }

    for (var i = 0; i < _sessions.length; i++) {
      final session = _sessions[i];

      final inMinutes = _minutes(session.punchIn);

      final outMinutes = session.punchOut == null
          ? null
          : _minutes(session.punchOut!);

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
            : _minutes(previous.punchOut!);

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

  Future<void> _save() async {
    if (_saving || !_validate()) {
      return;
    }

    setState(() => _saving = true);

    try {
      // If the admin removes every session, remove the attendance record.
      if (_sessions.isEmpty) {
        await _recordRef.remove();
      } else {
        final sessionMaps = _sessions
            .map(
              (session) => <String, dynamic>{
                'punchIn': session.punchIn,
                if (session.punchOut != null &&
                    session.punchOut!.isNotEmpty)
                  'punchOut': session.punchOut,
              },
            )
            .toList();

        final allClosed = _sessions.every(
          (session) =>
              session.punchOut != null &&
              session.punchOut!.isNotEmpty,
        );

        final firstIn = _sessions.first.punchIn;

        final lastOut =
            allClosed ? _sessions.last.punchOut : null;

        final update = <String, dynamic>{
          ..._original,

          'employeeId': widget.employeeId,
          'date': _dateKey,

          // New multi-session data.
          'sessions': sessionMaps,

          // Keep these legacy fields for existing reports/screens.
          'punchIn': firstIn,

          'manualEdited': true,
          'manualEditedBy': widget.adminId,
          'manualEditedByName': widget.adminName,
          'manualEditedAt':
              DateTime.now().toIso8601String(),

          'status': allClosed
              ? 'Checked Out'
              : 'Checked In',
        };

        if (lastOut != null) {
          update['punchOut'] = lastOut;

          update.remove('autoPunchOut');
          update.remove('approvedAutoCheckout');
        } else {
          update.remove('punchOut');
        }

        // Use the existing attendance calculator so the admin edit
        // follows the same working-hours / full-day / mis-punch rules.
        try {
          final calculatorSessions = sessionMaps
              .map(
                (session) => AttendanceSession(
                  punchIn: session['punchIn'].toString(),
                  punchOut:
                      session['punchOut']?.toString(),
                ),
              )
              .toList();

          final result =
              AttendanceCalculator.calculateFromSessions(
            calculatorSessions,
            workFromHome:
                update['workFromHome'] == true,
          );

          update['workingHours'] = result.netHours;
          update['attendanceStatus'] =
              result.dayType.name;
        } catch (_) {
          // The attendance record is still saved even if an
          // older calculator implementation lacks these fields.
        }

        await _recordRef.set(update);
      }

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

      // true tells HistoryScreen to reload the day/month data.
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        _showError('Could not save attendance: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _removeSession(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove session?'),
        content: Text(
          'Remove Session ${index + 1} from this attendance day?',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      setState(() {
        _sessions.removeAt(index);
      });
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _workingHoursPreview() {
    if (_sessions.isEmpty) {
      return '0 hr 0 min';
    }

    try {
      final result =
          AttendanceCalculator.calculateFromSessions(
        _sessions
            .map(
              (session) => AttendanceSession(
                punchIn: session.punchIn,
                punchOut: session.punchOut,
              ),
            )
            .toList(),
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

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('EEE, dd MMM yyyy').format(
      _selectedDate,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Edit Attendance'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check),
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
                              color:
                                  AppColors.primary,
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

                ..._sessions.asMap().entries.map(
                      (entry) => _sessionCard(
                        entry.key,
                        entry.value,
                      ),
                    ),

                const SizedBox(height: 8),

                OutlinedButton.icon(
                  onPressed:
                      _saving ? null : _addSession,
                  icon: const Icon(Icons.add),
                  label:
                      const Text('Add Session'),
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

                Container(
                  padding:
                      const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber
                        .withValues(alpha: .10),
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
                      foregroundColor:
                          Colors.white,
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

  Widget _sessionCard(
    int index,
    _EditableSession session,
  ) {
    return Container(
      margin:
          const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(14),
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
                onPressed: _saving
                    ? null
                    : () => _removeSession(
                          index,
                        ),
                icon: const Icon(
                  Icons.delete_outline,
                  color: Colors.red,
                ),
                tooltip: 'Remove session',
              ),
            ],
          ),

          const SizedBox(height: 4),

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
        ],
      ),
    );
  }

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
        padding:
            const EdgeInsets.all(12),
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

class _EditableSession {
  String punchIn;
  String? punchOut;

  _EditableSession({
    required this.punchIn,
    required this.punchOut,
  });
}
