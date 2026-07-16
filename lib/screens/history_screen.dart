import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

class HistoryScreen extends StatefulWidget {
  final String employeeId;
  final String? employeeName;

  const HistoryScreen({super.key, required this.employeeId, this.employeeName});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late DatabaseReference dbRef;

  Map<String, dynamic> attendanceData = {};
  bool loading = true;
  DateTime selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _load();
  }

  Future<void> _load() async {
    setState(() => loading = true);
    try {
      final snapshot = await dbRef.child("Attendance").child(widget.employeeId).get();
      if (snapshot.exists) {
        final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);
        attendanceData = raw.map((k, v) => MapEntry(k.toString(), Map<String, dynamic>.from(v as Map)));
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() => loading = false);
  }

  String _dateKey(DateTime d) => "${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  bool _isToday(String dateKey) => dateKey == _dateKey(DateTime.now());

  DayType? _classify(String dateKey, Map<String, dynamic>? data) {
    if (data == null || data["punchIn"] == null) return DayType.absent;
    final punchOut = data["punchOut"]?.toString();
    if (punchOut == null) return _isToday(dateKey) ? null : DayType.absent;
    return AttendanceCalculator.calculate(punchIn: data["punchIn"].toString(), punchOut: punchOut).dayType;
  }

  double _hoursFor(Map<String, dynamic>? data) {
    if (data == null) return 0;
    final punchIn = data["punchIn"]?.toString();
    final punchOut = data["punchOut"]?.toString();
    if (punchIn == null || punchOut == null) return 0;
    return AttendanceCalculator.calculate(punchIn: punchIn, punchOut: punchOut).netHours;
  }

  /// Every day in the selected month, up to today, gets an entry \u2014
  /// treated as a working day even if the employee never opened the
  /// app that day (which then correctly shows as Absent).
  List<MapEntry<String, Map<String, dynamic>?>> get _monthEntries {
    final monthStart = DateTime(selectedMonth.year, selectedMonth.month, 1);
    final monthEnd = DateTime(selectedMonth.year, selectedMonth.month + 1, 0);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final lastDay = monthEnd.isAfter(todayOnly) ? todayOnly : monthEnd;

    if (monthStart.isAfter(todayOnly)) return [];

    final entries = <MapEntry<String, Map<String, dynamic>?>>[];
    for (DateTime d = monthStart; !d.isAfter(lastDay); d = d.add(const Duration(days: 1))) {
      final key = _dateKey(d);
      entries.add(MapEntry(key, attendanceData[key] as Map<String, dynamic>?));
    }
    return entries.reversed.toList();
  }

  Color _dayTypeColor(DayType? type) {
    switch (type) {
      case DayType.fullDay:
        return AppColors.success;
      case DayType.halfDay:
        return AppColors.warning;
      case DayType.absent:
        return AppColors.danger;
      default:
        return AppColors.info;
    }
  }

  String _dayTypeText(DayType? type) {
    switch (type) {
      case DayType.fullDay:
        return "Full Day";
      case DayType.halfDay:
        return "Half Day";
      case DayType.absent:
        return "Absent";
      default:
        return "In Progress";
    }
  }

  Future<void> _pickMonth() async {
    final months = List.generate(12, (i) => DateTime(DateTime.now().year, DateTime.now().month - i, 1));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: months
              .map((m) => ListTile(
                    title: Text(DateFormat("MMMM yyyy").format(m)),
                    onTap: () => Navigator.pop(context, m),
                  ))
              .toList(),
        ),
      ),
    );
    if (picked != null) setState(() => selectedMonth = picked);
  }

  Future<void> _downloadHistory() async {
    final entries = _monthEntries;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("No records for this month")));
      return;
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) => [
          pw.Header(level: 0, child: pw.Text("Attendance History", style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold))),
          pw.Text("${widget.employeeName ?? widget.employeeId} \u2014 ${DateFormat("MMMM yyyy").format(selectedMonth)}"),
          pw.SizedBox(height: 16),
          pw.Table.fromTextArray(
            headers: ["Date", "Punch In", "Punch Out", "Status"],
            data: entries.map((e) {
              final dayType = _classify(e.key, e.value);
              return [e.key, e.value?["punchIn"]?.toString() ?? "--", e.value?["punchOut"]?.toString() ?? "--", _dayTypeText(dayType)];
            }).toList(),
          ),
        ],
      ),
    );

    final bytes = await doc.save();
    final dir = await getApplicationDocumentsDirectory();
    final file = File("${dir.path}/attendance_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(bytes);
    await Share.shareXFiles([XFile(file.path)], subject: "Attendance History");
  }

  @override
  Widget build(BuildContext context) {
    final entries = _monthEntries;
    int full = 0, half = 0, absent = 0;
    for (final e in entries) {
      final type = _classify(e.key, e.value);
      if (type == DayType.fullDay) full++;
      else if (type == DayType.halfDay) half++;
      else if (type == DayType.absent) absent++;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Attendance History", style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text("This Month Overview", style: TextStyle(fontWeight: FontWeight.bold)),
                            IconButton(icon: const Icon(Icons.calendar_today, color: AppColors.primary), onPressed: _pickMonth),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: _statBox("Full Day", full, AppColors.success, AppColors.successLight)),
                            const SizedBox(width: 8),
                            Expanded(child: _statBox("Half Day", half, AppColors.warning, AppColors.warningLight)),
                            const SizedBox(width: 8),
                            Expanded(child: _statBox("Absent", absent, AppColors.danger, AppColors.dangerLight)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("Month", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                  const SizedBox(height: 6),
                  InkWell(
                    onTap: _pickMonth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.divider),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today, size: 16, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Text(DateFormat("MMMM yyyy").format(selectedMonth), style: const TextStyle(fontWeight: FontWeight.bold)),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (entries.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: Text("No records this month", style: TextStyle(color: AppColors.textSecondary))),
                    )
                  else
                    ...entries.map((e) {
                      final dayType = _classify(e.key, e.value);
                      final date = DateTime.parse(e.key);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            SizedBox(
                              width: 54,
                              child: Column(
                                children: [
                                  Text(DateFormat("EEE").format(date), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                                  Text("${date.day}", style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 20)),
                                  Text(DateFormat("MMM yyyy").format(date), style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _rowLine(Icons.login, "Punch In", e.value?["punchIn"]?.toString() ?? "--"),
                                  _rowLine(Icons.logout, "Punch Out", e.value?["punchOut"]?.toString() ?? "--"),
                                  _rowLine(Icons.assignment_turned_in, "Status", e.value?["status"]?.toString() ?? "Not Checked In"),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _dayTypeColor(dayType).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                _dayTypeText(dayType),
                                style: TextStyle(color: _dayTypeColor(dayType), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: _downloadHistory,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
                      ),
                      icon: const Icon(Icons.download),
                      label: const Text("Download History", style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statBox(String label, int value, Color color, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12), border: Border(top: BorderSide(color: color, width: 3))),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontSize: 11)),
          const SizedBox(height: 4),
          Text("$value", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _rowLine(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.primary),
          const SizedBox(width: 6),
          Text("$label:", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
          const SizedBox(width: 6),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}