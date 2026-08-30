import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:fl_chart/fl_chart.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

class PersonalReportScreen extends StatefulWidget {
  final String employeeId;

  const PersonalReportScreen({super.key, required this.employeeId});

  @override
  State<PersonalReportScreen> createState() => _PersonalReportScreenState();
}

class _PersonalReportScreenState extends State<PersonalReportScreen> {
  late DatabaseReference dbRef;
  bool loading = true;
  Map<String, dynamic> attendance = {};

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadData();
  }

  String _dateKey(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  Future<void> _loadData() async {
    setState(() => loading = true);
    try {
      final snapshot = await dbRef.child("Attendance").child(widget.employeeId).get();
      if (snapshot.exists) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        attendance = data.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => loading = false);
  }

  List<DateTime> _weekDates() {
    final now = DateTime.now();
    final start = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));
  }

  List<AttendanceSession> _sessionsFromRecord(Map<String, dynamic>? record) {
    if (record == null) return <AttendanceSession>[];

    final sessions = <AttendanceSession>[];
    final raw = record["sessions"];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item["punchIn"] != null) {
          sessions.add(AttendanceSession(
            punchIn: item["punchIn"].toString(),
            punchOut: item["punchOut"]?.toString(),
          ));
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final item = entry.value;
        if (item is Map && item["punchIn"] != null) {
          sessions.add(AttendanceSession(
            punchIn: item["punchIn"].toString(),
            punchOut: item["punchOut"]?.toString(),
          ));
        }
      }
    }

    if (sessions.isEmpty && record["punchIn"] != null) {
      sessions.add(AttendanceSession(
        punchIn: record["punchIn"].toString(),
        punchOut: record["punchOut"]?.toString(),
      ));
    }

    return sessions;
  }

  AttendanceResult? _calculateSessions(Map<String, dynamic>? record) {
    final sessions = _sessionsFromRecord(record);
    if (sessions.isEmpty) return null;
    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    );
  }

  double _hoursFor(String key) {
    return _calculateSessions(attendance[key])?.netHours ?? 0;
  }

  DayType _classify(String key) {
    final record = attendance[key];
    final sessions = _sessionsFromRecord(record);
    if (sessions.isEmpty) return DayType.absent;

    final last = sessions.last;
    if (last.punchOut == null) return DayType.absent;

    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    ).dayType;
  }

  String _sessionSummary(String key) {
    final sessions = _sessionsFromRecord(attendance[key]);
    if (sessions.isEmpty) return '--';
    return sessions.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final s = entry.value;
      return 'S$i: ${s.punchIn} → ${s.punchOut ?? '--'}';
    }).join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final weekDates = _weekDates();
    final labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    int fullDays = 0, misDays = 0, absentDays = 0;
    double totalHours = 0;
    final bars = <BarChartGroupData>[];

    for (int i = 0; i < weekDates.length; i++) {
      final key = _dateKey(weekDates[i]);
      final hours = _hoursFor(key);
      totalHours += hours;

      if (!weekDates[i].isAfter(DateTime.now())) {
        final type = _classify(key);
        if (type == DayType.fullDay) fullDays++;
        else if (type == DayType.misPunch) misDays++;
        else if (type == DayType.absent) absentDays++;
      }

      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: hours, color: AppColors.primary, width: 16, borderRadius: BorderRadius.circular(4)),
      ]));
    }

    double maxHoursObserved = 0;
    for (final bar in bars) {
      if (bar.barRods.isNotEmpty && bar.barRods.first.toY > maxHoursObserved) {
        maxHoursObserved = bar.barRods.first.toY;
      }
    }
    final dynamicMaxY = (maxHoursObserved > 9.0) ? (maxHoursObserved + 2.0).ceilToDouble() : 10.0;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: loading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text("Reports", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        gradient: AppGradients.punchCard,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: AppShadows.hero,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text("Total Hours", style: TextStyle(color: Colors.white70, fontSize: 12)),
                              SizedBox(height: 4),
                              Text("This Week", style: TextStyle(color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                          Text(
                            AttendanceCalculator.formatHours(totalHours),
                            style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Working Hours", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text("Max: ${dynamicMaxY.toInt()}h", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 180,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: BarChart(
                                BarChartData(
                                  maxY: dynamicMaxY,
                                  minY: 0,
                                  gridData: FlGridData(
                                    show: true,
                                    drawVerticalLine: false,
                                    horizontalInterval: dynamicMaxY / 4 > 0 ? dynamicMaxY / 4 : 2.5,
                                    getDrawingHorizontalLine: (_) => FlLine(
                                      color: AppColors.divider.withOpacity(0.5),
                                      strokeWidth: 1,
                                      dashArray: [4, 4],
                                    ),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  titlesData: FlTitlesData(
                                    leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    bottomTitles: AxisTitles(
                                      sideTitles: SideTitles(
                                        showTitles: true,
                                        getTitlesWidget: (v, m) => Padding(
                                          padding: const EdgeInsets.only(top: 6),
                                          child: Text(labels[v.toInt() % 7], style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                                        ),
                                      ),
                                    ),
                                  ),
                                  barGroups: bars.map((group) {
                                    final rod = group.barRods.first;
                                    return BarChartGroupData(
                                      x: group.x,
                                      barRods: [
                                        BarChartRodData(
                                          toY: rod.toY,
                                          gradient: const LinearGradient(
                                            begin: Alignment.bottomCenter,
                                            end: Alignment.topCenter,
                                            colors: [AppColors.indigo, AppColors.brightBlue],
                                          ),
                                          width: 16,
                                          borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
                                          backDrawRodData: BackgroundBarChartRodData(
                                            show: true,
                                            toY: dynamicMaxY,
                                            color: AppColors.background.withOpacity(0.6),
                                          ),
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text("This Week", style: TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _statCard("Full", "$fullDays", AppColors.success, AppColors.successLight)),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard("Miss", "$misDays", AppColors.danger, AppColors.dangerLight)),
                        const SizedBox(width: 10),
                        Expanded(child: _statCard("Absent", "$absentDays", AppColors.danger, AppColors.dangerLight)),
                      ],
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14), border: Border(top: BorderSide(color: color, width: 3))),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
        ],
      ),
    );
  }
}