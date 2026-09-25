import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import 'history_screen.dart';
import 'add_employee_screen.dart';
import 'profile_screen.dart';

enum _AttendancePeriod { daily, weekly, monthly }

class AdminAttendanceScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  const AdminAttendanceScreen({super.key, required this.adminId, required this.adminName});

  @override
  State<AdminAttendanceScreen> createState() => _AdminAttendanceScreenState();
}

class _AdminAttendanceScreenState extends State<AdminAttendanceScreen> with SingleTickerProviderStateMixin {
  late final DatabaseReference _db;
  late final TabController _tabs;
  late Future<Map<dynamic, dynamic>> _usersFuture;
  late Future<_AdminAttendanceData> _attendanceFuture;
  _AttendancePeriod _period = _AttendancePeriod.daily;
  DateTime _reference = DateTime.now();

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
    _tabs = TabController(length: 3, vsync: this);
    _usersFuture = _loadUsers();
    _attendanceFuture = _loadAttendanceData();
  }

  @override
  void dispose() { _tabs.dispose(); super.dispose(); }

  String _dateKey(DateTime date) => DateFormat('yyyy-MM-dd').format(date);
  List<String> get _periodKeys {
    final day = DateTime(_reference.year, _reference.month, _reference.day);
    if (_period == _AttendancePeriod.daily) return [_dateKey(day)];
    if (_period == _AttendancePeriod.weekly) return List.generate(7, (i) => _dateKey(day.subtract(Duration(days: i))));
    return List.generate(day.day, (i) => _dateKey(DateTime(day.year, day.month, i + 1)));
  }

  /// Singular/plural text helper, e.g. _pluralize(1, 'full day', 'full days')
  /// => "1 full day", _pluralize(3, 'full day', 'full days') => "3 full days".
  String _pluralize(int count, String singular, String plural) => '$count ${count == 1 ? singular : plural}';

  Map<dynamic, dynamic> _map(dynamic value) => value is Map ? Map<dynamic, dynamic>.from(value) : <dynamic, dynamic>{};
  Future<Map<dynamic, dynamic>> _loadUsers() async => _map((await _db.child('users').get()).value);
  Future<_AdminAttendanceData> _loadAttendanceData() async {
    final results = await Future.wait([_db.child('users').get(), _db.child('Attendance').get(), _db.child('AttendanceSummary').get()]);
    return _AdminAttendanceData(
      users: _map(results[0].value),
      attendance: _map(results[1].value),
      summaries: _map(results[2].value),
    );
  }
  Future<void> _refresh() async {
    setState(() {
      _usersFuture = _loadUsers();
      _attendanceFuture = _loadAttendanceData();
    });
    await _usersFuture;
  }
  bool _isEmployee(Map<dynamic, dynamic> user) => user['role']?.toString().toLowerCase() != 'superadmin';

  /// Returns a normal daily attendance classification.
  ///
  /// MIS-PUNCH is only a temporary workflow status. Until an admin selects
  /// the employee's real punch-out time, we must not use the temporary 11:59
  /// PM closure for working-hours calculation.
  AttendanceResult? _result(Map<dynamic, dynamic> record) {
    final status = record['status']?.toString().toUpperCase();
    if (status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        status == 'AUTO CHECKED OUT') {
      return null;
    }
    if (record['punchIn'] == null || record['punchOut'] == null) return null;
    return AttendanceCalculator.calculate(
      punchIn: record['punchIn'].toString(),
      punchOut: record['punchOut'].toString(),
      workFromHome: record['workFromHome'] == true,
    );
  }

  bool _isMisPunch(Map<dynamic, dynamic> record) {
    final status = record['status']?.toString().toUpperCase();
    return status == 'MIS-PUNCH' ||
        status == 'AUTO CHECKOUT PENDING' ||
        status == 'AUTO CHECKED OUT' ||
        record['autoPunchOut'] == true;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Attendance'),
      actions: [
        IconButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddEmployeeScreen())).then((_) => _refresh()), icon: const Icon(Icons.person_add_alt_1), tooltip: 'Add employee'),
        IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
      ],
      bottom: TabBar(controller: _tabs, isScrollable: false, indicatorColor: Colors.white, labelColor: Colors.white, unselectedLabelColor: Colors.white70, tabs: const [Tab(text: 'Employees'), Tab(text: 'All Attendance'), Tab(text: 'Compensation')]),
    ),
    body: TabBarView(controller: _tabs, children: [_employeeFutureTab(), _allFutureTab(), _compensationFutureTab()]),
  );

  Widget _employeeFutureTab() => FutureBuilder<Map<dynamic, dynamic>>(
    future: _usersFuture,
    builder: (_, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _loadError(snapshot.error);
      return RefreshIndicator(onRefresh: _refresh, child: _employees(snapshot.data ?? {}));
    },
  );
  Widget _allFutureTab() => FutureBuilder<_AdminAttendanceData>(
    future: _attendanceFuture,
    builder: (_, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _loadError(snapshot.error);
      final data = snapshot.data!; return RefreshIndicator(onRefresh: _refresh, child: _allAttendance(data.users, data.attendance));
    },
  );
  Widget _compensationFutureTab() => FutureBuilder<_AdminAttendanceData>(
    future: _attendanceFuture,
    builder: (_, snapshot) {
      if (snapshot.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
      if (snapshot.hasError) return _loadError(snapshot.error);
      final data = snapshot.data!; return RefreshIndicator(onRefresh: _refresh, child: _compensation(data.users, data.attendance, data.summaries));
    },
  );
  Widget _loadError(Object? error) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_off, size: 34), const SizedBox(height: 12), const Text('Could not load data.'), const SizedBox(height: 8), Text('$error', textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)), TextButton(onPressed: _refresh, child: const Text('Try again'))])));

  List<MapEntry<dynamic, dynamic>> _employeeEntries(Map<dynamic, dynamic> users) {
    final entries = users.entries.where((entry) => _isEmployee(_map(entry.value))).toList();
    entries.sort((a, b) => (_map(a.value)['name'] ?? a.key).toString().compareTo((_map(b.value)['name'] ?? b.key).toString()));
    return entries;
  }

  Widget _employees(Map<dynamic, dynamic> users) {
    final entries = _employeeEntries(users);
    if (entries.isEmpty) return const Center(child: Text('No employees found.'));
    return ListView.builder(padding: const EdgeInsets.all(16), itemCount: entries.length, itemBuilder: (_, index) {
      final entry = entries[index];
      final data = _map(entry.value);
      final id = entry.key.toString();
      final name = data['name']?.toString() ?? id;
      final photoBase64 = data['photoBase64']?.toString();
      final subtitleInfo = data['designation'] ?? data['department'] ?? 'Employee';

      ImageProvider? avatarImg;
      if (photoBase64 != null && photoBase64.isNotEmpty) {
        try {
          avatarImg = MemoryImage(base64Decode(photoBase64));
        } catch (_) {}
      }

      return Card(
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            backgroundImage: avatarImg,
            child: avatarImg == null ? const Icon(Icons.person, color: AppColors.primary) : null,
          ),
          title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text("$id • $subtitleInfo", style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          trailing: PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'profile') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProfileScreen(
                      employeeId: id,
                      viewerIsAdmin: true,
                      viewerAdminId: widget.adminId,
                      viewerAdminName: widget.adminName,
                    ),
                  ),
                ).then((_) => _refresh());
              } else if (value == 'view') {
                Navigator.push(context, MaterialPageRoute(builder: (_) => HistoryScreen(
                  employeeId: id,
                  employeeName: name,
                  viewerIsAdmin: true,
                  viewerAdminId: widget.adminId,
                  viewerAdminName: widget.adminName,
                )));
              } else if (value == 'delete') {
                _confirmDeleteEmployee(id, name);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'profile',
                child: Row(children: [Icon(Icons.person_outline, size: 18), SizedBox(width: 8), Text('View profile')]),
              ),
              PopupMenuItem(
                value: 'view',
                child: Row(children: [Icon(Icons.visibility_outlined, size: 18), SizedBox(width: 8), Text('View attendance')]),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete employee', style: TextStyle(color: Colors.red))]),
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                employeeId: id,
                viewerIsAdmin: true,
                viewerAdminId: widget.adminId,
                viewerAdminName: widget.adminName,
              ),
            ),
          ).then((_) => _refresh()),
        ),
      );
    });
  }

  Future<void> _confirmDeleteEmployee(String employeeId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete employee?'),
        content: Text('Remove $name ($employeeId) from the employee list? Their attendance history will remain available for audit.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.child('users').child(employeeId).remove();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$name was removed. Attendance history was kept.')));
    await _refresh();
  }

  Widget _allAttendance(Map<dynamic, dynamic> users, Map<dynamic, dynamic> attendance) {
    final keys = _periodKeys;
    final cards = <Widget>[];

    for (final entry in _employeeEntries(users)) {
      final id = entry.key.toString();
      final user = _map(entry.value);
      final records = _map(attendance[id]);

      var full = 0;
      var workPending = 0;
      var absent = 0;
      var misPunchPending = 0;
      var worked = 0;

      for (final key in keys) {
        final record = _map(records[key]);

        // MIS-PUNCH is a temporary workflow state, not a DayType. It is
        // deliberately kept separate so the temporary 11:59 PM closure is
        // never included in working-hours calculations.
        if (_isMisPunch(record)) {
          misPunchPending++;
          continue;
        }

        final result = _result(record);
        if (result == null) continue;

        worked += (result.netHours * 60).round();
        switch (result.dayType) {
          case DayType.fullDay:
            full++;
            break;
          case DayType.workPending:
            workPending++;
            break;
          case DayType.absent:
            absent++;
            break;
        }
      }

      final subtitle = '${_pluralize(full, 'full day', 'full days')} • '
          '${_pluralize(workPending, 'work-pending day', 'work-pending days')} • '
          '${_pluralize(absent, 'absent day', 'absent days')}'
          '${misPunchPending > 0 ? ' • ${_pluralize(misPunchPending, 'MIS-PUNCH pending', 'MIS-PUNCHes pending')}' : ''} • '
          '${AttendanceCalculator.formatHours(worked / 60)} worked';

      cards.add(
        Card(
          child: ListTile(
            title: Text(user['name']?.toString() ?? id),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => HistoryScreen(
                  employeeId: id,
                  employeeName: user['name']?.toString() ?? id,
                  viewerIsAdmin: true,
                  viewerAdminId: widget.adminId,
                  viewerAdminName: widget.adminName,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      children: [
        _periodControls(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(12),
            children: cards,
          ),
        ),
      ],
    );
  }

  Widget _periodControls() => Padding(padding: const EdgeInsets.all(12), child: Row(children: [
    Expanded(child: SegmentedButton<_AttendancePeriod>(segments: const [ButtonSegment(value: _AttendancePeriod.daily, label: Text('Daily')), ButtonSegment(value: _AttendancePeriod.weekly, label: Text('Weekly')), ButtonSegment(value: _AttendancePeriod.monthly, label: Text('Monthly'))], selected: {_period}, onSelectionChanged: (value) => setState(() => _period = value.first))),
    IconButton(icon: const Icon(Icons.calendar_today_outlined), tooltip: 'Choose date', onPressed: () async { final date = await showDatePicker(context: context, initialDate: _reference, firstDate: DateTime(2020), lastDate: DateTime.now()); if (date != null) setState(() => _reference = date); }),
  ]));

  Widget _compensation(
    Map<dynamic, dynamic> users,
    Map<dynamic, dynamic> attendance,
    Map<dynamic, dynamic> summaries,
  ) {
    final cards = <Widget>[];

    for (final entry in _employeeEntries(users)) {
      final id = entry.key.toString();
      final name = _map(entry.value)['name']?.toString() ?? id;
      final records = _map(attendance[id]);
      final calculation = _calculateCompensation(records);
      final activity = calculation.activity;
      final outstanding = calculation.outstandingMinutes;

      if (activity.isNotEmpty || outstanding > 0) {
        cards.add(
          Card(
            child: ExpansionTile(
              title: Text(name),
              subtitle: Text(
                'Outstanding: ${AttendanceCalculator.formatHours(outstanding / 60)}',
              ),
              children: activity.isEmpty
                  ? const [
                      ListTile(title: Text('No compensation activity yet.')),
                    ]
                  : activity
                      .map(
                        (text) => ListTile(
                          leading: const Icon(Icons.schedule),
                          title: Text(text),
                        ),
                      )
                      .toList(),
            ),
          ),
        );
      }
    }

    return cards.isEmpty
        ? const Center(child: Text('No work-pending or compensation records.'))
        : ListView(padding: const EdgeInsets.all(12), children: cards);
  }

  /// Calculates monthly/overall compensation separately from the daily
  /// AttendanceCalculator.
  ///
  /// Extra time is pooled first. That pool is then applied to the smallest
  /// Work-Pending deficit first, exactly as required by the attendance rules.
  /// A pending day whose deficit is fully covered is therefore treated as a
  /// FULL DAY after compensation; a partially covered day remains
  /// WORK-PENDING with only its remaining deficit outstanding.
  _CompensationCalculation _calculateCompensation(Map<dynamic, dynamic> records) {
    final dates = records.keys.map((key) => key.toString()).toList()..sort();
    final pending = <_PendingDay>[];
    var compensationPool = 0;
    final activity = <String>[];

    for (final date in dates) {
      final record = _map(records[date]);

      // Temporary MIS-PUNCH records have no reliable actual punch-out yet.
      // Do not treat the temporary 11:59 closure as worked time or deficit.
      if (_isMisPunch(record)) {
        activity.add('$date • MIS-PUNCH pending admin punch-out');
        continue;
      }

      final result = _result(record);
      if (result == null) continue;

      final shortfallMinutes = (result.shortfallHours * 60).round();
      final extraMinutes = (result.extraHours * 60).round();

      if (shortfallMinutes > 0) {
        pending.add(_PendingDay(date: date, deficitMinutes: shortfallMinutes));
      }

      if (extraMinutes > 0) {
        compensationPool += extraMinutes;
        activity.add(
          '$date • earned ${AttendanceCalculator.formatHours(extraMinutes / 60)} extra',
        );
      }
    }

    // Least Work-Pending hour/day first.
    pending.sort((a, b) {
      final byDeficit = a.deficitMinutes.compareTo(b.deficitMinutes);
      if (byDeficit != 0) return byDeficit;
      return a.date.compareTo(b.date);
    });

    var outstanding = 0;
    for (final day in pending) {
      final original = day.deficitMinutes;
      final applied = compensationPool.clamp(0, original);
      compensationPool -= applied;
      final remaining = original - applied;
      outstanding += remaining;

      if (applied > 0 && remaining == 0) {
        activity.add(
          '${day.date} • ${AttendanceCalculator.formatHours(original / 60)} pending → FULL DAY after ${AttendanceCalculator.formatHours(applied / 60)} compensation',
        );
      } else if (applied > 0) {
        activity.add(
          '${day.date} • ${AttendanceCalculator.formatHours(original / 60)} pending → ${AttendanceCalculator.formatHours(remaining / 60)} outstanding after compensation',
        );
      } else {
        activity.add(
          '${day.date} • owes ${AttendanceCalculator.formatHours(original / 60)} • remains WORK-PENDING',
        );
      }
    }

    return _CompensationCalculation(
      outstandingMinutes: outstanding,
      activity: activity,
    );
  }

  /// Returns the final outstanding deficit after cross-day compensation.
  /// This method intentionally uses the same least-deficit-first algorithm as
  /// the Compensation tab so both places show the same balance.
  int _outstandingMinutes(Map<dynamic, dynamic> records) {
    return _calculateCompensation(records).outstandingMinutes;
  }

}

class _PendingDay {
  final String date;
  final int deficitMinutes;

  const _PendingDay({required this.date, required this.deficitMinutes});
}

class _CompensationCalculation {
  final int outstandingMinutes;
  final List<String> activity;

  const _CompensationCalculation({
    required this.outstandingMinutes,
    required this.activity,
  });
}

class _AdminAttendanceData {
  final Map<dynamic, dynamic> users;
  final Map<dynamic, dynamic> attendance;
  final Map<dynamic, dynamic> summaries;
  const _AdminAttendanceData({required this.users, required this.attendance, required this.summaries});
}