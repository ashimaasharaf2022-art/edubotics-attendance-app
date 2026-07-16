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

  double _hoursFor(String key) {
    final record = attendance[key];
    if (record == null) return 0;
    final punchIn = record["punchIn"]?.toString();
    final punchOut = record["punchOut"]?.toString();
    if (punchIn == null || punchOut == null) return 0;
    return AttendanceCalculator.calculate(punchIn: punchIn, punchOut: punchOut).netHours;
  }

  DayType _classify(String key) {
    final record = attendance[key];
    if (record == null || record["punchIn"] == null) return DayType.absent;
    final punchOut = record["punchOut"]?.toString();
    if (punchOut == null) return DayType.absent;
    return AttendanceCalculator.calculate(punchIn: record["punchIn"].toString(), punchOut: punchOut).dayType;
  }

  @override
  Widget build(BuildContext context) {
    final weekDates = _weekDates();
    final labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

    int fullDays = 0, halfDays = 0, absentDays = 0;
    double totalHours = 0;
    final bars = <BarChartGroupData>[];

    for (int i = 0; i < weekDates.length; i++) {
      final key = _dateKey(weekDates[i]);
      final hours = _hoursFor(key);
      totalHours += hours;

      if (!weekDates[i].isAfter(DateTime.now())) {
        final type = _classify(key);
        if (type == DayType.fullDay) fullDays++;
        else if (type == DayType.halfDay) halfDays++;
        else absentDays++;
      }

      bars.add(BarChartGroupData(x: i, barRods: [
        BarChartRodData(toY: hours, color: AppColors.primary, width: 16, borderRadius: BorderRadius.circular(4)),
      ]));
    }

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
                          const Text("Working Hours", style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 180,
                            child: BarChart(
                              BarChartData(
                                maxY: 10,
                                gridData: const FlGridData(show: false),
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
                                        child: Text(labels[v.toInt() % 7], style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                      ),
                                    ),
                                  ),
                                ),
                                barGroups: bars,
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
                        Expanded(child: _statCard("Half", "$halfDays", AppColors.warning, AppColors.warningLight)),
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