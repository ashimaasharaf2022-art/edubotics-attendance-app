import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

import '../utils/attendance_calculator.dart';
import '../utils/export_helper.dart';
import '../utils/app_colors.dart';

enum ReportPeriod { daily, weekly, monthly }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late DatabaseReference dbRef;

  bool loading = true;

  // employeeId -> employee name
  Map<String, String> employees = {};

  // employeeId -> { dateKey: {punchIn, punchOut, status} }
  Map<String, Map<String, dynamic>> attendance = {};

  ReportPeriod period = ReportPeriod.daily;
  DateTime referenceDate = DateTime.now();

  bool showPerEmployeeChart = false;
  String? selectedEmployeeIdForChart;

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => loading = true);

    try {
      final usersSnap = await dbRef.child("users").get();
      final attendanceSnap = await dbRef.child("Attendance").get();

      final Map<String, String> loadedEmployees = {};

      if (usersSnap.exists) {
        final usersMap =
            Map<dynamic, dynamic>.from(usersSnap.value as Map);

        usersMap.forEach((id, data) {
          final userData =
              Map<dynamic, dynamic>.from(data as Map);

          // Super Admin is not an employee — exclude from reports.
          if (userData["role"]?.toString().toLowerCase() == "superadmin") {
            return;
          }

          loadedEmployees[id.toString()] =
              (userData["name"] ?? id).toString();
        });
      }

      final Map<String, Map<String, dynamic>> loadedAttendance = {};

      if (attendanceSnap.exists) {
        final empMap =
            Map<dynamic, dynamic>.from(attendanceSnap.value as Map);

        empMap.forEach((empId, dateMap) {
          final dates =
              Map<dynamic, dynamic>.from(dateMap as Map);

          final Map<String, dynamic> dateRecords = {};

          dates.forEach((date, record) {
            dateRecords[date.toString()] =
                Map<String, dynamic>.from(record as Map);
          });

          loadedAttendance[empId.toString()] = dateRecords;
        });
      }

      if (!mounted) return;

      setState(() {
        employees = loadedEmployees;
        attendance = loadedAttendance;
        loading = false;

        if (showPerEmployeeChart &&
            selectedEmployeeIdForChart == null &&
            employees.isNotEmpty) {
          selectedEmployeeIdForChart = employees.keys.first;
        }
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => loading = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Failed to load reports: $e"),
        ),
      );
    }
  }

  String _dateKey(DateTime d) {
    return "${d.year}-"
        "${d.month.toString().padLeft(2, '0')}-"
        "${d.day.toString().padLeft(2, '0')}";
  }

  bool _isWeekend(DateTime date) {
    return date.weekday == DateTime.saturday ||
        date.weekday == DateTime.sunday;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }

  List<DateTime> _datesInRange() {
    final today = DateTime.now();

    final todayOnly = DateTime(
      today.year,
      today.month,
      today.day,
    );

    DateTime start;
    DateTime end;

    switch (period) {
      case ReportPeriod.daily:
        start = DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day,
        );
        end = start;
        break;

      case ReportPeriod.weekly:
        final weekday = referenceDate.weekday;

        start = DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day,
        ).subtract(
          Duration(days: weekday - 1),
        );

        end = start.add(
          const Duration(days: 6),
        );
        break;

      case ReportPeriod.monthly:
        start = DateTime(
          referenceDate.year,
          referenceDate.month,
          1,
        );

        end = DateTime(
          referenceDate.year,
          referenceDate.month + 1,
          0,
        );
        break;
    }

    if (end.isAfter(todayOnly)) {
      end = todayOnly;
    }

    final List<DateTime> dates = [];

    for (
      DateTime d = start;
      !d.isAfter(end);
      d = d.add(const Duration(days: 1))
    ) {
      dates.add(d);
    }

    return dates
        .where((date) => !_isWeekend(date))
        .toList();
  }

  String _periodLabel() {
    switch (period) {
      case ReportPeriod.daily:
        return DateFormat(
          "EEE, dd MMM yyyy",
        ).format(referenceDate);

      case ReportPeriod.weekly:
        final dates = _datesInRange();

        if (dates.isEmpty) {
          return "";
        }

        final start = DateTime(
          referenceDate.year,
          referenceDate.month,
          referenceDate.day,
        ).subtract(
          Duration(days: referenceDate.weekday - 1),
        );

        final end = start.add(
          const Duration(days: 6),
        );

        return "${DateFormat("dd MMM").format(start)} - "
            "${DateFormat("dd MMM yyyy").format(end)}";

      case ReportPeriod.monthly:
        return DateFormat(
          "MMMM yyyy",
        ).format(referenceDate);
    }
  }

  void _shiftPeriod(int direction) {
    setState(() {
      switch (period) {
        case ReportPeriod.daily:
          referenceDate =
              referenceDate.add(Duration(days: direction));
          break;

        case ReportPeriod.weekly:
          referenceDate =
              referenceDate.add(Duration(days: 7 * direction));
          break;

        case ReportPeriod.monthly:
          referenceDate = DateTime(
            referenceDate.year,
            referenceDate.month + direction,
            1,
          );
          break;
      }
    });
  }

  /// Converts the database attendance record into attendance sessions.
  ///
  /// The app supports both:
  ///   sessions: List
  /// and:
  ///   sessions: Map
  ///
  /// Older records using top-level punchIn/punchOut are also supported.
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
          (a, b) => a.key
              .toString()
              .compareTo(b.key.toString()),
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

    // Backward compatibility for older records.
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

  AttendanceResult? _calculateSessions(
    Map<String, dynamic>? record,
  ) {
    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) {
      return null;
    }

    return AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    );
  }

  /// Returns the final attendance classification for a day.
  ///
  /// The three classifications are:
  ///   FULL DAY
  ///   WORK-PENDING
  ///   ABSENT
  ///
  /// A day that is currently punched in but not punched out is kept
  /// separately as "in progress" and is not classified as ABSENT today.
  ///
  /// MIS-PUNCH is only a temporary workflow status and is NOT a DayType.
  DayType? _classifyDay(
    Map<String, dynamic>? record,
    DateTime date,
  ) {
    // Saturday and Sunday are weekly off days and are never classified.
    if (_isWeekend(date)) return null;

    final isToday = _isSameDay(
      date,
      DateTime.now(),
    );

    final sessions = _sessionsFromRecord(record);

    if (sessions.isEmpty) {
      return DayType.absent;
    }

    final last = sessions.last;

    // Still working / currently open session.
    if (last.punchOut == null) {
      return isToday ? null : DayType.absent;
    }

    final result = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record?['workFromHome'] == true,
    );

    return result.dayType;
  }

  double _netHoursFor(
    Map<String, dynamic>? record,
  ) {
    return _calculateSessions(record)?.netHours ?? 0;
  }

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

  /// Builds the attendance percentage trend.
  ///
  /// FULL DAY = 100%
  /// WORK-PENDING = percentage of required 9 hours actually worked
  /// ABSENT = 0%
  ///
  /// An in-progress day is excluded from the completed attendance
  /// calculation and contributes 0 for that day until it is completed.
  List<FlSpot> _buildTrendSpots({
    String? employeeId,
  }) {
    final monthStart = DateTime(
      referenceDate.year,
      referenceDate.month,
      1,
    );

    final monthEnd = DateTime(
      referenceDate.year,
      referenceDate.month + 1,
      0,
    );

    final today = DateTime.now();

    final todayOnly = DateTime(
      today.year,
      today.month,
      today.day,
    );

    final lastDay =
        monthEnd.isAfter(todayOnly) ? todayOnly : monthEnd;

    final List<FlSpot> spots = [];

    for (
      DateTime d = monthStart;
      !d.isAfter(lastDay);
      d = d.add(const Duration(days: 1))
    ) {
      if (_isWeekend(d)) {
        continue;
      }

      final key = _dateKey(d);

      double dayValue;

      if (employeeId != null) {
        final record = attendance[employeeId]?[key];

        final dayType = _classifyDay(
          record,
          d,
        );

        if (dayType == DayType.fullDay) {
          dayValue = 100;
        } else if (dayType == DayType.workPending) {
          final hours = _netHoursFor(record);

          dayValue =
              ((hours / 9.0) * 100).clamp(0, 100);
        } else {
          dayValue = 0;
        }
      } else {
        if (employees.isEmpty) {
          dayValue = 0;
        } else {
          double total = 0;

          employees.forEach((empId, _) {
            final record = attendance[empId]?[key];

            final dayType = _classifyDay(
              record,
              d,
            );

            if (dayType == DayType.fullDay) {
              total += 100;
            } else if (dayType == DayType.workPending) {
              final hours = _netHoursFor(record);

              total +=
                  ((hours / 9.0) * 100).clamp(0, 100);
            } else {
              total += 0;
            }
          });

          dayValue = total / employees.length;
        }
      }

      spots.add(
        FlSpot(
          d.day.toDouble(),
          dayValue,
        ),
      );
    }

    return spots;
  }

  /// Computes per-employee statistics for the selected period.
  ///
  /// Only the three attendance classifications are counted:
  /// FULL DAY
  /// WORK-PENDING
  /// ABSENT
  ///
  /// An open session is tracked separately as inProgressDays.
  List<_EmployeeReport> _buildReports() {
    final dates = _datesInRange();

    final List<_EmployeeReport> reports = [];

    employees.forEach((empId, name) {
      int fullDays = 0;
      int workPendingDays = 0;
      int absentDays = 0;
      int inProgressDays = 0;

      double totalHours = 0;

      String? lastPunchIn;
      String? lastPunchOut;
      String? lastStatus;

      DayType? lastDayType;

      final empRecords = attendance[empId] ?? {};

      for (final date in dates) {
        final key = _dateKey(date);

        final record = empRecords[key];

        final dayType = _classifyDay(
          record,
          date,
        );

        if (dayType == null) {
          inProgressDays++;
        } else {
          switch (dayType) {
            case DayType.fullDay:
              fullDays++;
              totalHours += _netHoursFor(record);
              break;

            case DayType.workPending:
              workPendingDays++;
              totalHours += _netHoursFor(record);
              break;

            case DayType.absent:
              absentDays++;
              break;
          }
        }

        if (dates.isNotEmpty && date == dates.last) {
          lastPunchIn = record?["punchIn"]?.toString();
          lastPunchOut = record?["punchOut"]?.toString();
          lastStatus = record?["status"]?.toString();
          lastDayType = dayType;
        }
      }

      reports.add(
        _EmployeeReport(
          employeeId: empId,
          name: name,
          fullDays: fullDays,
          workPendingDays: workPendingDays,
          absentDays: absentDays,
          inProgressDays: inProgressDays,
          totalHours: totalHours,
          lastPunchIn: lastPunchIn,
          lastPunchOut: lastPunchOut,
          lastStatus: lastStatus,
          lastDayType: lastDayType,
        ),
      );
    });

    reports.sort(
      (a, b) => a.name.compareTo(b.name),
    );

    return reports;
  }

  List<ExportRow> _toExportRows(
    List<_EmployeeReport> reports,
  ) {
    return reports
        .map(
          (r) => ExportRow(
            employeeId: r.employeeId,
            name: r.name,
            fullDays: r.fullDays,
            workPendingDays: r.workPendingDays,
            absentDays: r.absentDays,
            totalHours: r.totalHours,
            lastStatus: r.lastStatus,
            lastPunchIn: r.lastPunchIn,
            lastPunchOut: r.lastPunchOut,
          ),
        )
        .toList();
  }

  void _showExportOptions(
    List<_EmployeeReport> reports,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(
                Icons.picture_as_pdf,
                color: Colors.red,
              ),
              title: const Text(
                "Export as PDF",
              ),
              onTap: () {
                Navigator.pop(context);
                _exportPdf(reports);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.grid_on,
                color: Colors.green,
              ),
              title: const Text(
                "Export as Excel",
              ),
              onTap: () {
                Navigator.pop(context);
                _exportExcel(reports);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportPdf(
    List<_EmployeeReport> reports,
  ) async {
    try {
      await ExportHelper.exportPdf(
        title: "Attendance Report",
        periodLabel: _periodLabel(),
        rows: _toExportRows(reports),
        isDaily: period == ReportPeriod.daily,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "PDF export failed: $e",
          ),
        ),
      );
    }
  }

  Future<void> _exportExcel(
    List<_EmployeeReport> reports,
  ) async {
    try {
      await ExportHelper.exportExcel(
        title: "Attendance Report",
        periodLabel: _periodLabel(),
        rows: _toExportRows(reports),
        isDaily: period == ReportPeriod.daily,
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            "Excel export failed: $e",
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reports =
        loading ? <_EmployeeReport>[] : _buildReports();

    final totalFull = reports.fold<int>(
      0,
      (sum, r) => sum + r.fullDays,
    );

    final totalWorkPending = reports.fold<int>(
      0,
      (sum, r) => sum + r.workPendingDays,
    );

    final totalAbsent = reports.fold<int>(
      0,
      (sum, r) => sum + r.absentDays,
    );

    final totalHours = reports.fold<double>(
      0,
      (sum, r) => sum + r.totalHours,
    );

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "Reports",
          style: TextStyle(
            color: Colors.white,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.download,
              color: Colors.white,
            ),
            tooltip: "Export",
            onPressed: loading
                ? null
                : () => _showExportOptions(reports),
          ),
          IconButton(
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
            onPressed: loading ? null : _loadData,
          ),
        ],
      ),
      body: loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildPeriodSelector(),

                  const SizedBox(height: 12),

                  _buildDateNavigator(),

                  const SizedBox(height: 16),

                  _buildSummaryCards(
                    totalFull,
                    totalWorkPending,
                    totalAbsent,
                    totalHours,
                  ),

                  const SizedBox(height: 16),

                  _buildTrendChart(),

                  const SizedBox(height: 20),

                  const Text(
                    "Employee Breakdown",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (reports.isEmpty)
                    const Padding(
                      padding:
                          EdgeInsets.symmetric(vertical: 30),
                      child: Center(
                        child: Text(
                          "No employees found",
                        ),
                      ),
                    )
                  else
                    ...reports.map(_buildEmployeeCard),
                ],
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return SegmentedButton<ReportPeriod>(
      segments: const [
        ButtonSegment(
          value: ReportPeriod.daily,
          label: Text("Daily"),
        ),
        ButtonSegment(
          value: ReportPeriod.weekly,
          label: Text("Weekly"),
        ),
        ButtonSegment(
          value: ReportPeriod.monthly,
          label: Text("Monthly"),
        ),
      ],
      selected: {period},
      onSelectionChanged: (selection) {
        setState(() {
          period = selection.first;
        });
      },
      style: SegmentedButton.styleFrom(
        selectedBackgroundColor: AppColors.primary,
        selectedForegroundColor: Colors.white,
      ),
    );
  }

  Widget _buildDateNavigator() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment:
            MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: const Icon(
              Icons.chevron_left,
            ),
            onPressed: () => _shiftPeriod(-1),
          ),
          Text(
            _periodLabel(),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.chevron_right,
            ),
            onPressed: () => _shiftPeriod(1),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCards(
    int full,
    int workPending,
    int absent,
    double hours,
  ) {
    return Row(
      children: [
        Expanded(
          child: _summaryCard(
            "Full Day",
            full.toString(),
            Colors.green,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _summaryCard(
            "Work-Pending",
            workPending.toString(),
            Colors.orange,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _summaryCard(
            "Absent",
            absent.toString(),
            Colors.red,
          ),
        ),

        const SizedBox(width: 8),

        Expanded(
          child: _summaryCard(
            "Hours",
            AttendanceCalculator.formatHours(hours),
            Colors.blue,
          ),
        ),
      ],
    );
  }

  Widget _summaryCard(
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 6,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              color: Colors.grey,
              fontSize: 11,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTrendChart() {
    final spots = _buildTrendSpots(
      employeeId:
          showPerEmployeeChart
              ? selectedEmployeeIdForChart
              : null,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment:
                MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Attendance Trend",
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              Row(
                children: [
                  const Text(
                    "Per Employee",
                    style: TextStyle(
                      fontSize: 12,
                    ),
                  ),
                  Switch(
                    value: showPerEmployeeChart,
                    activeThumbColor: AppColors.primary,
                    onChanged: (value) {
                      setState(() {
                        showPerEmployeeChart = value;

                        if (value &&
                            selectedEmployeeIdForChart ==
                                null &&
                            employees.isNotEmpty) {
                          selectedEmployeeIdForChart =
                              employees.keys.first;
                        }
                      });
                    },
                  ),
                ],
              ),
            ],
          ),

          if (showPerEmployeeChart) ...[
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              initialValue: selectedEmployeeIdForChart,
              isExpanded: true,
              decoration: InputDecoration(
                contentPadding:
                    const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(10),
                ),
              ),
              items: employees.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(
                        "${e.value} (${e.key})",
                        overflow:
                            TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  selectedEmployeeIdForChart = value;
                });
              },
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            height: 220,
            child: spots.isEmpty
                ? const Center(
                    child: Text(
                      "No data for this month yet",
                    ),
                  )
                : LineChart(
                    LineChartData(
                      minY: 0,
                      maxY: 100,

                      gridData: FlGridData(
                        show: true,
                        drawVerticalLine: false,
                        horizontalInterval: 25,
                      ),

                      titlesData: FlTitlesData(
                        topTitles:
                            const AxisTitles(
                          sideTitles:
                              SideTitles(
                            showTitles: false,
                          ),
                        ),
                        rightTitles:
                            const AxisTitles(
                          sideTitles:
                              SideTitles(
                            showTitles: false,
                          ),
                        ),
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval: 25,
                            reservedSize: 36,
                            getTitlesWidget:
                                (value, meta) =>
                                    Text(
                              "${value.toInt()}%",
                              style:
                                  const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                        bottomTitles:
                            AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            interval:
                                spots.length > 15
                                    ? 5
                                    : 2,
                            reservedSize: 24,
                            getTitlesWidget:
                                (value, meta) =>
                                    Text(
                              value.toInt()
                                  .toString(),
                              style:
                                  const TextStyle(
                                fontSize: 10,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                        ),
                      ),

                      borderData:
                          FlBorderData(
                        show: false,
                      ),

                      lineBarsData: [
                        LineChartBarData(
                          spots: spots,
                          isCurved: true,
                          color: AppColors.primary,
                          barWidth: 3,
                          dotData: FlDotData(
                            show: spots.length <= 31,
                          ),
                          belowBarData:
                              BarAreaData(
                            show: true,
                            color: AppColors.primary
                                .withValues(alpha: 0.12),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Color _dayTypeColor(
    DayType? type,
  ) {
    switch (type) {
      case DayType.fullDay:
        return Colors.green;

      case DayType.workPending:
        return Colors.orange;

      case DayType.absent:
        return Colors.red;

      case null:
        return Colors.blue;
    }
  }

  String _dayTypeText(
    DayType? type,
  ) {
    switch (type) {
      case DayType.fullDay:
        return "FULL DAY";

      case DayType.workPending:
        return "WORK-PENDING";

      case DayType.absent:
        return "ABSENT";

      case null:
        return "IN PROGRESS";
    }
  }

  Widget _buildEmployeeCard(
    _EmployeeReport r,
  ) {
    return Card(
      margin: const EdgeInsets.only(
        bottom: 10,
      ),
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(
                  child: Icon(Icons.person),
                ),

                const SizedBox(width: 10),

                Expanded(
                  child: Column(
                    crossAxisAlignment:
                        CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        r.employeeId,
                        style: const TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),

                if (period == ReportPeriod.daily &&
                    r.lastDayType != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: _dayTypeColor(
                        r.lastDayType,
                      ).withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: Text(
                      _dayTypeText(
                        r.lastDayType,
                      ),
                      style: TextStyle(
                        color: _dayTypeColor(
                          r.lastDayType,
                        ),
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  )
                else if (
                    r.inProgressDays > 0 &&
                    period == ReportPeriod.daily
                  )
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue
                          .withValues(alpha: 0.12),
                      borderRadius:
                          BorderRadius.circular(20),
                    ),
                    child: const Text(
                      "IN PROGRESS",
                      style: TextStyle(
                        color: Colors.blue,
                        fontWeight:
                            FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),

            const Divider(height: 20),

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: [
                _miniStat(
                  "Full",
                  "${r.fullDays}",
                  Colors.green,
                ),

                _miniStat(
                  "Pending",
                  "${r.workPendingDays}",
                  Colors.orange,
                ),

                _miniStat(
                  "Absent",
                  "${r.absentDays}",
                  Colors.red,
                ),

                _miniStat(
                  "Hours",
                  AttendanceCalculator
                      .formatHours(
                    r.totalHours,
                  ),
                  Colors.blue,
                ),
              ],
            ),

            if (period == ReportPeriod.daily) ...[
              const SizedBox(height: 10),

              Text(
                "Status : ${r.lastStatus ?? "Not Checked In"}",
              ),

              Text(
                "In : ${r.lastPunchIn ?? "--"}"
                "   "
                "Out : ${r.lastPunchOut ?? "--"}",
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _miniStat(
    String label,
    String value,
    Color color,
  ) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: Colors.grey,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _EmployeeReport {
  final String employeeId;
  final String name;

  final int fullDays;
  final int workPendingDays;
  final int absentDays;

  final int inProgressDays;

  final double totalHours;

  final String? lastPunchIn;
  final String? lastPunchOut;
  final String? lastStatus;

  final DayType? lastDayType;

  _EmployeeReport({
    required this.employeeId,
    required this.name,
    required this.fullDays,
    required this.workPendingDays,
    required this.absentDays,
    required this.inProgressDays,
    required this.totalHours,
    this.lastPunchIn,
    this.lastPunchOut,
    this.lastStatus,
    this.lastDayType,
  });
}