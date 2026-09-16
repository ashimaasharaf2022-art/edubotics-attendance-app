import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../widgets/punch_card.dart';

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
  late DatabaseReference dbRef;

  bool loading = true;
  Map<dynamic, dynamic> attendanceData = {};

  DateTime selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _openAttendance();
  }

  Future<void> _openAttendance() async {
    await _checkPreviousDayForMisPunch();
    await _loadHistory();
  }

  String _dateKey(DateTime date) {
    return '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';
  }

  bool _isToday(String key) => key == _dateKey(DateTime.now());

  String _monthName(int month) {
    const months = [
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
    return months[month - 1];
  }

  String _weekday(DateTime date) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[date.weekday - 1];
  }

  String _dateLabel(DateTime date) {
    return '${_weekday(date)}, ${date.day} ${_monthName(date.month)} ${date.year}';
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

        if (dateKey == todayKey) continue;

        final raw = entry.value;
        if (raw is! Map) continue;

        final record = Map<dynamic, dynamic>.from(raw);

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
      // The UI should still open if the check fails.
    }
  }

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final snapshot = await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .get();

      if (snapshot.exists && snapshot.value is Map) {
        attendanceData = Map<dynamic, dynamic>.from(snapshot.value as Map);
      } else {
        attendanceData = {};
      }
    } catch (_) {
      attendanceData = {};
    }

    if (!mounted) return;
    setState(() => loading = false);
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

  DayType? _classify(String dateKey, Map data) {
    final status = data['status']?.toString().toUpperCase();

    if (status == 'MIS-PUNCH') return null;

    if (status == 'AUTO CHECKOUT PENDING' ||
        data['autoPunchOut'] == true) {
      return null;
    }

    final sessions = _sessionsFromRecord(data);

    if (sessions.isNotEmpty) {
      final hasOpenSession = sessions.any(
        (s) => s.punchOut == null || s.punchOut!.trim().isEmpty,
      );

      if (hasOpenSession) {
        return _isToday(dateKey) ? null : DayType.absent;
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
      return _isToday(dateKey) ? null : DayType.absent;
    }

    return AttendanceCalculator.calculate(
      punchIn: punchIn,
      punchOut: punchOut,
      workFromHome: data['workFromHome'] == true,
    ).dayType;
  }

  Color _statusColor(DayType? type) {
    switch (type) {
      case DayType.fullDay:
        return AppColors.success;
      case DayType.workPending:
        return AppColors.warning;
      case DayType.absent:
        return AppColors.danger;
      case null:
        return AppColors.info;
    }
  }

  String _statusText(String dateKey, Map data) {
    final status = data['status']?.toString().toUpperCase();

    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        data['autoPunchOut'] == true) {
      return 'MIS-PUNCH';
    }

    final type = _classify(dateKey, data);

    switch (type) {
      case DayType.fullDay:
        return 'FULL DAY';
      case DayType.workPending:
        return 'WORK-PENDING';
      case DayType.absent:
        return 'ABSENT';
      case null:
        return _isToday(dateKey) ? 'IN PROGRESS' : 'MIS-PUNCH';
    }
  }

  String _punchOutText(Map data) {
    final status = data['status']?.toString().toUpperCase();

    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        data['autoPunchOut'] == true) {
      return 'Awaiting admin correction';
    }

    final out = data['punchOut']?.toString();
    return out == null || out.trim().isEmpty ? '--' : out;
  }

  Map? _selectedRecord() {
    final raw = attendanceData[_dateKey(selectedDate)];
    if (raw is Map) return Map<dynamic, dynamic>.from(raw);
    return null;
  }

  List<DateTime> _weekDates() {
    final base = selectedDate.subtract(
      Duration(days: selectedDate.weekday - 1),
    );

    return List.generate(
      7,
      (index) => base.add(Duration(days: index)),
    );
  }

  Widget _buildCalendarStrip() {
    final dates = _weekDates();

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 12,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: dates.map((date) {
          final key = _dateKey(date);
          final raw = attendanceData[key];
          final data = raw is Map
              ? Map<dynamic, dynamic>.from(raw)
              : null;

          final today = _isToday(key);
          final selected = key == _dateKey(selectedDate);

          Color dotColor = AppColors.divider;
          String shortStatus = '';

          if (data != null) {
            final status = data['status']?.toString().toUpperCase();

            if (status == 'MIS-PUNCH') {
              dotColor = AppColors.warning;
              shortStatus = 'MIS';
            } else {
              final type = _classify(key, data);
              dotColor = _statusColor(type);
              shortStatus = type == DayType.fullDay
                  ? 'Full'
                  : type == DayType.workPending
                      ? 'Pending'
                      : type == DayType.absent
                          ? 'Absent'
                          : 'Open';
            }
          } else if (date.isBefore(
            DateTime.now().subtract(const Duration(days: 1)),
          )) {
            dotColor = AppColors.danger.withOpacity(.65);
            shortStatus = 'Absent';
          }

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => selectedDate = date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: selected
                      ? AppColors.primary.withOpacity(.10)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: selected
                      ? Border.all(
                          color: AppColors.primary,
                          width: 1.2,
                        )
                      : null,
                ),
                child: Column(
                  children: [
                    Text(
                      _weekday(date),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: today
                            ? AppColors.primary
                            : AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: dotColor.withOpacity(.12),
                        border: today
                            ? Border.all(
                                color: AppColors.primary,
                                width: 1.4,
                              )
                            : null,
                      ),
                      child: Text(
                        '${date.day}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: dotColor == AppColors.divider
                              ? AppColors.textPrimary
                              : dotColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      shortStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: shortStatus.isEmpty
                            ? AppColors.textSecondary
                            : dotColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSelectedDayCard() {
    final dateKey = _dateKey(selectedDate);
    final data = _selectedRecord();
    final isToday = _isToday(dateKey);

    final type = data == null ? DayType.absent : _classify(dateKey, data);
    final status = data == null
        ? 'ABSENT'
        : _statusText(dateKey, data);

    final statusColor = status == 'MIS-PUNCH'
        ? AppColors.warning
        : _statusColor(type);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppColors.divider),
        boxShadow: AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _dateLabel(selectedDate),
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              if (isToday)
                _statusPill(
                  'TODAY',
                  AppColors.primary,
                )
              else
                _statusPill(
                  status,
                  statusColor,
                ),
            ],
          ),
          const SizedBox(height: 18),

          if (data == null) ...[
            const _EmptyAttendanceRow(),
          ] else ...[
            Row(
              children: [
                Expanded(
                  child: _timeInfo(
                    icon: Icons.login_rounded,
                    label: 'Check in',
                    value: data['punchIn']?.toString() ?? '--',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _timeInfo(
                    icon: Icons.logout_rounded,
                    label: 'Check out',
                    value: _punchOutText(data),
                    warning: status == 'MIS-PUNCH',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _detailRow(
              Icons.info_outline,
              'Status',
              status,
              color: statusColor,
            ),
            if (data['workFromHome'] == true) ...[
              const SizedBox(height: 8),
              _detailRow(
                Icons.home_work_outlined,
                'Work mode',
                'Work from home',
              ),
            ],
            if (status == 'MIS-PUNCH') ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.warning.withOpacity(.22),
                  ),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: AppColors.warning,
                      size: 20,
                    ),
                    SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        'You forgot to punch out. This attendance is waiting for admin correction. The temporary 11:59 PM time is not used for working-hour calculation.',
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildTodayPunchCard() {
    if (!_isToday(_dateKey(selectedDate))) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        const Text(
          'Mark attendance',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 9),
        const Text(
          'Punch in or out from anywhere. Your location is recorded when you punch.',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 12),
        PunchCard(
          employeeId: widget.employeeId,
          compact: false,
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.divider),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 10,
        children: [
          _legendItem(AppColors.success, 'FULL DAY'),
          _legendItem(AppColors.warning, 'WORK-PENDING'),
          _legendItem(AppColors.danger, 'ABSENT'),
          _legendItem(AppColors.warning, 'MIS-PUNCH'),
        ],
      ),
    );
  }

  Widget _legendItem(Color color, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _statusPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _timeInfo({
    required IconData icon,
    required String label,
    required String value,
    bool warning = false,
  }) {
    final color = warning ? AppColors.warning : AppColors.primary;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 10,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: warning
                        ? AppColors.warning
                        : AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    IconData icon,
    String label,
    String value, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 17,
          color: color ?? AppColors.primary,
        ),
        const SizedBox(width: 8),
        Text(
          '$label:',
          style: const TextStyle(
            fontSize: 12,
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color ?? AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryList() {
    final dates = attendanceData.keys
        .map((e) => e.toString())
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (loading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (dates.isEmpty) {
      return const Center(
        child: Text(
          'No attendance records yet.',
          style: TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
      itemCount: dates.length,
      itemBuilder: (context, index) {
        final date = dates[index];
        final raw = attendanceData[date];

        if (raw is! Map) {
          return const SizedBox.shrink();
        }

        final data = Map<dynamic, dynamic>.from(raw);
        final status = _statusText(date, data);
        final type = _classify(date, data);

        final color = status == 'MIS-PUNCH'
            ? AppColors.warning
            : _statusColor(type);

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.divider),
            boxShadow: AppShadows.card,
          ),
          child: Row(
            children: [
              Container(
                width: 45,
                height: 45,
                decoration: BoxDecoration(
                  color: color.withOpacity(.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  status == 'MIS-PUNCH'
                      ? Icons.warning_amber_rounded
                      : type == DayType.fullDay
                          ? Icons.check_circle_outline
                          : type == DayType.workPending
                              ? Icons.schedule
                              : Icons.event_busy_outlined,
                  color: color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      date,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'In ${data['punchIn']?.toString() ?? '--'}  •  Out ${_punchOutText(data)}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(status, color),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _openAttendance,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Attendance',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'Mark your attendance and stay on track.',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: AppColors.divider,
                          ),
                        ),
                        child: const Icon(
                          Icons.calendar_month_outlined,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                  child: _buildCalendarStrip(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: _buildSelectedDayCard(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _buildTodayPunchCard(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: _buildLegend(),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Attendance history',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) {
                              return Container(
                                height:
                                    MediaQuery.of(context).size.height * .82,
                                decoration: const BoxDecoration(
                                  color: AppColors.background,
                                  borderRadius: BorderRadius.vertical(
                                    top: Radius.circular(28),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    const SizedBox(height: 10),
                                    Container(
                                      width: 42,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: AppColors.divider,
                                        borderRadius:
                                            BorderRadius.circular(20),
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    const Text(
                                      'Attendance history',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Expanded(
                                      child: _buildHistoryList(),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        child: const Text(
                          'View all',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 30),
                  child: _buildHistoryPreview(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoryPreview() {
    final dates = attendanceData.keys
        .map((e) => e.toString())
        .toList()
      ..sort((a, b) => b.compareTo(a));

    if (loading) {
      return const SizedBox(
        height: 80,
        child: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (dates.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.divider),
        ),
        child: const Text(
          'No attendance records yet.',
          style: TextStyle(
            color: AppColors.textSecondary,
          ),
        ),
      );
    }

    final previewDates = dates.take(3).toList();

    return Column(
      children: previewDates.map((date) {
        final raw = attendanceData[date];
        if (raw is! Map) return const SizedBox.shrink();

        final data = Map<dynamic, dynamic>.from(raw);
        final status = _statusText(date, data);
        final type = _classify(date, data);
        final color = status == 'MIS-PUNCH'
            ? AppColors.warning
            : _statusColor(type);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  date,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              _statusPill(status, color),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyAttendanceRow extends StatelessWidget {
  const _EmptyAttendanceRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 14,
        vertical: 18,
      ),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(
            Icons.event_busy_outlined,
            color: AppColors.danger,
            size: 20,
          ),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No attendance was recorded for this date.',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
