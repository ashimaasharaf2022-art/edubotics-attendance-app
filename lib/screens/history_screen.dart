import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../utils/web_download/web_download.dart';
import 'compensation_activity_screen.dart';
import 'compensation_request_screen.dart';
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
  static const MethodChannel _downloadChannel =
      MethodChannel('workora/downloads');

  late DatabaseReference dbRef;

  Map<String, dynamic> attendanceData = {};

  bool loading = true;

  DateTime selectedMonth =
      DateTime(DateTime.now().year, DateTime.now().month, 1);

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _load();
  }

  // ---------------------------------------------------------------------------
  // LOAD ATTENDANCE
  // ---------------------------------------------------------------------------

  Future<void> _load() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final snapshot =
          await dbRef.child("Attendance").child(widget.employeeId).get();

      if (snapshot.exists && snapshot.value is Map) {
        final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);

        attendanceData = raw.map(
          (k, v) => MapEntry(
            k.toString(),
            v is Map
                ? Map<String, dynamic>.from(v)
                : <String, dynamic>{},
          ),
        );
      } else {
        attendanceData = {};
      }
    } catch (_) {
      attendanceData = {};
    }

    if (!mounted) return;

    setState(() => loading = false);
  }

  // ---------------------------------------------------------------------------
  // DATE HELPERS
  // ---------------------------------------------------------------------------

  String _dateKey(DateTime d) {
    return "${d.year}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  bool _isToday(String dateKey) {
    return dateKey == _dateKey(DateTime.now());
  }

  // ---------------------------------------------------------------------------
  // SESSION PARSING
  // ---------------------------------------------------------------------------

  List<AttendanceSession> _sessionsFromRecord(
    Map<String, dynamic>? record,
  ) {
    if (record == null) {
      return <AttendanceSession>[];
    }

    final sessions = <AttendanceSession>[];

    final raw = record["sessions"];

    if (raw is List) {
      for (final item in raw) {
        if (item is Map && item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item["punchIn"].toString(),
              punchOut: item["punchOut"]?.toString(),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort(
          (a, b) => a.key.toString().compareTo(b.key.toString()),
        );

      for (final entry in entries) {
        final item = entry.value;

        if (item is Map && item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn: item["punchIn"].toString(),
              punchOut: item["punchOut"]?.toString(),
            ),
          );
        }
      }
    }

    // Backward compatibility with old single-session records.
    if (sessions.isEmpty && record["punchIn"] != null) {
      sessions.add(
        AttendanceSession(
          punchIn: record["punchIn"].toString(),
          punchOut: record["punchOut"]?.toString(),
        ),
      );
    }

    return sessions;
  }

  // ---------------------------------------------------------------------------
  // CALCULATE ATTENDANCE
  // ---------------------------------------------------------------------------

  AttendanceResult? _calculateSessions(
    Map<String, dynamic>? record,
  ) {
    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) {
      return null;
    }

    // IMPORTANT:
    // MIS-PUNCH is handled before this method is called.
    //
    // Therefore the temporary "11:59 PM" value is never used for attendance
    // calculation.
    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    );
  }

  // ---------------------------------------------------------------------------
  // CLASSIFICATION
  // ---------------------------------------------------------------------------

  DayType? _classify(
    String dateKey,
    Map<String, dynamic>? data,
  ) {
    if (data == null) {
      return DayType.absent;
    }

    final status = data['status']?.toString().toUpperCase();

    // MIS-PUNCH is only a temporary workflow state.
    //
    // It must NOT:
    // - use temporaryPunchOut
    // - use 11:59 PM
    // - become Work-Pending automatically
    //
    // Today:
    //   show In Progress / pending state.
    //
    // Past day:
    //   keep it outside the three attendance classifications until
    //   admin corrects the actual punch-out.
    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        data['autoPunchOut'] == true) {
      return null;
    }

    final sessions = _sessionsFromRecord(data);

    if (sessions.isEmpty) {
      return DayType.absent;
    }

    // If the last session is still open, it is currently in progress.
    final last = sessions.last;

    final lastPunchOut = last.punchOut?.trim();

    if (lastPunchOut == null || lastPunchOut.isEmpty) {
      return _isToday(dateKey) ? null : DayType.absent;
    }

    final result = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: data['workFromHome'] == true,
    );

    return result.dayType;
  }

  // ---------------------------------------------------------------------------
  // MONTH ENTRIES
  // ---------------------------------------------------------------------------

  /// Every date in the selected month up to today gets an entry.
  ///
  /// A date with no attendance record is therefore classified as Absent.
  List<MapEntry<String, Map<String, dynamic>?>> get _monthEntries {
    final monthStart =
        DateTime(selectedMonth.year, selectedMonth.month, 1);

    final monthEnd =
        DateTime(selectedMonth.year, selectedMonth.month + 1, 0);

    final today = DateTime.now();

    final todayOnly =
        DateTime(today.year, today.month, today.day);

    final lastDay =
        monthEnd.isAfter(todayOnly) ? todayOnly : monthEnd;

    if (monthStart.isAfter(todayOnly)) {
      return [];
    }

    final entries =
        <MapEntry<String, Map<String, dynamic>?>>[];

    for (
      DateTime d = monthStart;
      !d.isAfter(lastDay);
      d = d.add(const Duration(days: 1))
    ) {
      final key = _dateKey(d);

      entries.add(
        MapEntry(
          key,
          attendanceData[key] as Map<String, dynamic>?,
        ),
      );
    }

    return entries.reversed.toList();
  }

  // ---------------------------------------------------------------------------
  // DAY TYPE UI
  // ---------------------------------------------------------------------------

  Color _dayTypeColor(DayType? type) {
    switch (type) {
      case DayType.fullDay:
        return AppColors.success;

      case DayType.workPending:
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

      case DayType.workPending:
        return "Work-Pending";

      case DayType.absent:
        return "Absent";

      default:
        return "In Progress";
    }
  }

  // ---------------------------------------------------------------------------
  // PUNCH-OUT DISPLAY
  // ---------------------------------------------------------------------------

  String _punchOutText(
    Map<String, dynamic>? data,
  ) {
    final status = data?['status']?.toString().toUpperCase();

    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        data?['autoPunchOut'] == true) {
      return 'Awaiting admin correction';
    }

    return data?['punchOut']?.toString() ?? '--';
  }

  String _statusText(
    Map<String, dynamic>? data,
  ) {
    final status = data?['status']?.toString().toUpperCase();

    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        data?['autoPunchOut'] == true) {
      return 'MIS-PUNCH — awaiting admin correction';
    }

    if (status == 'AUTO CHECKOUT REJECTED') {
      return 'Punch-out correction rejected';
    }

    return data?['status']?.toString() ?? 'Not Checked In';
  }

  // ---------------------------------------------------------------------------
  // SEND MIS-PUNCH REQUEST
  // ---------------------------------------------------------------------------

  Future<void> _sendPunchoutRequest(
    String date,
    Map<String, dynamic> record,
  ) async {
    try {
      final requestRef = dbRef
          .child('PunchRequests')
          .child(widget.employeeId)
          .child(date);

      final existing = await requestRef.get();

      if (existing.exists && existing.value is Map) {
        final existingMap =
            Map<dynamic, dynamic>.from(existing.value as Map);

        if (existingMap['status']?.toString().toLowerCase() ==
            'pending') {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'A punchout request is already pending admin review.',
                ),
              ),
            );
          }
          return;
        }
      }

      final send = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Forgot to punch out?'),
          content: const Text(
            'Send a punchout request to admin? '
            'Admin will verify the attendance and select the correct '
            'checkout time.',
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, true),
              child: const Text('Send request'),
            ),
          ],
        ),
      );

      if (send != true) {
        return;
      }

      // IMPORTANT:
      // Do NOT set punchOut to 11:59 PM.
      //
      // The employee's real punch-out remains unknown until admin
      // selects it.
      await requestRef.set({
        'employeeId': widget.employeeId,
        'employeeName':
            (widget.employeeName ?? '').trim().isEmpty
                ? widget.employeeId
                : widget.employeeName!.trim(),
        'date': date,
        'type': 'mis_punch',
        'status': 'pending',
        'punchIn': record['punchIn'],
        'message':
            'Employee reported a forgotten checkout and requested '
            'admin verification.',
        'createdAt':
            DateTime.now().toIso8601String(),
      });

      await dbRef
          .child('Attendance')
          .child(widget.employeeId)
          .child(date)
          .update({
        'punchoutRequestStatus': 'pending',
        'status': 'MIS-PUNCH',
        'misPunch': true,
        'attendanceStatus':
            'MIS-PUNCH — awaiting admin punch-out correction',
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Punchout request sent to admin.',
          ),
        ),
      );

      await _load();
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send punchout request: $e',
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // MONTH PICKER
  // ---------------------------------------------------------------------------

  Future<void> _pickMonth() async {
    final months = List.generate(
      12,
      (i) => DateTime(
        DateTime.now().year,
        DateTime.now().month - i,
        1,
      ),
    );

    final picked =
        await showModalBottomSheet<DateTime>(
      context: context,
      builder: (_) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: months
              .map(
                (m) => ListTile(
                  title: Text(
                    DateFormat("MMMM yyyy").format(m),
                  ),
                  onTap: () =>
                      Navigator.pop(context, m),
                ),
              )
              .toList(),
        ),
      ),
    );

    if (picked != null && mounted) {
      setState(() {
        selectedMonth = picked;
      });
    }
  }

  // ---------------------------------------------------------------------------
  // WORKING HOURS
  // ---------------------------------------------------------------------------

  String workingHours(
    Map<String, dynamic>? record,
  ) {
    if (record == null) {
      return '--';
    }

    final status =
        record['status']?.toString().toUpperCase();

    // Never calculate hours from MIS-PUNCH.
    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        record['autoPunchOut'] == true) {
      return '--';
    }

    final result = _calculateSessions(record);

    if (result == null) {
      return '--';
    }

    return AttendanceCalculator.formatHours(
      result.netHours,
    );
  }

  // ---------------------------------------------------------------------------
  // SESSION SUMMARY
  // ---------------------------------------------------------------------------

  String _sessionSummary(
    Map<String, dynamic>? record,
  ) {
    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) {
      return '--';
    }

    return sessions.asMap().entries.map((entry) {
      final i = entry.key + 1;
      final s = entry.value;

      return 'S$i: ${s.punchIn} → ${s.punchOut ?? '--'}';
    }).join('\n');
  }

  String _sessionLocationSummary(
    Map<String, dynamic>? record,
  ) {
    if (record == null) return '--';

    final locations = <String>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (var i = 0; i < raw.length; i++) {
        final item = raw[i];
        if (item is! Map || item['punchIn'] == null) continue;

        final inAddress = item['punchInAddress']?.toString().trim();
        final outAddress = item['punchOutAddress']?.toString().trim();

        final inLat = item['punchInLat']?.toString();
        final inLng = item['punchInLng']?.toString();
        final outLat = item['punchOutLat']?.toString();
        final outLng = item['punchOutLng']?.toString();

        final inLocation = (inAddress != null && inAddress.isNotEmpty)
            ? inAddress
            : (inLat != null && inLng != null
                ? '$inLat, $inLng'
                : '--');

        final outLocation = (outAddress != null && outAddress.isNotEmpty)
            ? outAddress
            : (outLat != null && outLng != null
                ? '$outLat, $outLng'
                : '--');

        locations.add('S${i + 1} IN: $inLocation\n   OUT: $outLocation');
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));

      var index = 0;
      for (final entry in entries) {
        final item = entry.value;
        if (item is! Map || item['punchIn'] == null) continue;

        index++;
        final inAddress = item['punchInAddress']?.toString().trim();
        final outAddress = item['punchOutAddress']?.toString().trim();
        final inLat = item['punchInLat']?.toString();
        final inLng = item['punchInLng']?.toString();
        final outLat = item['punchOutLat']?.toString();
        final outLng = item['punchOutLng']?.toString();

        final inLocation = (inAddress != null && inAddress.isNotEmpty)
            ? inAddress
            : (inLat != null && inLng != null
                ? '$inLat, $inLng'
                : '--');

        final outLocation = (outAddress != null && outAddress.isNotEmpty)
            ? outAddress
            : (outLat != null && outLng != null
                ? '$outLat, $outLng'
                : '--');

        locations.add('S$index IN: $inLocation\n   OUT: $outLocation');
      }
    }

    // Backward compatibility for older single-session records.
    if (locations.isEmpty &&
        (record['punchInAddress'] != null ||
            record['punchInLat'] != null ||
            record['punchOutAddress'] != null ||
            record['punchOutLat'] != null)) {
      final inAddress = record['punchInAddress']?.toString().trim();
      final outAddress = record['punchOutAddress']?.toString().trim();
      final inLat = record['punchInLat']?.toString();
      final inLng = record['punchInLng']?.toString();
      final outLat = record['punchOutLat']?.toString();
      final outLng = record['punchOutLng']?.toString();

      final inLocation = (inAddress != null && inAddress.isNotEmpty)
          ? inAddress
          : (inLat != null && inLng != null ? '$inLat, $inLng' : '--');
      final outLocation = (outAddress != null && outAddress.isNotEmpty)
          ? outAddress
          : (outLat != null && outLng != null ? '$outLat, $outLng' : '--');

      locations.add('IN: $inLocation\nOUT: $outLocation');
    }

    return locations.isEmpty ? '--' : locations.join('\n');
  }

  // ---------------------------------------------------------------------------
  // DOWNLOAD HISTORY
  // ---------------------------------------------------------------------------

  Future<void> _downloadHistory() async {
    final entries = _monthEntries;

    if (entries.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("No records for this month"),
        ),
      );
      return;
    }

    final employeeName =
        (widget.employeeName ?? '').trim().isEmpty
            ? widget.employeeId
            : widget.employeeName!.trim();

    final monthLabel =
        DateFormat("MMMM yyyy").format(selectedMonth);

    final doc = pw.Document();

    final blue =
        PdfColor.fromInt(0xFF2563EB);

    final darkBlue =
        PdfColor.fromInt(0xFF123A8F);

    final lightBlue =
        PdfColor.fromInt(0xFFEFF4FE);

    final grey =
        PdfColor.fromInt(0xFF667085);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(
          32,
          30,
          32,
          30,
        ),
        header: (_) => pw.Container(
          padding:
              const pw.EdgeInsets.only(bottom: 10),
          decoration: pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(
                color: blue,
                width: 2,
              ),
            ),
          ),
          child: pw.Row(
            mainAxisAlignment:
                pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'WORKORA',
                style: pw.TextStyle(
                  color: blue,
                  fontSize: 13,
                  fontWeight:
                      pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Attendance Report',
                style: pw.TextStyle(
                  color: grey,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        footer: (context) => pw.Align(
          alignment:
              pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(
              color: grey,
              fontSize: 8,
            ),
          ),
        ),
        build: (_) => [
          pw.SizedBox(height: 14),

          pw.Text(
            'Attendance History',
            style: pw.TextStyle(
              color: darkBlue,
              fontSize: 21,
              fontWeight:
                  pw.FontWeight.bold,
            ),
          ),

          pw.SizedBox(height: 4),

          pw.Text(
            monthLabel,
            style: pw.TextStyle(
              color: grey,
              fontSize: 11,
            ),
          ),

          pw.SizedBox(height: 16),

          pw.Container(
            padding:
                const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: lightBlue,
              borderRadius:
                  pw.BorderRadius.circular(8),
            ),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Employee Name',
                        style: pw.TextStyle(
                          color: grey,
                          fontSize: 8,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        employeeName,
                        style: pw.TextStyle(
                          color: darkBlue,
                          fontSize: 12,
                          fontWeight:
                              pw.FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                pw.Container(
                  width: 1,
                  height: 32,
                  color: PdfColor.fromInt(
                    0xFFD5DEEF,
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment:
                        pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Employee ID',
                        style: pw.TextStyle(
                          color: grey,
                          fontSize: 8,
                        ),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text(
                        widget.employeeId,
                        style: pw.TextStyle(
                          color: darkBlue,
                          fontSize: 12,
                          fontWeight:
                              pw.FontWeight.bold,
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
              'Punch-out',
              'Working Hours',
              'Status',
            ],
            data: entries.map((entry) {
              final type =
                  _classify(
                entry.key,
                entry.value,
              );

              final record = entry.value;

              final status =
                  _dayTypeText(type);

              return [
                DateFormat('dd MMM yyyy').format(
                  DateTime.parse(entry.key),
                ),
                _sessionSummary(record),
                _punchOutText(record),
                workingHours(record),
                record?['status'] == 'MIS-PUNCH'
                    ? 'MIS-PUNCH'
                    : status,
              ];
            }).toList(),
            headerStyle: pw.TextStyle(
              color: PdfColors.white,
              fontSize: 8,
              fontWeight:
                  pw.FontWeight.bold,
            ),
            headerDecoration:
                pw.BoxDecoration(
              color: blue,
            ),
            cellStyle:
                const pw.TextStyle(
              fontSize: 8,
            ),
            cellPadding:
                const pw.EdgeInsets.symmetric(
              horizontal: 6,
              vertical: 6,
            ),
            cellAlignment:
                pw.Alignment.centerLeft,
            oddRowDecoration:
                pw.BoxDecoration(
              color: PdfColor.fromInt(
                0xFFF8FAFD,
              ),
            ),
            border:
                pw.TableBorder.all(
              color: PdfColor.fromInt(
                0xFFD9E1EE,
              ),
              width: 0.5,
            ),
          ),

          pw.SizedBox(height: 16),

          pw.Text(
            'Generated from Workora attendance records • $monthLabel',
            style: pw.TextStyle(
              color: grey,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );

    final bytes = await doc.save();

    // -----------------------------------------------------------------------
    // WEB
    // -----------------------------------------------------------------------

    if (kIsWeb) {
      try {
        await downloadBytesWeb(
          Uint8List.fromList(bytes),
          'attendance_${widget.employeeId}_${selectedMonth.year}_${selectedMonth.month.toString().padLeft(2, '0')}.pdf',
          mimeType: 'application/pdf',
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Attendance report downloaded.'),
          ),
        );
      } catch (e) {
        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Could not download the report: $e'),
          ),
        );
      }

      return;
    }

    // -----------------------------------------------------------------------
    // ANDROID / NATIVE
    // -----------------------------------------------------------------------

    try {
      final result =
          await _downloadChannel.invokeMethod<String>(
        'savePdfToDownloads',
        {
          'fileName':
              'attendance_${widget.employeeId}_${selectedMonth.year}_${selectedMonth.month.toString().padLeft(2, '0')}.pdf',
          'bytes':
              Uint8List.fromList(bytes),
        },
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result ??
                'Attendance report downloaded to Downloads/Workora',
          ),
        ),
      );
    } on PlatformException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.message ??
                'Could not save the attendance report.',
          ),
        ),
      );
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final entries = _monthEntries;

    int full = 0;
    int workPending = 0;
    int absent = 0;
    int misPunchPending = 0;

    for (final e in entries) {
      final record = e.value;

      final status =
          record?['status']?.toString().toUpperCase();

      if (status == 'MIS-PUNCH' ||
          status == 'AUTO CHECKOUT PENDING' ||
          record?['autoPunchOut'] == true) {
        misPunchPending++;
        continue;
      }

      final type =
          _classify(e.key, record);

      if (type == DayType.fullDay) {
        full++;
      } else if (type == DayType.workPending) {
        workPending++;
      } else if (type == DayType.absent) {
        absent++;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,

      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "Attendance History",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
      ),

      body: loading
          ? const Center(
              child:
                  CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding:
                    const EdgeInsets.all(20),
                children: [
                  // -----------------------------------------------------------
                  // MONTH OVERVIEW
                  // -----------------------------------------------------------

                  Container(
                    padding:
                        const EdgeInsets.all(16),
                    decoration:
                        BoxDecoration(
                      color: AppColors.surface,
                      borderRadius:
                          BorderRadius.circular(16),
                      boxShadow:
                          AppShadows.card,
                    ),
                    child: Column(
                      crossAxisAlignment:
                          CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment:
                              MainAxisAlignment
                                  .spaceBetween,
                          children: [
                            const Text(
                              "This Month Overview",
                              style: TextStyle(
                                fontWeight:
                                    FontWeight.bold,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.calendar_today,
                                color:
                                    AppColors.primary,
                              ),
                              onPressed:
                                  _pickMonth,
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Row(
                          children: [
                            Expanded(
                              child: _statBox(
                                "Full Day",
                                full,
                                AppColors.success,
                                AppColors
                                    .successLight,
                              ),
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: _statBox(
                                "Work-Pending",
                                workPending,
                                AppColors.warning,
                                AppColors
                                    .warningLight,
                              ),
                            ),

                            const SizedBox(width: 8),

                            Expanded(
                              child: _statBox(
                                "Absent",
                                absent,
                                AppColors.danger,
                                AppColors
                                    .dangerLight,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // -----------------------------------------------------------
                  // MIS-PUNCH NOTICE
                  // -----------------------------------------------------------

                  if (misPunchPending > 0) ...[
                    const SizedBox(height: 8),

                    Container(
                      padding:
                          const EdgeInsets.all(12),
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors.warning
                                .withValues(alpha: .08),
                        borderRadius:
                            BorderRadius.circular(
                                12),
                        border: Border.all(
                          color:
                              AppColors.warning
                                  .withValues(alpha: .25),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color:
                                AppColors.warning,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '$misPunchPending MIS-PUNCH${misPunchPending == 1 ? '' : 'es'} awaiting admin correction',
                              style:
                                  const TextStyle(
                                color:
                                    AppColors.warning,
                                fontSize: 11,
                                fontWeight:
                                    FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 14),

                  // -----------------------------------------------------------
                  // COMPENSATION
                  // -----------------------------------------------------------

                  _buildCompensationSummary(
                    entries,
                  ),

                  const SizedBox(height: 16),

                  // -----------------------------------------------------------
                  // MONTH SELECTOR
                  // -----------------------------------------------------------

                  const Text(
                    "Month",
                    style: TextStyle(
                      color:
                          AppColors.textSecondary,
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 6),

                  InkWell(
                    onTap: _pickMonth,
                    child: Container(
                      padding:
                          const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration:
                          BoxDecoration(
                        color: AppColors.surface,
                        borderRadius:
                            BorderRadius.circular(
                                12),
                        border: Border.all(
                          color:
                              AppColors.divider,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.calendar_today,
                            size: 16,
                            color:
                                AppColors.primary,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            DateFormat(
                              "MMMM yyyy",
                            ).format(
                              selectedMonth,
                            ),
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons
                                .keyboard_arrow_down,
                            color:
                                AppColors
                                    .textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // -----------------------------------------------------------
                  // DOWNLOAD
                  // -----------------------------------------------------------

                  SizedBox(
                    height: 48,
                    width: double.infinity,
                    child:
                        ElevatedButton.icon(
                      onPressed:
                          _downloadHistory,
                      style:
                          ElevatedButton.styleFrom(
                        backgroundColor:
                            AppColors.primary,
                        foregroundColor:
                            Colors.white,
                        elevation: 0,
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                                  14),
                        ),
                      ),
                      icon: const Icon(
                        Icons.download_rounded,
                      ),
                      label: const Text(
                        "Download History",
                        style: TextStyle(
                          fontWeight:
                              FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // -----------------------------------------------------------
                  // NO RECORDS
                  // -----------------------------------------------------------

                  if (entries.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(
                        vertical: 30,
                      ),
                      child: Center(
                        child: Text(
                          "No records this month",
                          style: TextStyle(
                            color: AppColors
                                .textSecondary,
                          ),
                        ),
                      ),
                    )
                  else

                    // ---------------------------------------------------------
                    // DAILY HISTORY
                    // ---------------------------------------------------------

                    ...entries.map((e) {
                      final dayType =
                          _classify(
                        e.key,
                        e.value,
                      );

                      final date =
                          DateTime.parse(
                        e.key,
                      );

                      final status =
                          e.value?['status']
                              ?.toString()
                              .toUpperCase();

                      final isMisPunch =
                          status ==
                                  'MIS-PUNCH' ||
                              status ==
                                  'AUTO CHECKOUT PENDING' ||
                              e.value?[
                                      'autoPunchOut'] ==
                                  true;

                      return InkWell(
                        onTap: widget.viewerIsAdmin
                            ? () async {
                                final changed =
                                    await Navigator.push<
                                        bool>(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        AdminAttendanceEditorScreen(
                                      adminId:
                                          widget.viewerAdminId ??
                                              '',
                                      adminName:
                                          widget.viewerAdminName ??
                                              'Admin',
                                      employeeId:
                                          widget.employeeId,
                                      employeeName:
                                          widget.employeeName ??
                                              widget.employeeId,
                                      initialDate:
                                          date,
                                    ),
                                  ),
                                );

                                if (changed ==
                                        true &&
                                    mounted) {
                                  await _load();
                                }
                              }
                            : (isMisPunch
                                ? () =>
                                    _sendPunchoutRequest(
                                      e.key,
                                      e.value!,
                                    )
                                : (dayType == DayType.workPending
                                    ? () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) =>
                                                CompensationRequestScreen(
                                              employeeId: widget.employeeId,
                                              employeeName: widget.employeeName,
                                              initialDate: e.key,
                                            ),
                                          ),
                                        )
                                    : null)),

                        borderRadius:
                            BorderRadius.circular(
                                14),

                        child: Container(
                          margin:
                              const EdgeInsets.only(
                            bottom: 10,
                          ),
                          padding:
                              const EdgeInsets.all(
                            14,
                          ),
                          decoration:
                              BoxDecoration(
                            color: isMisPunch
                                ? AppColors.warning
                                    .withValues(alpha: .08)
                                : AppColors.surface,
                            borderRadius:
                                BorderRadius.circular(
                                    14),
                            boxShadow:
                                AppShadows.card,
                          ),
                          child: Row(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              // ------------------------------------------------
                              // DATE
                              // ------------------------------------------------

                              SizedBox(
                                width: 54,
                                child: Column(
                                  children: [
                                    Text(
                                      DateFormat(
                                        "EEE",
                                      ).format(
                                        date,
                                      ),
                                      style:
                                          const TextStyle(
                                        color: AppColors
                                            .textSecondary,
                                        fontSize: 11,
                                      ),
                                    ),

                                    Text(
                                      "${date.day}",
                                      style:
                                          const TextStyle(
                                        color: AppColors
                                            .primary,
                                        fontWeight:
                                            FontWeight.bold,
                                        fontSize: 20,
                                      ),
                                    ),

                                    Text(
                                      DateFormat(
                                        "MMM yyyy",
                                      ).format(
                                        date,
                                      ),
                                      style:
                                          const TextStyle(
                                        color: AppColors
                                            .textSecondary,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(
                                width: 14,
                              ),

                              // ------------------------------------------------
                              // DETAILS
                              // ------------------------------------------------

                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment
                                          .start,
                                  children: [
                                    _rowLine(
                                      Icons.schedule,
                                      "Sessions",
                                      _sessionSummary(
                                        e.value,
                                      ),
                                    ),

                                    _rowLine(
                                      Icons.location_on_outlined,
                                      "Punch locations",
                                      _sessionLocationSummary(
                                        e.value,
                                      ),
                                    ),

                                    _rowLine(
                                      Icons
                                          .timer_outlined,
                                      "Working hours",
                                      workingHours(
                                        e.value,
                                      ),
                                    ),

                                    _rowLine(
                                      Icons
                                          .assignment_turned_in,
                                      "Status",
                                      _statusText(
                                        e.value,
                                      ),
                                    ),

                                    if (isMisPunch)
                                      const Padding(
                                        padding:
                                            EdgeInsets
                                                .only(
                                          top: 5,
                                        ),
                                        child: Text(
                                          'Tap to send / review punch-out correction',
                                          style:
                                              TextStyle(
                                            color: AppColors
                                                .warning,
                                            fontSize: 10,
                                            fontWeight:
                                                FontWeight
                                                    .w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),

                              const SizedBox(
                                width: 8,
                              ),

                              // ------------------------------------------------
                              // DAY TYPE
                              // ------------------------------------------------

                              Container(
                                padding:
                                    const EdgeInsets
                                        .symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color:
                                      _dayTypeColor(
                                    isMisPunch
                                        ? null
                                        : dayType,
                                  ).withValues(
                                      alpha: 0.12),
                                  borderRadius:
                                      BorderRadius
                                          .circular(
                                    20,
                                  ),
                                ),
                                child: Text(
                                  isMisPunch
                                      ? 'MIS-PUNCH'
                                      : _dayTypeText(
                                          dayType,
                                        ),
                                  style:
                                      TextStyle(
                                    color:
                                        _dayTypeColor(
                                      isMisPunch
                                          ? null
                                          : dayType,
                                    ),
                                    fontWeight:
                                        FontWeight
                                            .bold,
                                    fontSize: 11,
                                  ),
                                ),
                              ),

                              // ------------------------------------------------
                              // ADMIN EDIT ICON
                              // ------------------------------------------------

                              if (widget
                                  .viewerIsAdmin) ...[
                                const SizedBox(
                                  width: 6,
                                ),
                                const Icon(
                                  Icons
                                      .edit_outlined,
                                  size: 17,
                                  color: AppColors
                                      .primary,
                                ),
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

  // ---------------------------------------------------------------------------
  // STAT BOX
  // ---------------------------------------------------------------------------

  Widget _statBox(
    String label,
    int value,
    Color color,
    Color bg,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        vertical: 12,
      ),
      decoration:
          BoxDecoration(
        color: bg,
        borderRadius:
            BorderRadius.circular(12),
        border: Border(
          top: BorderSide(
            color: color,
            width: 3,
          ),
        ),
      ),
      child: Column(
        children: [
          Text(
            label,
            style:
                const TextStyle(
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 4),

          Text(
            "$value",
            style: TextStyle(
              fontSize: 18,
              fontWeight:
                  FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // COMPENSATION ACTIVITY
  // ---------------------------------------------------------------------------

  List<Map<String, String>> _buildActivity(
    List<MapEntry<String, Map<String, dynamic>?>>
        entries,
  ) {
    final activity =
        <Map<String, String>>[];

    for (final entry in entries) {
      final record = entry.value;

      if (record == null) {
        continue;
      }

      final status =
          record['status']
              ?.toString()
              .toUpperCase();

      // MIS-PUNCH is not included in compensation
      // until admin supplies the actual punch-out.
      if (status == 'MIS-PUNCH' ||
          status == 'AUTO CHECKOUT PENDING' ||
          record['autoPunchOut'] == true) {
        activity.add({
          'date': entry.key,
          'text':
              'MIS-PUNCH: awaiting admin correction',
        });

        continue;
      }

      if (status ==
          'AUTO CHECKOUT REJECTED') {
        activity.add({
          'date': entry.key,
          'text':
              'Punch-out correction rejected by admin',
        });

        continue;
      }

      final calculation =
          _calculateSessions(record);

      if (calculation == null) {
        continue;
      }

      if (calculation.dayType ==
          DayType.workPending) {
        activity.add({
          'date': entry.key,
          'text':
              'Work-Pending: ${AttendanceCalculator.formatHours(calculation.shortfallHours)} outstanding',
        });
      }

      if (calculation.extraHours > 0) {
        activity.add({
          'date': entry.key,
          'text':
              'Extra work: ${AttendanceCalculator.formatHours(calculation.extraHours)} available for compensation',
        });
      }
    }

    return activity;
  }

  // ---------------------------------------------------------------------------
  // COMPENSATION SUMMARY
  // ---------------------------------------------------------------------------

  Widget _buildCompensationSummary(
    List<MapEntry<String, Map<String, dynamic>?>>
        entries,
  ) {
    final monthOutstanding =
        _calculateOutstandingMinutes(
      entries,
    );

    final allTimeOutstanding =
        _calculateAllTimeOutstandingMinutes();

    return Container(
      padding:
          const EdgeInsets.all(16),
      decoration:
          BoxDecoration(
        color: AppColors.surface,
        borderRadius:
            BorderRadius.circular(16),
        boxShadow:
            AppShadows.card,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          const Text(
            'Compensation',
            style:
                TextStyle(
              fontWeight:
                  FontWeight.bold,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'Total outstanding time: '
            '${AttendanceCalculator.formatHours(allTimeOutstanding / 60)}',
            style: TextStyle(
              color: allTimeOutstanding > 0
                  ? AppColors.danger
                  : AppColors.success,
              fontWeight:
                  FontWeight.w700,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 6),

          Text(
            'This month: '
            '${AttendanceCalculator.formatHours(monthOutstanding / 60)}',
            style: TextStyle(
              color: monthOutstanding > 0
                  ? AppColors.danger
                  : AppColors.success,
              fontWeight:
                  FontWeight.w700,
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 3),

          const Text(
            'The total runs across every month of attendance; '
            'this month figure only covers the selected month.',
            style: TextStyle(
              color:
                  AppColors.textSecondary,
              fontSize: 11,
            ),
          ),

          const SizedBox(height: 12),

          SizedBox(
            width: double.infinity,
            height: 42,
            child:
                OutlinedButton.icon(
              onPressed: () =>
                  Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) =>
                      CompensationActivityScreen(
                    monthLabel:
                        DateFormat(
                      "MMMM yyyy",
                    ).format(
                      selectedMonth,
                    ),
                    monthOutstandingMinutes:
                        monthOutstanding,
                    allTimeOutstandingMinutes:
                        allTimeOutstanding,
                    activity:
                        _buildActivity(
                      entries,
                    ),
                  ),
                ),
              ),
              style:
                  OutlinedButton.styleFrom(
                foregroundColor:
                    AppColors.primary,
                side:
                    const BorderSide(
                  color:
                      AppColors.primary,
                ),
                shape:
                    RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(
                          20),
                ),
              ),
              icon: const Icon(
                Icons.list_alt,
                size: 18,
              ),
              label: const Text(
                "View Activity",
                style: TextStyle(
                  fontWeight:
                      FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MONTHLY OUTSTANDING
  // ---------------------------------------------------------------------------

  /// Calculates outstanding time for the selected month.
  ///
  /// Rules:
  ///
  /// 1. MIS-PUNCH is ignored until admin correction.
  /// 2. Work-Pending deficits are collected.
  /// 3. Extra work is pooled as compensation.
  /// 4. Compensation is applied to the smallest deficit first.
  /// 5. Fully compensated deficits become effectively Full Day.
  /// 6. Partially compensated deficits remain Work-Pending.
  int _calculateOutstandingMinutes(
    List<MapEntry<String, Map<String, dynamic>?>>
        entries,
  ) {
    final pending = <int>[];

    var compensationMinutes = 0;

    for (final entry in entries) {
      final record = entry.value;

      if (record == null) {
        continue;
      }

      final status =
          record['status']
              ?.toString()
              .toUpperCase();

      // NEVER calculate from temporary MIS-PUNCH.
      if (status == 'MIS-PUNCH' ||
          status == 'AUTO CHECKOUT PENDING' ||
          record['autoPunchOut'] == true) {
        continue;
      }

      final result =
          _calculateSessions(record);

      if (result == null) {
        continue;
      }

      final deficit =
          (result.shortfallHours * 60).round();

      final extra =
          (result.extraHours * 60).round();

      if (deficit > 0) {
        pending.add(deficit);
      }

      if (extra > 0) {
        compensationMinutes += extra;
      }
    }

    // Least Work-Pending hour first.
    pending.sort();

    var outstanding = 0;

    for (final deficit in pending) {
      final applied =
          compensationMinutes >= deficit
              ? deficit
              : compensationMinutes;

      compensationMinutes -= applied;

      outstanding +=
          deficit - applied;
    }

    return outstanding;
  }

  // ---------------------------------------------------------------------------
  // ALL-TIME OUTSTANDING
  // ---------------------------------------------------------------------------

  int _calculateAllTimeOutstandingMinutes() {
    final entries = attendanceData.entries
        .map(
          (e) => MapEntry(
            e.key.toString(),
            e.value is Map
                ? Map<String, dynamic>.from(
                    e.value as Map,
                  )
                : null,
          ),
        )
        .toList();

    return _calculateOutstandingMinutes(
      entries,
    );
  }

  // ---------------------------------------------------------------------------
  // ROW
  // ---------------------------------------------------------------------------

  Widget _rowLine(
    IconData icon,
    String label,
    String value,
  ) {
    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 2,
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 14,
            color: AppColors.primary,
          ),

          const SizedBox(width: 6),

          Text(
            "$label:",
            style:
                const TextStyle(
              color:
                  AppColors.textSecondary,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 6),

          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(
                fontWeight:
                    FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}