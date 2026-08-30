import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../widgets/punch_card.dart';

class AttendanceTabScreen extends StatefulWidget {
  final String employeeId;

  const AttendanceTabScreen({super.key, required this.employeeId});

  @override
  State<AttendanceTabScreen> createState() => _AttendanceTabScreenState();
}

class _AttendanceTabScreenState extends State<AttendanceTabScreen> {
  late DatabaseReference dbRef;
  bool showList = false;
  bool loading = true;
  Map<dynamic, dynamic> attendanceData = {};

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => loading = true);
    try {
      final snapshot = await dbRef.child("Attendance").child(widget.employeeId).get();
      if (snapshot.exists) {
        attendanceData = Map<dynamic, dynamic>.from(snapshot.value as Map);
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => loading = false);
  }

  bool _isToday(String dateKey) {
    final now = DateTime.now();
    final todayKey = "${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}";
    return dateKey == todayKey;
  }

  /// Classification always runs through AttendanceCalculator using the real
  /// punch-in and punch-out times \u2014 including admin-verified auto
  /// checkouts. There is no forced full-day override: a verified day is a
  /// full day only if it actually reaches 9 gross hours.
  DayType? _classify(String dateKey, Map data) {
    final punchIn = data["punchIn"]?.toString();
    final punchOut = data["punchOut"]?.toString();
    if (punchIn == null) return DayType.absent;
    if (punchOut == null) return _isToday(dateKey) ? null : DayType.absent;
    return AttendanceCalculator.calculate(punchIn: punchIn, punchOut: punchOut, workFromHome: data['workFromHome'] == true).dayType;
  }

  Color _dayTypeColor(DayType? type) {
    switch (type) {
      case DayType.fullDay: return AppColors.success;
      case DayType.halfDay: return AppColors.danger;
      case DayType.misPunch: return AppColors.danger;
      case DayType.absent: return AppColors.danger;
      default: return AppColors.info;
    }
  }

  String _dayTypeText(DayType? type) {
    switch (type) {
      case DayType.fullDay: return "Full Day";
      case DayType.halfDay: return "Mis-punch";
      case DayType.misPunch: return "Mis-punch";
      case DayType.absent: return "Absent";
      default: return "In Progress";
    }
  }

  @override
  Widget build(BuildContext context) {
    final dates = attendanceData.keys.toList().cast<String>()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: AppGradients.background),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Attendance", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(24), boxShadow: AppShadows.card),
                      child: Row(
                        children: [
                          _toggleChip("Today", !showList, () => setState(() => showList = false)),
                          _toggleChip("List", showList, () => setState(() => showList = true)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: showList
                    ? _buildList(dates)
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: PunchCard(employeeId: widget.employeeId, compact: false),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toggleChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(color: selected ? AppColors.primary : Colors.transparent, borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(color: selected ? Colors.white : AppColors.textSecondary, fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }

  Widget _buildList(List<String> dates) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (dates.isEmpty) return const Center(child: Text("No Attendance Found", style: TextStyle(color: AppColors.textSecondary)));

    return RefreshIndicator(
      onRefresh: _loadHistory,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        itemCount: dates.length,
        itemBuilder: (context, index) {
          final date = dates[index];
          final data = Map<dynamic, dynamic>.from(attendanceData[date]);
          final dayType = _classify(date, data);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(date, style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: _dayTypeColor(dayType).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                      child: Text(_dayTypeText(dayType), style: TextStyle(color: _dayTypeColor(dayType), fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text("In: ${data["punchIn"] ?? "--"}   Out: ${data["punchOut"] ?? "--"}", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
              ],
            ),
          );
        },
      ),
    );
  }
}