import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/attendance_calculator.dart';
import '../widgets/workora_logo.dart';

class PersonalReportScreen extends StatefulWidget {
  final String employeeId;

  const PersonalReportScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<PersonalReportScreen> createState() => _PersonalReportScreenState();
}

class _PersonalReportScreenState extends State<PersonalReportScreen> {
  static const Color green = Color(0xFF0E5A3B);
  static const Color greenDark = Color(0xFF08452D);
  static const Color greenSoft = Color(0xFFEAF5EF);
  static const Color yellow = Color(0xFFFFB020);
  static const Color yellowSoft = Color(0xFFFFF6DE);
  static const Color red = Color(0xFFE5484D);
  static const Color redSoft = Color(0xFFFFECEC);
  static const Color text = Color(0xFF17221C);
  static const Color muted = Color(0xFF758079);
  static const Color border = Color(0xFFE5EAE7);
  static const Color page = Color(0xFFF7F9F8);

  late DatabaseReference dbRef;

  bool loading = true;
  String? errorMessage;

  Map<String, dynamic> attendance = {};

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadData();
  }

  String _dateKey(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() {
        loading = true;
        errorMessage = null;
      });
    }

    try {
      final snapshot = await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .get();

      final Map<String, dynamic> loaded = {};

      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);

        data.forEach((key, value) {
          if (value is Map) {
            loaded[key.toString()] = Map<String, dynamic>.from(value);
          }
        });
      }

      if (!mounted) return;

      setState(() {
        attendance = loaded;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
        errorMessage = 'Unable to load your report.';
      });
    }
  }

  List<DateTime> _weekDates() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(
      Duration(days: today.weekday - 1),
    );

    return List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
  }

  List<AttendanceSession> _sessionsFromRecord(
    Map<String, dynamic>? record,
  ) {
    if (record == null) return <AttendanceSession>[];

    final sessions = <AttendanceSession>[];
    final raw = record['sessions'];

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

    // Backward compatibility for old records.
    if (sessions.isEmpty && record['punchIn'] != null) {
      sessions.add(
        AttendanceSession(
          punchIn: record['punchIn'].toString(),
          punchOut: record['punchOut']?.toString(),
        ),
      );
    }

    return sessions;
  }

  AttendanceResult? _calculate(
    Map<String, dynamic>? record,
  ) {
    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) return null;

    // Never calculate MIS-PUNCH using the temporary 11:59 PM value.
    if (_isMisPunch(record)) return null;

    final hasOpenSession = sessions.any(
      (session) =>
          session.punchIn.isNotEmpty &&
          (session.punchOut == null || session.punchOut!.isEmpty),
    );

    if (hasOpenSession) return null;

    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    );
  }

  bool _isMisPunch(Map<String, dynamic>? record) {
    if (record == null) return false;

    final status = record['status']?.toString().toUpperCase();

    return status == 'MIS-PUNCH' ||
        record['misPunch'] == true ||
        record['temporaryPunchOut'] != null ||
        status == 'MIS-PUNCH — AWAITING ADMIN CORRECTION';
  }

  DayType? _dayType(
    DateTime date,
    Map<String, dynamic>? record,
  ) {
    if (record == null) return DayType.absent;

    if (_isMisPunch(record)) {
      return null;
    }

    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) {
      return DayType.absent;
    }

    final last = sessions.last;

    if (last.punchOut == null || last.punchOut!.isEmpty) {
      return _isSameDay(date, DateTime.now())
          ? null
          : DayType.absent;
    }

    return _calculate(record)?.dayType ?? DayType.absent;
  }

  double _hoursFor(String key) {
    return _calculate(attendance[key])?.netHours ?? 0;
  }

  String _formatHours(double hours) {
    final totalMinutes = (hours * 60).round();
    final h = totalMinutes ~/ 60;
    final m = totalMinutes % 60;

    if (h == 0) return '${m}m';
    if (m == 0) return '${h}h';
    return '${h}h ${m}m';
  }

  String _statusLabel(
    DateTime date,
    Map<String, dynamic>? record,
  ) {
    final type = _dayType(date, record);

    if (_isMisPunch(record)) return 'MIS-PUNCH';

    switch (type) {
      case DayType.fullDay:
        return 'FULL DAY';
      case DayType.workPending:
        return 'WORK-PENDING';
      case DayType.absent:
        return 'ABSENT';
      case null:
        return 'IN PROGRESS';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'FULL DAY':
        return green;
      case 'WORK-PENDING':
        return yellow;
      case 'MIS-PUNCH':
        return yellow;
      case 'IN PROGRESS':
        return green;
      default:
        return red;
    }
  }

  Color _statusBackground(String status) {
    switch (status) {
      case 'FULL DAY':
        return greenSoft;
      case 'WORK-PENDING':
        return yellowSoft;
      case 'MIS-PUNCH':
        return yellowSoft;
      case 'IN PROGRESS':
        return greenSoft;
      default:
        return redSoft;
    }
  }

  int _completedFullDays(List<DateTime> dates) {
    var count = 0;

    for (final date in dates) {
      if (date.isAfter(DateTime.now())) continue;

      final type = _dayType(
        date,
        attendance[_dateKey(date)],
      );

      if (type == DayType.fullDay) count++;
    }

    return count;
  }

  int _completedPendingDays(List<DateTime> dates) {
    var count = 0;

    for (final date in dates) {
      if (date.isAfter(DateTime.now())) continue;

      final type = _dayType(
        date,
        attendance[_dateKey(date)],
      );

      if (type == DayType.workPending) count++;
    }

    return count;
  }

  int _completedAbsentDays(List<DateTime> dates) {
    var count = 0;

    for (final date in dates) {
      if (date.isAfter(DateTime.now())) continue;

      final type = _dayType(
        date,
        attendance[_dateKey(date)],
      );

      if (type == DayType.absent) count++;
    }

    return count;
  }

  double _weekHours(List<DateTime> dates) {
    var total = 0.0;

    for (final date in dates) {
      total += _hoursFor(_dateKey(date));
    }

    return total;
  }

  double _averageHours(List<DateTime> dates) {
    var total = 0.0;
    var counted = 0;

    for (final date in dates) {
      if (date.isAfter(DateTime.now())) continue;

      final key = _dateKey(date);
      final hours = _hoursFor(key);

      if (hours > 0) {
        total += hours;
        counted++;
      }
    }

    return counted == 0 ? 0 : total / counted;
  }

  double _progress(double hours) {
    return (hours / 9).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final weekDates = _weekDates();

    return Scaffold(
      backgroundColor: page,
      body: SafeArea(
        child: loading
            ? const Center(
                child: CircularProgressIndicator(
                  color: green,
                ),
              )
            : errorMessage != null
                ? _errorView()
                : RefreshIndicator(
                    color: green,
                    onRefresh: _loadData,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(
                        18,
                        12,
                        18,
                        28,
                      ),
                      children: [
                        _buildHeader(),
                        const SizedBox(height: 18),
                        _buildTitle(),
                        const SizedBox(height: 16),
                        _buildWeeklyOverview(weekDates),
                        const SizedBox(height: 16),
                        _buildSummaryCards(weekDates),
                        const SizedBox(height: 20),
                        _buildDailySection(weekDates),
                        const SizedBox(height: 20),
                        _buildWorkBalance(weekDates),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      children: [
        const WorkoraLogo(
          width: 112,
          height: 34,
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'A Product of EDUBOTICS\nA Division of Hindustan',
            style: TextStyle(
              fontSize: 8.5,
              height: 1.2,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        _headerIcon(
          Icons.notifications_none_rounded,
          onTap: () {},
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: const BoxDecoration(
            color: green,
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: const Text(
            'AA',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerIcon(
    IconData icon, {
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: text,
          ),
        ),
      ),
    );
  }

  Widget _buildTitle() {
    final now = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Reports',
          style: TextStyle(
            color: text,
            fontSize: 24,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Your attendance and working-hours overview',
          style: TextStyle(
            color: muted,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${_monthName(now.month)} ${now.year}',
          style: const TextStyle(
            color: green,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyOverview(List<DateTime> dates) {
    final total = _weekHours(dates);
    final average = _averageHours(dates);
    final progress = _progress(average);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            greenDark,
            green,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: green.withOpacity(0.18),
            blurRadius: 20,
            offset: const Offset(0, 9),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This week',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Working hours',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                _formatHours(total),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: dates.map((date) {
              final key = _dateKey(date);
              final hours = _hoursFor(key);
              final status = _statusLabel(
                date,
                attendance[key],
              );

              final isToday = _isSameDay(
                date,
                DateTime.now(),
              );

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Column(
                    children: [
                      Text(
                        _weekdayShort(date.weekday),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        height: 38,
                        width: 38,
                        decoration: BoxDecoration(
                          color: isToday
                              ? Colors.white
                              : Colors.white.withOpacity(0.10),
                          shape: BoxShape.circle,
                          border: isToday
                              ? null
                              : Border.all(
                                  color: Colors.white.withOpacity(0.12),
                                ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${date.day}',
                          style: TextStyle(
                            color: isToday
                                ? green
                                : Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: _statusColor(status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        hours > 0
                            ? '${hours.toStringAsFixed(1)}h'
                            : '--',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.72),
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Average ${_formatHours(average)} / day',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: progress,
              backgroundColor: Colors.white.withOpacity(0.13),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(List<DateTime> dates) {
    final full = _completedFullDays(dates);
    final pending = _completedPendingDays(dates);
    final absent = _completedAbsentDays(dates);

    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            icon: Icons.check_circle_outline_rounded,
            label: 'Full day',
            value: '$full',
            color: green,
            background: greenSoft,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _summaryCard(
            icon: Icons.schedule_rounded,
            label: 'Pending',
            value: '$pending',
            color: yellow,
            background: yellowSoft,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: _summaryCard(
            icon: Icons.cancel_outlined,
            label: 'Absent',
            value: '$absent',
            color: red,
            background: redSoft,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: color.withOpacity(0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 19,
            color: color,
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailySection(List<DateTime> dates) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          title: 'Daily breakdown',
          subtitle: 'Your current week',
        ),
        const SizedBox(height: 10),
        ...dates.map(_dailyCard),
      ],
    );
  }

  Widget _dailyCard(DateTime date) {
    final key = _dateKey(date);
    final record = attendance[key];
    final hours = _hoursFor(key);
    final status = _statusLabel(
      date,
      record,
    );

    final isToday = _isSameDay(
      date,
      DateTime.now(),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isToday
              ? green.withOpacity(0.35)
              : border,
          width: isToday ? 1.3 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.025),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              color: isToday
                  ? greenSoft
                  : const Color(0xFFF2F5F3),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekdayShort(date.weekday),
                  style: const TextStyle(
                    color: muted,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${date.day}',
                  style: const TextStyle(
                    color: text,
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _dateLabel(date),
                      style: const TextStyle(
                        color: text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (isToday) ...[
                      const SizedBox(width: 6),
                      const Text(
                        'TODAY',
                        style: TextStyle(
                          color: green,
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  hours > 0
                      ? '${_formatHours(hours)} worked'
                      : _secondaryDailyText(record, date),
                  style: const TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _statusChip(status),
        ],
      ),
    );
  }

  String _secondaryDailyText(
    Map<String, dynamic>? record,
    DateTime date,
  ) {
    if (_isMisPunch(record)) {
      return 'Waiting for admin correction';
    }

    final sessions = _sessionsFromRecord(record);

    if (sessions.isNotEmpty &&
        (sessions.last.punchOut == null ||
            sessions.last.punchOut!.isEmpty)) {
      return 'Currently checked in';
    }

    if (date.isAfter(DateTime.now())) {
      return 'Not available yet';
    }

    return 'No completed attendance';
  }

  Widget _statusChip(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: _statusBackground(status),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 8,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  Widget _buildWorkBalance(List<DateTime> dates) {
    final total = _weekHours(dates);
    final target = 45.0;
    final remaining = (target - total).clamp(0.0, target);
    final extra = (total - target).clamp(0.0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            title: 'Work balance',
            subtitle: 'Based on 9 hours required per day',
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: _balanceValue(
                  'Worked',
                  _formatHours(total),
                  green,
                ),
              ),
              Expanded(
                child: _balanceValue(
                  'Target',
                  '45h',
                  text,
                ),
              ),
              Expanded(
                child: _balanceValue(
                  extra > 0 ? 'Extra' : 'Remaining',
                  extra > 0
                      ? _formatHours(extra)
                      : _formatHours(remaining),
                  extra > 0 ? green : yellow,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: (total / target).clamp(0.0, 1.0),
              backgroundColor: const Color(0xFFE9EEEB),
              valueColor: const AlwaysStoppedAnimation<Color>(
                green,
              ),
            ),
          ),
          const SizedBox(height: 9),
          const Text(
            'Compensation and outstanding time are calculated from completed attendance records.',
            style: TextStyle(
              color: muted,
              fontSize: 10,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _balanceValue(
    String label,
    String value,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(
            color: muted,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _errorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_rounded,
              size: 46,
              color: red,
            ),
            const SizedBox(height: 14),
            Text(
              errorMessage ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: _loadData,
              style: FilledButton.styleFrom(
                backgroundColor: green,
              ),
              child: const Text('TRY AGAIN'),
            ),
          ],
        ),
      ),
    );
  }

  String _weekdayShort(int weekday) {
    const names = [
      'Mon',
      'Tue',
      'Wed',
      'Thu',
      'Fri',
      'Sat',
      'Sun',
    ];

    return names[weekday - 1];
  }

  String _monthName(int month) {
    const names = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return names[month - 1];
  }

  String _dateLabel(DateTime date) {
    return '${_weekdayShort(date.weekday)}, '
        '${date.day.toString().padLeft(2, '0')} '
        '${_monthName(date.month).substring(0, 3)}';
  }
}
