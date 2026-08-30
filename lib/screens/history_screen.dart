import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/auto_checkout_fallback.dart';
import 'compensation_activity_screen.dart';
import 'admin_attendance_editor_screen.dart';

class HistoryScreen extends StatefulWidget {
  final String employeeId;
  final String? employeeName;

  // Admin/Super Admin access only. Employees remain read-only.
  final bool viewerIsAdmin;
  final String? viewerAdminId;
  final String? viewerAdminName;

  const HistoryScreen({
    super.key,
    required this.employeeId,
    this.employeeName,
    this.viewerIsAdmin = false,
    this.viewerAdminId,
    this.viewerAdminName,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const MethodChannel _downloadChannel = MethodChannel('workora/downloads');
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
    AutoCheckoutFallback.reconcilePreviousDay(widget.employeeId).then((_) => _load());
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

  /// Classification always runs through AttendanceCalculator using the real
  /// punch-in and punch-out times \u2014 including days where the punch-out
  /// came from an admin-verified auto checkout. There is no forced full-day
  /// override: a verified day is a full day only if it actually reaches 9
  /// gross hours, otherwise it's a mis-punch like any other day.
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

    // Backward compatibility with old single-session records.
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

  DayType? _classify(String dateKey, Map<String, dynamic>? data) {
    if (data == null) return DayType.absent;

    final sessions = _sessionsFromRecord(data);
    if (sessions.isEmpty) return DayType.absent;

    final last = sessions.last;
    if (last.punchOut == null) {
      if (data['status'] == 'Auto Checkout Pending') return DayType.notMarked;
      return _isToday(dateKey) ? null : DayType.absent;
    }

    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: data['workFromHome'] == true,
    ).dayType;
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
        return AppColors.danger;
      case DayType.misPunch:
        return AppColors.danger;
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
        return "Mis-punch";
      case DayType.misPunch:
        return "Mis-punch";
      case DayType.absent:
        return "Absent";
      default:
        return "In Progress";
    }
  }

  String _punchOutText(Map<String, dynamic>? data) {
    if (data?['status'] == 'Auto Checkout Pending') return 'Awaiting admin approval';
    return data?['punchOut']?.toString() ?? '--';
  }

  String _statusText(Map<String, dynamic>? data) {
    if (data?['status'] == 'Auto Checkout Pending') return 'Auto punch-out pending';
    if (data?['status'] == 'Auto Checkout Rejected') return 'Auto punch-out rejected';
    return data?['status']?.toString() ?? 'Not Checked In';
  }

