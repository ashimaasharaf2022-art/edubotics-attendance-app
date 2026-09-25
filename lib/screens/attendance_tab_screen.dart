import 'dart:async';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/notification_center.dart';
import 'incomplete_duty_request_bottom_sheet.dart';
import 'mispunch_request_bottom_sheet.dart';
import 'overtime_compensation_bottom_sheet.dart';
import 'payroll_screen.dart';

class AttendanceTabScreen extends StatefulWidget {
  final String employeeId;

  const AttendanceTabScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<AttendanceTabScreen> createState() => _AttendanceTabScreenState();
}

class _AttendanceTabScreenState extends State<AttendanceTabScreen> {
  late final DatabaseReference dbRef;
  StreamSubscription<DatabaseEvent>? _attendanceSubscription;

  bool loading = true;
  Map<String, Map<String, dynamic>> attendanceData = {};
  List<Map<String, dynamic>> leaveRequests = [];

  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadAttendance();
    _startAttendanceListener();
  }

  void _startAttendanceListener() {
    _attendanceSubscription = dbRef
        .child('Attendance')
        .child(widget.employeeId)
        .onValue
        .listen((event) {
      if (!mounted) return;

      final loadedAttendance = <String, Map<String, dynamic>>{};
      final value = event.snapshot.value;

      if (value is Map) {
        final raw = Map<dynamic, dynamic>.from(value);
        for (final entry in raw.entries) {
          if (entry.value is Map) {
            loadedAttendance[entry.key.toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }

      setState(() {
        attendanceData = loadedAttendance;
        loading = false;
      });
    }, onError: (Object error) {
      debugPrint('Attendance realtime listener error: $error');
    });
  }

  @override
  void dispose() {
    _attendanceSubscription?.cancel();
    super.dispose();
  }

  String _dateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  DateTime _dayOnly(DateTime date) => DateTime(date.year, date.month, date.day);

  bool _sameDay(DateTime a, DateTime b) => _dayOnly(a) == _dayOnly(b);

  bool _isFuture(DateTime date) =>
      _dayOnly(date).isAfter(_dayOnly(DateTime.now()));

  bool _isToday(DateTime date) => _sameDay(date, DateTime.now());

  bool _isWeekday(DateTime date) =>
      date.weekday >= DateTime.monday && date.weekday <= DateTime.friday;

  String _shortDate(DateTime date) =>
      DateFormat('EEE, d MMM').format(date);

  String _timeText(String? value) {
    if (value == null || value.trim().isEmpty) return '—';
    return value;
  }

  Future<void> _loadAttendance() async {
    if (mounted) setState(() => loading = true);

    try {
      await _checkPreviousDayForMisPunch();

      final attendanceSnap = await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .get();

      final loadedAttendance = <String, Map<String, dynamic>>{};

      if (attendanceSnap.exists && attendanceSnap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(attendanceSnap.value as Map);

        for (final entry in raw.entries) {
          if (entry.value is Map) {
            loadedAttendance[entry.key.toString()] =
                Map<String, dynamic>.from(entry.value as Map);
          }
        }
      }

      final leaveSnap =
          await dbRef.child('LeaveRequests').child(widget.employeeId).get();

      final loadedLeaves = <Map<String, dynamic>>[];
      if (leaveSnap.exists && leaveSnap.value is Map) {
        final raw = Map<dynamic, dynamic>.from(leaveSnap.value as Map);

        for (final entry in raw.entries) {
          if (entry.value is Map) {
            final request = Map<String, dynamic>.from(entry.value as Map);
            request['_id'] = entry.key.toString();
            loadedLeaves.add(request);
          }
        }
      }

      if (!mounted) return;

      setState(() {
        attendanceData = loadedAttendance;
        leaveRequests = loadedLeaves;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        attendanceData = {};
        leaveRequests = [];
        loading = false;
      });
    }
  }

  Future<void> _checkPreviousDayForMisPunch() async {
    try {
      final attendanceRef =
          dbRef.child('Attendance').child(widget.employeeId);
      final snapshot = await attendanceRef.get();

      if (!snapshot.exists || snapshot.value is! Map) return;

      final records = Map<dynamic, dynamic>.from(snapshot.value as Map);
      final todayKey = _dateKey(DateTime.now());

      for (final entry in records.entries) {
        final dateKey = entry.key.toString();
        if (dateKey == todayKey || entry.value is! Map) continue;

        final parsedDate = DateTime.tryParse(dateKey);
        if (parsedDate != null && !_isWeekday(parsedDate)) continue;

        final record = Map<dynamic, dynamic>.from(entry.value as Map);
        final status = record['status']?.toString().toUpperCase();

        if (status != 'CHECKED IN') continue;

        final punchIn = record['punchIn']?.toString();
        if (punchIn == null || punchIn.trim().isEmpty) continue;

        final topPunchOut = record['punchOut']?.toString();
        if (topPunchOut != null && topPunchOut.trim().isNotEmpty) continue;

        final sessions = _sessionsFromRecord(record);
        if (sessions.isEmpty) continue;

        final lastPunchOut = sessions.last.punchOut?.trim();
        if (lastPunchOut != null && lastPunchOut.isNotEmpty) continue;

        await attendanceRef.child(dateKey).update({
          'status': 'MIS-PUNCH',
          'misPunch': true,
          'temporaryPunchOut': AttendanceCalculator.autoCheckoutTime,
          'misPunchDetectedAt': DateTime.now().toIso8601String(),
          'punchoutRequestStatus': 'not_requested',
          'attendanceStatus': 'MIS-PUNCH — awaiting admin correction',
        });
      }
    } catch (_) {
      // Attendance should still open if this optional workflow fails.
    }
  }

  List<AttendanceSession> _sessionsFromRecord(Map data) {
    final sessions = <AttendanceSession>[];
    final raw = data['sessions'];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['punchIn'] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item['punchIn'].toString(),
              punchOut: item['punchOut']?.toString(),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));

      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item['punchIn'] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item['punchIn'].toString(),
              punchOut: item['punchOut']?.toString(),
            ),
          );
        }
      }
    }

    if (sessions.isEmpty && data['punchIn'] != null) {
      sessions.add(
        AttendanceSession(
          punchIn: data['punchIn'].toString(),
          punchOut: data['punchOut']?.toString(),
        ),
      );
    }

    return sessions;
  }

  List<Map<String, dynamic>> _sessionMapsFromRecord(
    Map<String, dynamic> data,
  ) {
    final result = <Map<String, dynamic>>[];
    final raw = data['sessions'];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['punchIn'] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort(
          (a, b) => a.key.toString().compareTo(b.key.toString()),
        );

      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item['punchIn'] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    }

    // Backward compatibility for old single-session records.
    if (result.isEmpty && data['punchIn'] != null) {
      result.add({
        'punchIn': data['punchIn'],
        if (data['punchOut'] != null) 'punchOut': data['punchOut'],
        'workFromHome': data['workFromHome'] == true,
        if (data['workFromHome'] == true)
          'workLocationType': 'Work From Home',
      });
    }

    return result;
  }

  bool _sessionIsWfh(Map<String, dynamic> session) {
    return session['workFromHome'] == true ||
        session['workLocationType']?.toString().toLowerCase() ==
            'work from home';
  }

  bool _isMisPunch(Map<String, dynamic> data) {
    final status = data['status']?.toString().toUpperCase();
    return status == 'MIS-PUNCH' ||
        data['misPunch'] == true ||
        data['mis_punch'] == true ||
        status == 'AUTO CHECKOUT PENDING' ||
        data['autoPunchOut'] == true;
  }

  DayType? _classify(String dateKey, Map<String, dynamic> data) {
    if (_isMisPunch(data)) return null;

    final sessions = _sessionsFromRecord(data);

    if (sessions.isNotEmpty) {
      final hasOpenSession = sessions.any(
        (s) => s.punchOut == null || s.punchOut!.trim().isEmpty,
      );

      if (hasOpenSession) {
        return _isToday(DateTime.parse(dateKey)) ? null : DayType.absent;
      }

      return AttendanceCalculator.calculateFromSessions(
        sessions,
        workFromHome: data['workFromHome'] == true,
      ).dayType;
    }

    final punchIn = data['punchIn']?.toString();
    final punchOut = data['punchOut']?.toString();

    if (punchIn == null || punchIn.trim().isEmpty) {
      return DayType.absent;
    }

    if (punchOut == null || punchOut.trim().isEmpty) {
      return _isToday(DateTime.parse(dateKey)) ? null : DayType.absent;
    }

    return AttendanceCalculator.calculate(
      punchIn: punchIn,
      punchOut: punchOut,
      workFromHome: data['workFromHome'] == true,
    ).dayType;
  }

  int _intValue(dynamic value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  AttendanceResult? _calculationFor(Map<String, dynamic> data) {
    final sessions = _sessionsFromRecord(data);
    if (sessions.isEmpty) return null;

    final hasOpenSession = sessions.any(
      (s) => s.punchOut == null || s.punchOut!.trim().isEmpty,
    );
    if (hasOpenSession) return null;

    final raw = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: data['workFromHome'] == true,
    );

    // Admin-approved compensation is represented on the attendance record.
    // It does not rewrite the original punch sessions.
    final regularizedMinutes = _intValue(
      data['regularizedMinutes'] ?? data['compensatedMinutes'],
    );
    final odUsedMinutes = _intValue(
      data['odUsedMinutes'] ?? data['overtimeUsedMinutes'],
    );

    if (regularizedMinutes <= 0 && odUsedMinutes <= 0) {
      return raw;
    }

    final rawMinutes = (raw.netHours * 60).round();
    final effectiveMinutes = rawMinutes + regularizedMinutes;
    final effectiveExtraMinutes = (raw.extraHours * 60).round() - odUsedMinutes;

    if (effectiveMinutes >= AttendanceCalculator.requiredMinutes) {
      return AttendanceResult(
        dayType: DayType.fullDay,
        netHours: effectiveMinutes / 60.0,
        shortfallHours: 0,
        extraHours: effectiveExtraMinutes > 0
            ? effectiveExtraMinutes / 60.0
            : 0,
        label: data['workFromHome'] == true
            ? 'Full Day (WFH)'
            : 'Full Day',
      );
    }

    final shortfallMinutes =
        AttendanceCalculator.requiredMinutes - effectiveMinutes;

    return AttendanceResult(
      dayType: DayType.workPending,
      netHours: effectiveMinutes / 60.0,
      shortfallHours: shortfallMinutes / 60.0,
      extraHours: 0,
      label: data['workFromHome'] == true
          ? 'Work-Pending (WFH)'
          : 'Work-Pending',
    );
  }

  List<_IncompleteDutyBalance> _activeIncompleteDuties() {
    final result = <_IncompleteDutyBalance>[];

    for (final entry in attendanceData.entries) {
      final date = entry.key;
      final data = entry.value;

      final parsedDate = DateTime.tryParse(date);
      if (parsedDate != null && !_isWeekday(parsedDate)) continue;

      if (_isMisPunch(data)) continue;

      final calculation = _calculationFor(data);
      if (calculation == null || calculation.shortfallHours <= 0) continue;

      result.add(
        _IncompleteDutyBalance(
          date: date,
          shortfallMinutes: (calculation.shortfallHours * 60).round(),
        ),
      );
    }

    result.sort(
      (a, b) => a.shortfallMinutes.compareTo(b.shortfallMinutes),
    );
    return result;
  }

  int _availableOvertimeMinutes() {
    var total = 0;

    for (final entry in attendanceData.entries) {
      final parsedDate = DateTime.tryParse(entry.key);
      if (parsedDate != null && !_isWeekday(parsedDate)) continue;

      final data = entry.value;
      if (_isMisPunch(data)) continue;

      final calculation = _calculationFor(data);
      if (calculation == null || calculation.extraHours <= 0) continue;

      final remaining = (calculation.extraHours * 60).round();
      if (remaining > 0) total += remaining;
    }

    return total;
  }

  bool _leaveCovers(DateTime date) {
    final target = _dayOnly(date);

    for (final request in leaveRequests) {
      final status = request['status']?.toString().toLowerCase();
      if (status != 'approved') continue;

      final from = DateTime.tryParse(request['fromDate']?.toString() ?? '');
      final to = DateTime.tryParse(request['toDate']?.toString() ?? '');
      if (from == null || to == null) continue;

      final start = _dayOnly(from);
      final end = _dayOnly(to);

      if (!target.isBefore(start) && !target.isAfter(end)) {
        return true;
      }
    }

    return false;
  }

  _DayStatus _statusFor(DateTime date) {
    // Saturday and Sunday are weekly off days.
    // They must never become Present, Absent, Leave, ID, OD or Mis-punch.
    if (!_isWeekday(date)) return _DayStatus.none;

    if (_isFuture(date)) return _DayStatus.none;

    if (_leaveCovers(date)) return _DayStatus.leave;

    final key = _dateKey(date);
    final data = attendanceData[key];

    if (data == null) {
      if (_isToday(date) || !_isWeekday(date)) {
        return _DayStatus.none;
      }
      return _DayStatus.absent;
    }

    if (_isMisPunch(data)) return _DayStatus.misPunch;

    final calculation = _calculationFor(data);
    if (calculation == null) {
      return _isToday(date) ? _DayStatus.none : _DayStatus.absent;
    }

    switch (calculation.dayType) {
      case DayType.fullDay:
        return calculation.extraHours > 0
            ? _DayStatus.overtime
            : _DayStatus.present;
      case DayType.workPending:
        return _DayStatus.incomplete;
      case DayType.absent:
        return _DayStatus.absent;
    }
  }

  String _statusLabel(_DayStatus status) {
    switch (status) {
      case _DayStatus.present:
        return 'Present';
      case _DayStatus.absent:
        return 'Absent';
      case _DayStatus.leave:
        return 'Leave';
      case _DayStatus.incomplete:
        return 'Incomplete duty';
      case _DayStatus.overtime:
        return 'Overtime duty';
      case _DayStatus.misPunch:
        return 'Mis-punch';
      case _DayStatus.none:
        return '';
    }
  }

  Color _statusColor(_DayStatus status) {
    switch (status) {
      case _DayStatus.present:
        return AppColors.calendarPresentText;
      case _DayStatus.absent:
        return AppColors.calendarAbsentText;
      case _DayStatus.leave:
        return AppColors.calendarLeaveText;
      case _DayStatus.incomplete:
        return const Color(0xFF7A4DD8);
      case _DayStatus.overtime:
        return AppColors.primary;
      case _DayStatus.misPunch:
        return AppColors.danger;
      case _DayStatus.none:
        return AppColors.textSecondary;
    }
  }

  List<DateTime> _monthDays() {
    final first = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final count =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0).day;

    return List.generate(
      count,
      (index) => DateTime(selectedMonth.year, selectedMonth.month, index + 1),
    );
  }

  List<DateTime> _activityDays() {
    final now = _dayOnly(DateTime.now());
    return _monthDays()
        .where(
          (date) =>
              !date.isAfter(now) &&
              _statusFor(date) != _DayStatus.none,
        )
        .toList()
      ..sort((a, b) => b.compareTo(a));
  }

  _Summary _summary() {
    int present = 0;
    int absent = 0;
    int leave = 0;
    int incomplete = 0;
    int overtime = 0;
    int misPunch = 0;

    for (final date in _monthDays()) {
      final status = _statusFor(date);
      switch (status) {
        case _DayStatus.present:
          present++;
          break;
        case _DayStatus.absent:
          absent++;
          break;
        case _DayStatus.leave:
          leave++;
          break;
        case _DayStatus.incomplete:
          incomplete++;
          break;
        case _DayStatus.overtime:
          overtime++;
          break;
        case _DayStatus.misPunch:
          misPunch++;
          break;
        case _DayStatus.none:
          break;
      }
    }

    return _Summary(
      present: present,
      absent: absent,
      leave: leave,
      incomplete: incomplete,
      overtime: overtime,
      misPunch: misPunch,
    );
  }

  void _changeMonth(int delta) {
    final next = DateTime(
      selectedMonth.year,
      selectedMonth.month + delta,
    );

    setState(() {
      selectedMonth = next;
      if (selectedDate.year != next.year ||
          selectedDate.month != next.month) {
        selectedDate = DateTime(next.year, next.month, 1);
      }
    });
  }

  void _selectDate(DateTime date) {
    if (_isFuture(date) || !_isWeekday(date)) return;

    setState(() {
      selectedDate = date;
      selectedMonth = DateTime(date.year, date.month);
    });

    _showDayDetails(date);
  }

  Widget _buildTopBar() {
    return const SizedBox.shrink();
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Text(
            'Attendance',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
              height: 1.1,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Your monthly record and compensation requests.',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSwitcher() {
    final months = List.generate(
      5,
      (index) => DateTime(
        selectedMonth.year,
        selectedMonth.month - 2 + index,
      ),
    );

    return SizedBox(
      height: 48,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        scrollDirection: Axis.horizontal,
        itemCount: months.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (_, index) {
          final month = months[index];
          final selected = month.year == selectedMonth.year &&
              month.month == selectedMonth.month;

          return GestureDetector(
            onTap: () {
              setState(() {
                selectedMonth = DateTime(month.year, month.month);
                if (selectedDate.year != month.year ||
                    selectedDate.month != month.month) {
                  selectedDate = DateTime(month.year, month.month, 1);
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? AppColors.green : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                DateFormat('MMM yyyy').format(month),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: selected
                      ? Colors.white
                      : AppColors.mutedText,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCalendar() {
    final days = _monthDays();
    // Calendar header is Sunday -> Saturday.
    // Dart's DateTime.weekday is Monday=1 ... Sunday=7.
    // Convert to Sunday-first index: Sunday=0 ... Saturday=6.
    final firstWeekday = days.first.weekday % 7;
    final cells = <DateTime?>[
      ...List<DateTime?>.filled(firstWeekday, null),
      ...days,
    ];

    while (cells.length % 7 != 0) {
      cells.add(null);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      padding: const EdgeInsets.fromLTRB(13, 14, 13, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat('MMMM yyyy').format(selectedMonth),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              _circleButton(
                Icons.chevron_left_rounded,
                () => _changeMonth(-1),
              ),
              const SizedBox(width: 7),
              _circleButton(
                Icons.chevron_right_rounded,
                () => _changeMonth(1),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: ['S', 'M', 'T', 'W', 'T', 'F', 'S']
                .map(
                  (label) => Expanded(
                    child: Center(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w700,
                          color: AppColors.mutedText,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: cells.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisExtent: 37,
            ),
            itemBuilder: (_, index) {
              final date = cells[index];
              if (date == null) return const SizedBox.shrink();

              final status = _statusFor(date);
              final selected = _sameDay(date, selectedDate);
              final today = _isToday(date);
              final future = _isFuture(date);

              final bg = selected
                  ? AppColors.calendarTodayFill
                  : status == _DayStatus.none
                      ? Colors.transparent
                      : Colors.transparent;

              return GestureDetector(
                onTap: future ? null : () => _selectDate(date),
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 1.5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(9),
                    border: today
                        ? Border.all(
                            color: AppColors.calendarTodayBorder,
                            width: 1,
                          )
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: selected || today
                              ? FontWeight.w900
                              : FontWeight.w700,
                          color: future
                              ? AppColors.mutedText.withOpacity(.45)
                              : AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      if (status != _DayStatus.none)
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: _statusColor(status),
                            shape: BoxShape.circle,
                          ),
                        )
                      else
                        const SizedBox(height: 4),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 9),
          Wrap(
            spacing: 11,
            runSpacing: 6,
            children: [
              _legendDot(
                AppColors.calendarPresentText,
                'Present',
              ),
              _legendDot(
                AppColors.calendarAbsentText,
                'Absent',
              ),
              _legendDot(
                AppColors.calendarLeaveText,
                'Leave',
              ),
              _legendDot(
                const Color(0xFF7A4DD8),
                'Incomplete',
              ),
              _legendDot(
                AppColors.primary,
                'Overtime',
              ),
              _legendDot(
                AppColors.danger,
                'Mis-punch',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 25,
        height: 25,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.background,
          border: Border.all(color: AppColors.divider),
        ),
        child: Icon(
          icon,
          size: 14,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildSummary() {
    final summary = _summary();
    final total =
        summary.present +
        summary.absent +
        summary.leave +
        summary.incomplete +
        summary.overtime +
        summary.misPunch;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Summary',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 11),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  if (summary.present > 0)
                    Expanded(
                      flex: summary.present,
                      child: Container(
                        color: AppColors.calendarPresentText,
                      ),
                    ),
                  if (summary.absent > 0)
                    Expanded(
                      flex: summary.absent,
                      child: Container(
                        color: AppColors.calendarAbsentText,
                      ),
                    ),
                  if (summary.leave > 0)
                    Expanded(
                      flex: summary.leave,
                      child: Container(
                        color: AppColors.calendarLeaveText,
                      ),
                    ),
                  if (summary.incomplete > 0)
                    Expanded(
                      flex: summary.incomplete,
                      child: Container(
                        color: const Color(0xFF7A4DD8),
                      ),
                    ),
                  if (summary.overtime > 0)
                    Expanded(
                      flex: summary.overtime,
                      child: Container(
                        color: AppColors.primary,
                      ),
                    ),
                  if (summary.misPunch > 0)
                    Expanded(
                      flex: summary.misPunch,
                      child: Container(
                        color: AppColors.danger,
                      ),
                    ),
                  if (total == 0)
                    Expanded(
                      child: Container(
                        color: AppColors.lightGrey,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _summaryRow(
            AppColors.calendarPresentText,
            'Present',
            summary.present,
          ),
          _summaryRow(
            AppColors.calendarAbsentText,
            'Absent',
            summary.absent,
          ),
          _summaryRow(
            AppColors.calendarLeaveText,
            'Leave',
            summary.leave,
          ),
          _summaryRow(
            const Color(0xFF7A4DD8),
            'Incomplete duty',
            summary.incomplete,
          ),
          _summaryRow(
            AppColors.primary,
            'Overtime duty',
            summary.overtime,
          ),
          _summaryRow(
            AppColors.danger,
            'Mis-punch',
            summary.misPunch,
            last: true,
          ),
        ],
      ),
    );
  }

  Widget _summaryRow(
    Color color,
    String label,
    int value, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(
                bottom: BorderSide(color: AppColors.divider),
              ),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            '$value',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }


  Widget _buildPayrollButton() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PayrollScreen(
                  employeeId: widget.employeeId,
                ),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Ink(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: AppColors.successLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.success.withValues(alpha: .18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: .18),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 25,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 13),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Payroll',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'View salary, payslips and payroll details.',
                        style: TextStyle(
                          fontSize: 9.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 13,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyActivity() {
    final days = _activityDays();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Daily activity',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 9),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              ),
            )
          else if (days.isEmpty)
            _emptyActivity()
          else
            ...days.map(_buildActivityCard),
        ],
      ),
    );
  }

  Widget _emptyActivity() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: const Text(
        'No attendance activity for this month yet.',
        style: TextStyle(
          fontSize: 11,
          color: AppColors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildActivityCard(DateTime date) {
    final status = _statusFor(date);
    final key = _dateKey(date);
    final data = attendanceData[key];

    final calculation =
        data == null ? null : _calculationFor(data);

    final sessionMaps =
        data == null ? <Map<String, dynamic>>[] : _sessionMapsFromRecord(data);
    final hasWfhSession =
        sessionMaps.any(_sessionIsWfh);

    final isOvertime =
        status == _DayStatus.overtime &&
        calculation != null &&
        calculation.extraHours > 0;

    final statusColor = _statusColor(status);

    String checkIn = '—';
    String checkOut = '—';
    String total = '—';

    if (data != null) {
      final sessions = _sessionsFromRecord(data);
      if (sessions.isNotEmpty) {
        checkIn = _timeText(sessions.first.punchIn);
        checkOut = _timeText(sessions.last.punchOut);
      }

      if (calculation != null) {
        total = AttendanceCalculator.formatHours(
          calculation.netHours,
        ).replaceFirst(' hr ', 'h ').replaceFirst(' min', 'm');
      } else if (_isToday(date)) {
        total = 'In progress';
      }
    }

    if (status == _DayStatus.leave) {
      checkIn = '—';
      checkOut = '—';
      total = '0h 00m';
    }

    return GestureDetector(
      onTap: () => _showDayDetails(date),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.divider),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      color: statusColor,
                    ),
                  ),
                ),
                if (hasWfhSession)
                  _statusBadge(
                    'WFH',
                    AppColors.successLight,
                    AppColors.success,
                    marginRight: 5,
                  ),
                if (status == _DayStatus.incomplete)
                  _statusBadge(
                    'ID',
                    const Color(0xFFF0E8FF),
                    const Color(0xFF7A4DD8),
                    marginRight: 5,
                  ),
                if (isOvertime)
                  _statusBadge(
                    'OT',
                    const Color(0xFFF0E8FF),
                    const Color(0xFF7A4DD8),
                    marginRight: 5,
                  ),
                if (status == _DayStatus.misPunch)
                  _statusBadge(
                    'MP',
                    AppColors.danger.withValues(alpha: .10),
                    AppColors.danger,
                    marginRight: 5,
                  ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 17,
                  color: AppColors.mutedText,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _shortDate(date),
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.mutedText,
                    ),
                  ),
                ),
                if (isOvertime)
                  Text(
                    '+${AttendanceCalculator.formatHours(calculation!.extraHours)}',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _activityTime('Check in', checkIn),
                _activityTime('Check out', checkOut),
                const Spacer(),
                Text(
                  total,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
            if (hasWfhSession) ...[
              const SizedBox(height: 7),
              Align(
                alignment: Alignment.centerLeft,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.home_work_outlined,
                      size: 12,
                      color: AppColors.success,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Work From Home session included',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(
    String label,
    Color background,
    Color foreground, {
    double marginRight = 0,
  }) {
    return Container(
      margin: EdgeInsets.only(right: marginRight),
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w900,
          color: foreground,
        ),
      ),
    );
  }

  Widget _activityTime(String label, String value) {
    return SizedBox(
      width: 78,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 7,
              color: AppColors.mutedText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showDayDetails(DateTime date) async {
    if (!_isWeekday(date)) return;

    final status = _statusFor(date);
    final data = attendanceData[_dateKey(date)];
    final calculation = data == null ? null : _calculationFor(data);
    final dateKey = _dateKey(date);
    final existingRequest = await _findExistingRequest(dateKey);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.48),
      builder: (_) => _DayDetailsSheet(
        date: date,
        status: status,
        data: data,
        calculation: calculation,
        requestAlreadySent: existingRequest != null,
        requestLabel: existingRequest == null
            ? null
            : _requestTypeLabel(existingRequest['requestType']?.toString()),
        onDeleteRequest: existingRequest != null &&
                existingRequest['canDelete'] == true
            ? () => _deleteExistingRequest(existingRequest, dateKey)
            : null,
        onRequestIncompleteDuty:
            existingRequest == null &&
                    status == _DayStatus.incomplete &&
                    calculation != null
                ? () {
                Navigator.pop(context);
                _showIncompleteDutyRequest(date, calculation);
              }
            : null,
        onRequestMispunch:
            existingRequest == null &&
                    status == _DayStatus.misPunch &&
                    data != null
                ? () {
                Navigator.pop(context);
                _showMispunchRequest(date, data);
              }
            : null,
        onRequestOvertime:
            existingRequest == null &&
                    status == _DayStatus.overtime &&
                    calculation != null &&
                    calculation.extraHours > 0
                ? () {
                Navigator.pop(context);
                _showOvertimeRequest(date, calculation);
              }
            : null,
      ),
    );
  }

  String _requestTypeLabel(String? type) {
    switch (type) {
      case 'incomplete_duty':
        return 'Incomplete duty request';
      case 'overtime':
        return 'Overtime compensation request';
      case 'mis_punch':
        return 'Mis-punch request';
      default:
        return 'Attendance request';
    }
  }

  String _punchTimeForDate(
    DateTime date, {
    required bool first,
  }) {
    final data = attendanceData[_dateKey(date)];
    if (data == null) return '—';

    final sessions = _sessionsFromRecord(data);
    if (sessions.isEmpty) return '—';

    return first
        ? _timeText(sessions.first.punchIn)
        : _timeText(sessions.last.punchOut);
  }

  Future<String> _employeeName() async {
    final snap = await dbRef.child('users').child(widget.employeeId).get();
    if (snap.exists && snap.value is Map) {
      final map = Map<dynamic, dynamic>.from(snap.value as Map);
      final name = map['name']?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return widget.employeeId;
  }

  Future<Map<String, dynamic>?> _findExistingRequest(
    String date,
  ) async {
    // A request locks the date until the employee explicitly deletes it.
    // We check both compensation requests and punch-out requests because
    // ID/OD/MP requests must never be stacked on top of one another.
    final compensationSnap = await dbRef
        .child('CompensationRequests')
        .child(widget.employeeId)
        .get();

    if (compensationSnap.exists && compensationSnap.value is Map) {
      final requests =
          Map<dynamic, dynamic>.from(compensationSnap.value as Map);

      for (final entry in requests.entries) {
        if (entry.value is! Map) continue;

        final request = Map<String, dynamic>.from(
          Map<dynamic, dynamic>.from(entry.value as Map),
        );

        final requestDate = request['date']?.toString() ?? '';
        final targetDate = request['targetDate']?.toString() ?? '';
        final selectedDates = request['selectedDates'];

        final matchesDate =
            requestDate == date ||
            targetDate == date ||
            (selectedDates is List &&
                selectedDates.map((e) => e.toString()).contains(date));

        if (!matchesDate) continue;

        final requestStatus =
            request['status']?.toString().toLowerCase() ?? 'pending';

        return {
          'node': 'CompensationRequests',
          'id': entry.key.toString(),
          'status': requestStatus,
          'requestType': request['requestType']?.toString() ?? 'compensation',
          'canDelete': requestStatus == 'pending' ||
              requestStatus == 'returned' ||
              requestStatus == 'rejected',
          'record': request,
        };
      }
    }

    final punchSnap = await dbRef
        .child('PunchRequests')
        .child(widget.employeeId)
        .child(date)
        .get();

    if (punchSnap.exists && punchSnap.value is Map) {
      final request =
          Map<String, dynamic>.from(
            Map<dynamic, dynamic>.from(punchSnap.value as Map),
          );

      final requestStatus =
          request['status']?.toString().toLowerCase() ?? 'pending';

      return {
        'node': 'PunchRequests',
        'id': date,
        'status': requestStatus,
        'requestType': 'mis_punch',
        'canDelete': requestStatus == 'pending' ||
            requestStatus == 'returned' ||
            requestStatus == 'rejected',
        'record': request,
      };
    }

    return null;
  }

  Future<void> _deleteExistingRequest(
    Map<String, dynamic> requestInfo,
    String date,
  ) async {
    try {
      final node = requestInfo['node']?.toString();

      if (node == 'CompensationRequests') {
        final requestId = requestInfo['id']?.toString();
        if (requestId == null || requestId.isEmpty) return;

        await dbRef
            .child('CompensationRequests')
            .child(widget.employeeId)
            .child(requestId)
            .remove();
      } else if (node == 'PunchRequests') {
        await dbRef
            .child('PunchRequests')
            .child(widget.employeeId)
            .child(date)
            .remove();

        // Clear only the request marker. Do not change the attendance
        // classification or punch data itself.
        await dbRef
            .child('Attendance')
            .child(widget.employeeId)
            .child(date)
            .update({
          'punchoutRequestStatus': 'not_requested',
        });
      }

      if (!mounted) return;
      Navigator.pop(context);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Request deleted. You can submit a new request.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not delete request: $e')),
      );
    }
  }

  Future<void> _showIncompleteDutyRequest(
    DateTime date,
    AttendanceResult calculation,
  ) async {
    final dateKey = _dateKey(date);

    final existingRequest = await _findExistingRequest(dateKey);
    if (existingRequest != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request already sent.')),
      );
      return;
    }

    final name = await _employeeName();
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.48),
      builder: (_) => IncompleteDutyRequestBottomSheet(
        employeeId: widget.employeeId,
        employeeName: name,
        date: dateKey,
        workedHours: AttendanceCalculator.formatHours(calculation.netHours),
        shortfallMinutes: (calculation.shortfallHours * 60).round(),
      ),
    );

    if (result == null) return;

    try {
      final requestRef = dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .push();

      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': name,
        'requestType': 'incomplete_duty',
        'date': dateKey,
        'selectedDates': [dateKey],
        'workedMinutes': (calculation.netHours * 60).round(),
        'shortfallMinutes': (calculation.shortfallHours * 60).round(),
        'reason': result['reason']?.toString() ?? '',
        'message': result['reason']?.toString() ?? '',
        'compensationDayMessage':
            result['compensationDayMessage']?.toString() ?? '',
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });

      await NotificationCenter.sendAdmin(
        title: 'Incomplete Duty Reason',
        message:
            '$name submitted an incomplete-duty reason for $dateKey.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Incomplete-duty reason sent to admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send request: $e')),
      );
    }
  }

  Future<void> _showMispunchRequest(
    DateTime date,
    Map<String, dynamic> data,
  ) async {
    final dateKey = _dateKey(date);
    final requestRef = dbRef
        .child('PunchRequests')
        .child(widget.employeeId)
        .child(dateKey);

    final existingRequest = await _findExistingRequest(dateKey);
    if (existingRequest != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request already sent.')),
      );
      return;
    }

    final name = await _employeeName();
    if (!mounted) return;

    final sessions = _sessionsFromRecord(data);
    final punchIn = sessions.isEmpty ? '—' : sessions.first.punchIn;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.48),
      builder: (_) => MispunchRequestBottomSheet(
        employeeId: widget.employeeId,
        employeeName: name,
        date: dateKey,
        punchIn: punchIn,
      ),
    );

    if (result == null) return;

    try {
      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': name,
        'date': dateKey,
        'type': 'mis_punch',
        'status': 'pending',
        'punchIn': punchIn,
        'actualPunchOutRequested': result['actualPunchOut']?.toString() ?? '',
        'message': result['message']?.toString() ?? '',
        'createdAt': DateTime.now().toIso8601String(),
        'requestedAt': DateTime.now().toIso8601String(),
      });

      await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .child(dateKey)
          .update({
        'punchoutRequestStatus': 'pending',
      });

      await NotificationCenter.sendAdmin(
        title: 'MIS-PUNCH Correction Request',
        message:
            '$name requested punch-out correction for $dateKey.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Punch-out request sent to admin.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send punch-out request: $e')),
      );
    }
  }

  Future<void> _showOvertimeRequest(
    DateTime date,
    AttendanceResult calculation,
  ) async {
    final incompleteDuties = _activeIncompleteDuties()
        .map(
          (item) => IncompleteDutyOption(
            date: item.date,
            shortfallMinutes: item.shortfallMinutes,
          ),
        )
        .toList();

    final availableOvertimeMinutes = _availableOvertimeMinutes();

    final existingRequest = await _findExistingRequest(_dateKey(date));
    if (existingRequest != null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request already sent.')),
      );
      return;
    }

    final name = await _employeeName();
    if (!mounted) return;

    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.48),
      builder: (_) => OvertimeCompensationBottomSheet(
        employeeId: widget.employeeId,
        employeeName: name,
        date: _dateKey(date),
        calculation: calculation,
        availableOvertimeMinutes: availableOvertimeMinutes,
        incompleteDuties: incompleteDuties,
      ),
    );

    if (result == null) return;

    final selectedDates =
        (result['selectedDates'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            <String>[];

    final targetDate = result['targetDate']?.toString() ?? '';
    final datesToLock = <String>{
      _dateKey(date),
      ...selectedDates,
      if (targetDate.isNotEmpty) targetDate,
    };

    for (final selectedDate in datesToLock) {
      final existingTarget = await _findExistingRequest(selectedDate);
      if (existingTarget != null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Request already sent for $selectedDate. Delete that request before submitting another one.',
            ),
          ),
        );
        return;
      }
    }

    try {
      final requestRef = dbRef
          .child('CompensationRequests')
          .child(widget.employeeId)
          .push();

      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName': name,
        'requestType': 'overtime',
        'date': _dateKey(date),
        'selectedDates': selectedDates.isEmpty ? [_dateKey(date)] : selectedDates,
        'requestedMinutes': result['requestedMinutes'] ?? 0,
        'overtimeMinutes': (calculation.extraHours * 60).round(),
        'availableOvertimeMinutes': availableOvertimeMinutes,
        'compensationType': result['compensationType']?.toString() ?? '',
        'targetDate': result['targetDate']?.toString() ?? '',
        'reason': result['reason']?.toString() ?? '',
        'message': result['reason']?.toString() ?? '',
        'status': 'pending',
        'requestedAt': DateTime.now().toIso8601String(),
        'createdAt': DateTime.now().toIso8601String(),
      });

      await NotificationCenter.sendAdmin(
        title: 'Overtime Compensation Request',
        message:
            '$name submitted ${result['compensationType']} for ${_dateKey(date)}.',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Overtime compensation request submitted.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit request: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _loadAttendance,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _buildTopBar()),
              SliverToBoxAdapter(child: _buildHeader()),
              SliverToBoxAdapter(child: _buildMonthSwitcher()),
              SliverToBoxAdapter(child: _buildCalendar()),
              SliverToBoxAdapter(child: _buildSummary()),
              SliverToBoxAdapter(child: _buildPayrollButton()),
              SliverToBoxAdapter(child: _buildDailyActivity()),
            ],
          ),
        ),
      ),
    );
  }
}

