import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Read-only attendance verification screen for admins reviewing ID, OD,
/// compensation and MIS-PUNCH requests.
class AdminEmployeeAttendanceViewScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final Set<String> focusDates;
  final Set<String> sourceOdDates;
  final String targetIdDate;

  const AdminEmployeeAttendanceViewScreen({
    super.key,
    required this.employeeId,
    this.employeeName = '',
    this.focusDates = const <String>{},
    this.sourceOdDates = const <String>{},
    this.targetIdDate = '',
  });

  @override
  State<AdminEmployeeAttendanceViewScreen> createState() =>
      _AdminEmployeeAttendanceViewScreenState();
}

class _AdminEmployeeAttendanceViewScreenState
    extends State<AdminEmployeeAttendanceViewScreen> {
  late final DatabaseReference dbRef;
  bool loading = true;
  String displayName = '';
  Map<String, Map<String, dynamic>> attendance = {};

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
    _load();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _string(dynamic value) => value?.toString().trim() ?? '';

  List<AttendanceSession> _sessions(Map<String, dynamic> record) {
    final result = <AttendanceSession>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (final item in raw) {
        final map = _map(item);
        if (_string(map['punchIn']).isNotEmpty) {
          result.add(
            AttendanceSession(
              punchIn: _string(map['punchIn']),
              punchOut: _string(map['punchOut']).isEmpty
                  ? null
                  : _string(map['punchOut']),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final map = _map(entry.value);
        if (_string(map['punchIn']).isNotEmpty) {
          result.add(
            AttendanceSession(
              punchIn: _string(map['punchIn']),
              punchOut: _string(map['punchOut']).isEmpty
                  ? null
                  : _string(map['punchOut']),
            ),
          );
        }
      }
    }

    if (result.isEmpty && _string(record['punchIn']).isNotEmpty) {
      result.add(
        AttendanceSession(
          punchIn: _string(record['punchIn']),
          punchOut: _string(record['punchOut']).isEmpty
              ? null
              : _string(record['punchOut']),
        ),
      );
    }

    return result;
  }

  bool _isWfh(Map<String, dynamic> record) {
    if (record['workFromHome'] == true) return true;
    final raw = record['sessions'];
    if (raw is List) {
      return raw.any((item) {
        final map = _map(item);
        return map['workFromHome'] == true ||
            _string(map['workLocationType']).toLowerCase() == 'work from home';
      });
    }
    if (raw is Map) {
      return raw.values.any((item) {
        final map = _map(item);
        return map['workFromHome'] == true ||
            _string(map['workLocationType']).toLowerCase() == 'work from home';
      });
    }
    return false;
  }

  bool _isMisPunch(Map<String, dynamic> record) {
    final status =
        _string(record['attendanceStatus'] ?? record['status']).toUpperCase();
    return status.contains('MIS-PUNCH') ||
        record['misPunch'] == true ||
        record['mis_punch'] == true;
  }

  AttendanceResult? _calculate(Map<String, dynamic> record) {
    final sessions = _sessions(record);
    if (sessions.isEmpty) return null;
    if (sessions.any((s) => s.punchOut == null || s.punchOut!.trim().isEmpty)) {
      return null;
    }

    final raw = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record['workFromHome'] == true,
    );

    final regularized =
        int.tryParse(record['regularizedMinutes']?.toString() ?? '') ??
            int.tryParse(record['compensatedMinutes']?.toString() ?? '') ??
            0;
    final odUsed =
        int.tryParse(record['odUsedMinutes']?.toString() ?? '') ??
            int.tryParse(record['overtimeUsedMinutes']?.toString() ?? '') ??
            0;

    final effectiveMinutes = (raw.netHours * 60).round() + regularized;
    final remainingExtra =
        ((raw.extraHours * 60).round() - odUsed).clamp(0, 1000000);

    if (effectiveMinutes >= AttendanceCalculator.requiredMinutes) {
      return AttendanceResult(
        dayType: DayType.fullDay,
        netHours: effectiveMinutes / 60.0,
        shortfallHours: 0,
        extraHours: remainingExtra / 60.0,
        label: 'Full Day',
      );
    }

    return AttendanceResult(
      dayType: DayType.workPending,
      netHours: effectiveMinutes / 60.0,
      shortfallHours:
          (AttendanceCalculator.requiredMinutes - effectiveMinutes) / 60.0,
      extraHours: 0,
      label: 'Work-Pending',
    );
  }

  String _statusFor(Map<String, dynamic>? record) {
    if (record == null) return 'ABSENT';
    if (_isMisPunch(record)) return 'MP — Mis-punch';

    final calculation = _calculate(record);
    if (calculation == null) return 'CHECKED IN';

    switch (calculation.dayType) {
      case DayType.fullDay:
        return calculation.extraHours > 0
            ? 'OD — Overtime duty'
            : 'Present';
      case DayType.workPending:
        return 'ID — Incomplete duty';
      case DayType.absent:
        return 'Absent';
    }
  }

  Color _statusColor(String status) {
    if (status.startsWith('OD')) return AppColors.primary;
    if (status.startsWith('ID')) return const Color(0xFF7A4DD8);
    if (status.startsWith('MP')) return AppColors.danger;
    if (status == 'Present') return AppColors.calendarPresentText;
    if (status == 'ABSENT') return AppColors.calendarAbsentText;
    return AppColors.warning;
  }

  Future<void> _load() async {
    try {
      final userSnap = await dbRef.child('users').child(widget.employeeId).get();
      final attendanceSnap =
          await dbRef.child('Attendance').child(widget.employeeId).get();

      final loaded = <String, Map<String, dynamic>>{};
      if (attendanceSnap.exists && attendanceSnap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(attendanceSnap.value as Map);
        for (final entry in raw.entries) {
          if (entry.value is Map) {
            loaded[entry.key.toString()] = _map(entry.value);
          }
        }
      }

      var name = widget.employeeName.trim();
      if (name.isEmpty && userSnap.exists && userSnap.value is Map) {
        name = _string(_map(userSnap.value)['name']);
      }

      if (!mounted) return;
      setState(() {
        displayName = name.isEmpty ? widget.employeeId : name;
        attendance = loaded;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load attendance: $e')),
      );
    }
  }

  String _time(dynamic value) => _string(value).isEmpty ? '—' : _string(value);

  @override
  Widget build(BuildContext context) {
    final dates = attendance.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Employee Attendance'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Employee ID: ${widget.employeeId}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                        if (widget.targetIdDate.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          _contextChip(
                            'ID to regularize',
                            widget.targetIdDate,
                            const Color(0xFF7A4DD8),
                          ),
                        ],
                        if (widget.sourceOdDates.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...widget.sourceOdDates.map(
                            (date) => _contextChip(
                              'OD source',
                              date,
                              AppColors.primary,
                            ),
                          ),
                        ],
                        if (widget.targetIdDate.isNotEmpty ||
                            widget.sourceOdDates.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          const Text(
                            'Verify the source OD and target ID using the actual attendance sessions before approving.',
                            style: TextStyle(
                              fontSize: 10,
                              color: AppColors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  if (dates.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('No attendance records.')),
                    )
                  else
                    ...dates.map((date) => _buildDay(date, attendance[date]!)),
                ],
              ),
            ),
    );
  }

  Widget _contextChip(String label, String date, Color color) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: color.withValues(alpha: .20)),
      ),
      child: Row(
        children: [
          Icon(Icons.flag_outlined, size: 16, color: color),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              '$label: $date',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDay(String date, Map<String, dynamic> record) {
    final status = _statusFor(record);
    final calculation = _calculate(record);
    final sessions = _sessions(record);
    final highlighted = widget.focusDates.contains(date);
    final isSource = widget.sourceOdDates.contains(date);
    final isTarget = widget.targetIdDate == date;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlighted ? AppColors.successLight : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: highlighted
              ? AppColors.primary.withValues(alpha: .45)
              : AppColors.divider,
          width: highlighted ? 1.4 : 1,
        ),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              if (isSource) _smallTag('OD SOURCE', AppColors.primary),
              if (isTarget)
                _smallTag('ID TARGET', const Color(0xFF7A4DD8)),
              const SizedBox(width: 5),
              _smallTag(status, _statusColor(status)),
            ],
          ),
          const SizedBox(height: 8),
          if (sessions.isEmpty)
            const Text(
              'No recorded session',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            )
          else
            ...sessions.asMap().entries.map(
                  (entry) => _sessionRow(entry.key + 1, entry.value),
                ),
          if (calculation != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Worked: ${AttendanceCalculator.formatHours(calculation.netHours)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (calculation.extraHours > 0)
                  Text(
                    'Remaining OD: ${AttendanceCalculator.formatHours(calculation.extraHours)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: AppColors.primary,
                    ),
                  )
                else if (calculation.shortfallHours > 0)
                  Text(
                    'ID shortfall: ${AttendanceCalculator.formatHours(calculation.shortfallHours)}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF7A4DD8),
                    ),
                  ),
              ],
            ),
          ],
          if (_isWfh(record)) ...[
            const SizedBox(height: 6),
            const Text(
              'Work From Home session included',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: AppColors.success,
              ),
            ),
          ],
          if (_string(record['address']).isNotEmpty ||
              _string(record['punchInAddress']).isNotEmpty ||
              _string(record['punchOutAddress']).isNotEmpty) ...[
            const SizedBox(height: 7),
            Text(
              'Location: ${_string(record['address']).isNotEmpty ? _string(record['address']) : _string(record['punchInAddress']).isNotEmpty ? _string(record['punchInAddress']) : _string(record['punchOutAddress'])}',
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          if (_string(record['odUsedMinutes']).isNotEmpty &&
              int.tryParse(record['odUsedMinutes'].toString()) != null &&
              int.parse(record['odUsedMinutes'].toString()) > 0) ...[
            const SizedBox(height: 5),
            Text(
              'OD already used: ${record['odUsedMinutes']} min',
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _smallTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }

  Widget _sessionRow(int index, AttendanceSession session) {
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Session $index',
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            '${_time(session.punchIn)} → ${_time(session.punchOut)}',
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