  Future<void> _sendPunchoutRequest(String date, Map<String, dynamic> record) async {
    final existing = await dbRef.child('PunchRequests').child(widget.employeeId).child(date).get();
    if (existing.exists && Map<dynamic, dynamic>.from(existing.value as Map)['status'] == 'pending') return;
    final send = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('Forgot to punch out?'),
      content: const Text('Send a punchout request to admin? Admin will verify it and select the correct checkout time.'),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Send request'))],
    ));
    if (send != true) return;
    await dbRef.child('PunchRequests').child(widget.employeeId).child(date).set({
      'employeeId': widget.employeeId,
      'date': date,
      'type': 'auto_checkout',
      'status': 'pending',
      'punchIn': record['punchIn'],
      'suggestedPunchOut': AttendanceCalculator.autoCheckoutTime,
      'message': 'Employee reported a forgotten checkout and requested verification.',
      'createdAt': DateTime.now().toIso8601String(),
    });
    await dbRef.child('Attendance').child(widget.employeeId).child(date).update({'punchoutRequestStatus': 'pending', 'attendanceStatus': 'Punchout request pending admin verification'});
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Punchout request sent to admin.'))); await _load(); }
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

  String workingHours(Map<String, dynamic>? record) {
    final result = _calculateSessions(record);
    if (result == null) return '--';
    return AttendanceCalculator.formatHours(result.netHours);
  }

  String _sessionSummary(Map<String, dynamic>? record) {
    final sessions = _sessionsFromRecord(record);
    if (sessions.isEmpty) return '--';

    return sessions.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final s = entry.value;
      return 'S$i: ${s.punchIn} → ${s.punchOut ?? '--'}';
    }).join('\n');
  }

  Future<void> _downloadHistory() async {
    final entries = _monthEntries;
    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No records for this month")),
      );
      return;
    }

    final employeeName = (widget.employeeName ?? '').trim().isEmpty
        ? widget.employeeId
        : widget.employeeName!.trim();
    final monthLabel = DateFormat("MMMM yyyy").format(selectedMonth);

    final doc = pw.Document();

    final blue = PdfColor.fromInt(0xFF2563EB);
    final darkBlue = PdfColor.fromInt(0xFF123A8F);
    final lightBlue = PdfColor.fromInt(0xFFEFF4FE);
    final grey = PdfColor.fromInt(0xFF667085);
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 30, 32, 30),
        header: (_) => pw.Container(
          padding: const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: blue, width: 2),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'WORKORA',
                style: pw.TextStyle(
                  color: blue,
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Attendance Report',
                style: pw.TextStyle(color: grey, fontSize: 9),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(color: grey, fontSize: 8),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 14),
          pw.Text(
            'Attendance History',
            style: pw.TextStyle(
              color: darkBlue,
              fontSize: 21,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            monthLabel,
            style: pw.TextStyle(color: grey, fontSize: 11),
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: lightBlue,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Employee Name',
                        style: pw.TextStyle(color: grey, fontSize: 8),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        employeeName,
                        style: pw.TextStyle(
                          color: darkBlue,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 1,
                  height: 32,
                  color: PdfColor.fromInt(0xFFD5DEEF),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Employee ID',
                        style: pw.TextStyle(color: grey, fontSize: 8),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        widget.employeeId,
                        style: pw.TextStyle(
                          color: darkBlue,
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 18),
          pw.TableHelper.fromTextArray(
            headers: const [
              'Date',
              'Sessions',
              'Working Hours',
              'Status',
            ],
            data: entries.map((entry) {
              final type = _classify(entry.key, entry.value);
              final record = entry.value;
              final status = _dayTypeText(type);
              return [
                DateFormat('dd MMM yyyy').format(DateTime.parse(entry.key)),
                record?['punchIn']?.toString() ?? '--',
                _punchOutText(record),
                workingHours(record),
                status,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
            headerDecoration: pw.BoxDecoration(color: blue),
            cellStyle: const pw.TextStyle(fontSize: 8),
            cellPadding: const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
            cellAlignment: pw.Alignment.centerLeft,
            oddRowDecoration: pw.BoxDecoration(
              color: PdfColor.fromInt(0xFFF8FAFD),
            ),
            border: pw.TableBorder.all(
              color: PdfColor.fromInt(0xFFD9E1EE),
              width: 0.5,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Text(
            'Generated from Workora attendance records • $monthLabel',
            style: pw.TextStyle(color: grey, fontSize: 8),
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    try {
      final result = await _downloadChannel.invokeMethod<String>(
        'savePdfToDownloads',
        {
          'fileName':
              'attendance_${widget.employeeId}_${selectedMonth.year}_${selectedMonth.month.toString().padLeft(2, '0')}.pdf',
          'bytes': Uint8List.fromList(bytes),
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result ?? 'Attendance report downloaded to Downloads/Workora',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ?? 'Could not save the attendance report.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = _monthEntries;
    int full = 0, misPunch = 0, absent = 0;
    for (final e in entries) {
      final type = _classify(e.key, e.value);
      if (type == DayType.fullDay) full++;
      else if (type == DayType.misPunch) misPunch++;
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
                            Expanded(child: _statBox("Mis-punch", misPunch, AppColors.danger, AppColors.dangerLight)),
                            const SizedBox(width: 8),
                            Expanded(child: _statBox("Absent", absent, AppColors.danger, AppColors.dangerLight)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  _buildCompensationSummary(entries),
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
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _downloadHistory,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text(
                        "Download History",
                        style: TextStyle(fontWeight: FontWeight.bold),
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
                      final isAutoPunchOut = e.value?['autoPunchOut'] == true && e.value?['approvedAutoCheckout'] != true;

                      return InkWell(
                        onTap: widget.viewerIsAdmin
                            ? () async {
                                final changed = await Navigator.push<bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => AdminAttendanceEditorScreen(
                                      adminId: widget.viewerAdminId ?? '',
                                      adminName: widget.viewerAdminName ?? 'Admin',
                                      employeeId: widget.employeeId,
                                      employeeName: widget.employeeName ?? widget.employeeId,
                                      initialDate: date,
                                    ),
                                  ),
                                );
                                if (changed == true && mounted) {
                                  await _load();
                                }
                              }
                            : (isAutoPunchOut
                                ? () => _sendPunchoutRequest(e.key, e.value!)
                                : null),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: isAutoPunchOut ? AppColors.warning.withOpacity(.08) : AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
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
                                  _rowLine(Icons.schedule, "Sessions", _sessionSummary(e.value)),
                                  _rowLine(Icons.timer_outlined, "Working hours", workingHours(e.value)),
                                  _rowLine(Icons.assignment_turned_in, "Status", _statusText(e.value)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: _dayTypeColor(dayType).withOpacity(0.12), borderRadius: BorderRadius.circular(20)),
                              child: Text(
                                isAutoPunchOut ? 'Auto punch-out' : _dayTypeText(dayType),
                                style: TextStyle(color: _dayTypeColor(dayType), fontWeight: FontWeight.bold, fontSize: 11),
                              ),
                            ),
                            if (widget.viewerIsAdmin) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.edit_outlined, size: 17, color: AppColors.primary),
                            ],
                          ],
                          ),
                        ),
                      );
                    }),

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

  /// Every entry that contributes to the MONTH balance, built once and
  /// shared by the summary card and the activity screen so they can never
  /// drift apart. This is intentionally month-scoped, not all-time \u2014
  /// the all-time figure is a single running number without a line-by-line
  /// breakdown across every month.
  List<Map<String, String>> _buildActivity(List<MapEntry<String, Map<String, dynamic>?>> entries) {
    final activity = <Map<String, String>>[];
    for (final entry in entries) {
      final record = entry.value;
      if (record == null) continue;
      if (record['status'] == 'Auto Checkout Pending') {
        activity.add({'date': entry.key, 'text': 'Auto punch-out request sent to admin for verification'});
        continue;
      }
      if (record['status'] == 'Auto Checkout Rejected') {
        activity.add({'date': entry.key, 'text': 'Auto punch-out request rejected by admin'});
        continue;
      }
      final result = _classify(entry.key, record);
      final calculation = _calculateSessions(record);
      if (result == DayType.misPunch && calculation != null) activity.add({'date': entry.key, 'text': 'Mis-punch: ${AttendanceCalculator.formatHours(calculation.shortfallHours)} added to compensation'});
      if ((calculation?.extraHours ?? 0) > 0) activity.add({'date': entry.key, 'text': 'Extra work: ${AttendanceCalculator.formatHours(calculation!.extraHours)} deducted from compensation'});
      if (record['approvedAutoCheckout'] == true) activity.add({'date': entry.key, 'text': 'Auto punch-out verified and approved by admin'});
    }
    return activity;
  }

  /// Shows both totals on the History screen itself, total outstanding time
  /// first, this month's figure below it, with a button through to
  /// CompensationActivityScreen for the month's line-by-line breakdown.
  Widget _buildCompensationSummary(List<MapEntry<String, Map<String, dynamic>?>> entries) {
    final monthOutstanding = _calculateOutstandingMinutes(entries);
    final allTimeOutstanding = _calculateAllTimeOutstandingMinutes();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Compensation', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Text(
            'Total outstanding time: ${AttendanceCalculator.formatHours(allTimeOutstanding / 60)}',
            style: TextStyle(color: allTimeOutstanding > 0 ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            'This month: ${AttendanceCalculator.formatHours(monthOutstanding / 60)}',
            style: TextStyle(color: monthOutstanding > 0 ? AppColors.danger : AppColors.success, fontWeight: FontWeight.w700, fontSize: 16),
          ),
          const SizedBox(height: 3),
          const Text('The total runs across every month of attendance; this month figure only covers the selected month.', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 42,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CompensationActivityScreen(
                    monthLabel: DateFormat("MMMM yyyy").format(selectedMonth),
                    monthOutstandingMinutes: monthOutstanding,
                    allTimeOutstandingMinutes: allTimeOutstanding,
                    activity: _buildActivity(entries),
                  ),
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.list_alt, size: 18),
              label: const Text("View Activity", style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  /// Outstanding for the SELECTED MONTH only: running total of mis-punch
  /// shortfalls minus extra-work hours worked on later days this month,
  /// floored at zero.
  ///
  /// Still-unverified auto punch-outs (autoPunchOut == true) are skipped: an
  /// employee who forgot to check out doesn't accrue shortfall off the 11:59
  /// PM placeholder. Only once admin verifies and sets the real time (which
  /// clears autoPunchOut) does that day enter this calculation, using the
  /// admin-set time.
  int _calculateOutstandingMinutes(List<MapEntry<String, Map<String, dynamic>?>> entries) {
    // entries arrives most-recent-first; process oldest-to-newest so extra
    // work only offsets shortfall that happened earlier in the month.
    final chronological = entries.reversed.toList();
    var balance = 0;
    for (final entry in chronological) {
      final record = entry.value;
      if (record == null) continue;
      if (record['punchIn'] == null || record['punchOut'] == null || record['autoPunchOut'] == true || record['workFromHome'] == true) continue;
      final result = AttendanceCalculator.calculate(punchIn: record['punchIn'].toString(), punchOut: record['punchOut'].toString());
      balance += (result.shortfallHours * 60).round();
      balance -= (result.extraHours * 60).round();
      if (balance < 0) balance = 0;
    }
    return balance;
  }

  /// Outstanding across EVERY month of attendance ever recorded for this
  /// employee, same shortfall-minus-extra running balance, floored at zero.
  /// This is the lifetime figure shown alongside the month figure.
  int _calculateAllTimeOutstandingMinutes() {
    final dates = attendanceData.keys.map((k) => k.toString()).toList()..sort();
    var balance = 0;
    for (final date in dates) {
      final record = Map<String, dynamic>.from(attendanceData[date] as Map);
      if (record['punchIn'] == null || record['punchOut'] == null || record['autoPunchOut'] == true || record['workFromHome'] == true) continue;
      final result = AttendanceCalculator.calculate(punchIn: record['punchIn'].toString(), punchOut: record['punchOut'].toString());
      balance += (result.shortfallHours * 60).round();
      balance -= (result.extraHours * 60).round();
      if (balance < 0) balance = 0;
    }
    return balance;
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