enum _DayStatus {
  present,
  absent,
  leave,
  incomplete,
  overtime,
  misPunch,
  none,
}

class _Summary {
  final int present;
  final int absent;
  final int leave;
  final int incomplete;
  final int overtime;
  final int misPunch;

  const _Summary({
    required this.present,
    required this.absent,
    required this.leave,
    required this.incomplete,
    required this.overtime,
    required this.misPunch,
  });
}

class _IncompleteDutyBalance {
  final String date;
  final int shortfallMinutes;

  const _IncompleteDutyBalance({
    required this.date,
    required this.shortfallMinutes,
  });
}

class _DayDetailsSheet extends StatelessWidget {
  final DateTime date;
  final _DayStatus status;
  final Map<String, dynamic>? data;
  final AttendanceResult? calculation;
  final VoidCallback? onRequestIncompleteDuty;
  final VoidCallback? onRequestMispunch;
  final VoidCallback? onRequestOvertime;
  final bool requestAlreadySent;
  final String? requestLabel;
  final VoidCallback? onDeleteRequest;

  const _DayDetailsSheet({
    required this.date,
    required this.status,
    required this.data,
    required this.calculation,
    required this.onRequestIncompleteDuty,
    required this.onRequestMispunch,
    required this.onRequestOvertime,
    required this.requestAlreadySent,
    required this.requestLabel,
    required this.onDeleteRequest,
  });

  String _statusLabel() {
    switch (status) {
      case _DayStatus.present:
        return 'Present';
      case _DayStatus.absent:
        return 'Absent';
      case _DayStatus.leave:
        return 'Leave';
      case _DayStatus.incomplete:
        return 'Incomplete duty';
      case _DayStatus.overtime:
        return 'Overtime duty';
      case _DayStatus.misPunch:
        return 'Mis-punch';
      case _DayStatus.none:
        return 'No attendance';
    }
  }

  Color _statusColor() {
    switch (status) {
      case _DayStatus.present:
        return AppColors.calendarPresentText;
      case _DayStatus.absent:
        return AppColors.calendarAbsentText;
      case _DayStatus.leave:
        return AppColors.calendarLeaveText;
      case _DayStatus.incomplete:
        return const Color(0xFF7A4DD8);
      case _DayStatus.overtime:
        return AppColors.primary;
      case _DayStatus.misPunch:
        return AppColors.danger;
      case _DayStatus.none:
        return AppColors.textSecondary;
    }
  }

  String _time(String? value) =>
      value == null || value.trim().isEmpty ? '—' : value;

  List<Map<String, dynamic>> _sessionMapsFromRecord(
    Map<String, dynamic> record,
  ) {
    final result = <Map<String, dynamic>>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item['punchIn'] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort(
          (a, b) => a.key.toString().compareTo(b.key.toString()),
        );
      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item['punchIn'] != null) {
          result.add(Map<String, dynamic>.from(item));
        }
      }
    }

    if (result.isEmpty && record['punchIn'] != null) {
      result.add({
        'punchIn': record['punchIn'],
        if (record['punchOut'] != null) 'punchOut': record['punchOut'],
        'workFromHome': record['workFromHome'] == true,
        if (record['workLocationType'] != null)
          'workLocationType': record['workLocationType'],
      });
    }

    return result;
  }

  bool _sessionIsWfh(Map<String, dynamic> session) {
    return session['workFromHome'] == true ||
        session['workLocationType']?.toString().toLowerCase() ==
            'work from home';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = <AttendanceSession>[];
    if (data != null) {
      final raw = data!['sessions'];

      if (raw is List) {
        for (final item in raw) {
          if (item is Map && item['punchIn'] != null) {
            sessions.add(
              AttendanceSession(
                punchIn: item['punchIn'].toString(),
                punchOut: item['punchOut']?.toString(),
              ),
            );
          }
        }
      } else if (raw is Map) {
        final entries = raw.entries.toList()
          ..sort(
            (a, b) => a.key.toString().compareTo(
              b.key.toString(),
            ),
          );

        for (final entry in entries) {
          if (entry.value is Map &&
              entry.value['punchIn'] != null) {
            sessions.add(
              AttendanceSession(
                punchIn: entry.value['punchIn'].toString(),
                punchOut: entry.value['punchOut']?.toString(),
              ),
            );
          }
        }
      }

      if (sessions.isEmpty && data!['punchIn'] != null) {
        sessions.add(
          AttendanceSession(
            punchIn: data!['punchIn'].toString(),
            punchOut: data!['punchOut']?.toString(),
          ),
        );
      }
    }

    final sessionMaps = data == null
        ? <Map<String, dynamic>>[]
        : _sessionMapsFromRecord(data!);

    final hasWfhSession = sessionMaps.any(_sessionIsWfh);

    final checkIn =
        sessions.isEmpty ? null : sessions.first.punchIn;
    final checkOut =
        sessions.isEmpty ? null : sessions.last.punchOut;

    final total = calculation == null
        ? (status == _DayStatus.leave ? '0h 00m' : '—')
        : AttendanceCalculator.formatHours(
            calculation!.netHours,
          )
            .replaceFirst(' hr ', 'h ')
            .replaceFirst(' min', 'm');

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(26),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.divider,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('EEE, d MMM').format(date),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (hasWfhSession)
                    Container(
                      margin: const EdgeInsets.only(right: 7),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.successLight,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Text(
                        'WFH',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: AppColors.success,
                        ),
                      ),
                    ),
                  InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppColors.divider,
                        ),
                      ),
                      child: const Icon(
                        Icons.close,
                        size: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                _statusLabel(),
                style: TextStyle(
                  fontSize: 10,
                  color: _statusColor(),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 17),
              _detailLine(
                'Check in',
                _time(checkIn),
              ),
              _detailLine(
                'Check out',
                _time(checkOut),
              ),
              _detailLine('Total hours', total),
              if (sessionMaps.length > 1 || hasWfhSession) ...[
                const SizedBox(height: 12),
                const Text(
                  'Sessions',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                ...sessionMaps.asMap().entries.map((entry) {
                  final index = entry.key;
                  final session = entry.value;
                  final isWfh = _sessionIsWfh(session);
                  final sessionIn = _time(session['punchIn']?.toString());
                  final sessionOut = _time(session['punchOut']?.toString());

                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: isWfh
                          ? AppColors.successLight
                          : AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isWfh
                              ? Icons.home_work_outlined
                              : Icons.apartment_outlined,
                          size: 14,
                          color: isWfh
                              ? AppColors.success
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'Session ${index + 1}',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          '$sessionIn → $sessionOut',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          isWfh ? 'WFH' : 'Office',
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: isWfh
                                ? AppColors.success
                                : AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              if (requestAlreadySent) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${requestLabel ?? 'Request'} already sent for this day.',
                          style: const TextStyle(
                            fontSize: 9,
                            height: 1.35,
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (onDeleteRequest != null) ...[
                  const SizedBox(height: 9),
                  SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: OutlinedButton.icon(
                      onPressed: onDeleteRequest,
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: const Text(
                        'Delete request',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.danger,
                        side: BorderSide(
                          color: AppColors.danger.withValues(alpha: .55),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
              if (status == _DayStatus.misPunch &&
                  onRequestMispunch != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'This day is marked MP because the last session did not have a real checkout. Submit your actual checkout time for admin verification.',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.35,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: onRequestMispunch,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Request punch-out correction',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
              if (status == _DayStatus.incomplete &&
                  calculation != null &&
                  calculation!.shortfallHours > 0 &&
                  onRequestIncompleteDuty != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: const Color(0xFF7A4DD8).withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'You are short by ${AttendanceCalculator.formatHours(calculation!.shortfallHours)}. Send the reason for the incomplete duty to admin.',
                    style: const TextStyle(
                      fontSize: 9,
                      height: 1.35,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: onRequestIncompleteDuty,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Send incomplete-duty reason',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
              if (status == _DayStatus.overtime &&
                  calculation != null &&
                  calculation!.extraHours > 0) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 11, 12, 10),
                  decoration: BoxDecoration(
                    color: AppColors.successLight,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'You worked ${AttendanceCalculator.formatHours(calculation!.extraHours)} of verified overtime. You can use it for compensation according to your active ID balance.',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 9,
                      height: 1.35,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 42,
                  child: ElevatedButton(
                    onPressed: onRequestOvertime,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.green,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Request overtime compensation',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailLine(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.divider),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 10,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
