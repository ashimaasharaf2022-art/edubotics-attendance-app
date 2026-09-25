import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/notification_center.dart';
import '../utils/attendance_calculator.dart';

/// Admin screen for reviewing employee incomplete-duty and overtime
/// compensation requests.
///
/// Important rules:
/// - An incomplete-duty request is only a reason/message. Approving it does
///   NOT regularize the attendance day.
/// - Overtime is consumed only after an admin approves an overtime request.
/// - Regularization uses the selected OD minutes against the requested ID.
/// - The system never uses OD from an ID day and never uses the temporary
///   MIS-PUNCH checkout as real working time.
/// - After every approved compensation, AttendanceSummary is recalculated.
class AdminCompensationRequestsScreen extends StatefulWidget {
  final String adminId;
  final String adminName;

  const AdminCompensationRequestsScreen({
    super.key,
    required this.adminId,
    required this.adminName,
  });

  @override
  State<AdminCompensationRequestsScreen> createState() =>
      _AdminCompensationRequestsScreenState();
}

class _AdminCompensationRequestsScreenState
    extends State<AdminCompensationRequestsScreen> {
  late DatabaseReference dbRef;
  bool loading = true;
  List<Map<String, dynamic>> requests = [];

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
    _load();
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  int _int(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _string(dynamic value) => value?.toString().trim() ?? '';

  Future<String> _employeeName(String employeeId, String? current) async {
    if (current != null && current.trim().isNotEmpty && current != employeeId) {
      return current.trim();
    }
    try {
      final snap = await dbRef.child('users').child(employeeId).get();
      if (snap.exists && snap.value is Map) {
        final map = Map<dynamic, dynamic>.from(snap.value as Map);
        final name = map['name']?.toString().trim();
        if (name != null && name.isNotEmpty) return name;
      }
    } catch (_) {}
    return current?.trim().isNotEmpty == true ? current!.trim() : employeeId;
  }

  Future<void> _load() async {
    if (mounted) setState(() => loading = true);
    try {
      final snap = await dbRef.child('CompensationRequests').get();
      final result = <Map<String, dynamic>>[];

      if (snap.exists && snap.value is Map) {
        final employees = Map<dynamic, dynamic>.from(snap.value as Map);
        for (final empEntry in employees.entries) {
          if (empEntry.value is! Map) continue;
          final employeeId = empEntry.key.toString();
          final requestMap = Map<dynamic, dynamic>.from(empEntry.value as Map);

          for (final reqEntry in requestMap.entries) {
            if (reqEntry.value is! Map) continue;
            final req = _map(reqEntry.value);
            final status = _string(req['status']).toLowerCase();
            if (status != 'pending' && status != 'returned') continue;

            req['_employeeId'] = employeeId;
            req['_requestId'] = reqEntry.key.toString();
            req['employeeName'] = await _employeeName(
              employeeId,
              req['employeeName']?.toString(),
            );
            result.add(req);
          }
        }
      }

      result.sort(
        (a, b) => (_string(b['updatedAt']).isNotEmpty
                ? _string(b['updatedAt'])
                : _string(b['createdAt']))
            .compareTo(
          _string(a['updatedAt']).isNotEmpty
              ? _string(a['updatedAt'])
              : _string(a['createdAt']),
        ),
      );

      if (!mounted) return;
      setState(() {
        requests = result;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load compensation requests: $e')),
      );
    }
  }

  List<String> _dates(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    if (value is Map) return value.values.map((e) => e.toString()).toList();
    return [];
  }

  Future<Map<String, Map<String, dynamic>>> _loadAttendance(
    String employeeId,
  ) async {
    final snap = await dbRef.child('Attendance').child(employeeId).get();
    final result = <String, Map<String, dynamic>>{};
    if (!snap.exists || snap.value is! Map) return result;

    final raw = Map<dynamic, dynamic>.from(snap.value as Map);
    for (final entry in raw.entries) {
      if (entry.value is Map) {
        result[entry.key.toString()] = _map(entry.value);
      }
    }
    return result;
  }

  List<AttendanceSession> _sessions(Map<String, dynamic> record) {
    final result = <AttendanceSession>[];
    final raw = record['sessions'];

    if (raw is List) {
      for (final item in raw) {
        final map = _map(item);
        if (_string(map['punchIn']).isNotEmpty) {
          result.add(
            AttendanceSession(
              punchIn: _string(map['punchIn']),
              punchOut: _string(map['punchOut']).isEmpty
                  ? null
                  : _string(map['punchOut']),
            ),
          );
        }
      }
    } else if (raw is Map) {
      final entries = raw.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      for (final entry in entries) {
        final map = _map(entry.value);
        if (_string(map['punchIn']).isNotEmpty) {
          result.add(
            AttendanceSession(
              punchIn: _string(map['punchIn']),
              punchOut: _string(map['punchOut']).isEmpty
                  ? null
                  : _string(map['punchOut']),
            ),
          );
        }
      }
    }

    if (result.isEmpty && _string(record['punchIn']).isNotEmpty) {
      result.add(
        AttendanceSession(
          punchIn: _string(record['punchIn']),
          punchOut: _string(record['punchOut']).isEmpty
              ? null
              : _string(record['punchOut']),
        ),
      );
    }

    return result;
  }

  AttendanceResult? _calculate(Map<String, dynamic> record) {
    final sessions = _sessions(record);
    if (sessions.isEmpty) return null;

    final open = sessions.any(
      (s) => s.punchOut == null || s.punchOut!.trim().isEmpty,
    );
    if (open) return null;

    final raw = AttendanceCalculator.calculateFromSessions(
      sessions,
      workFromHome: record['workFromHome'] == true,
    );

    final regularized = _int(
      record['regularizedMinutes'] ?? record['compensatedMinutes'],
    );
    final odUsed = _int(
      record['odUsedMinutes'] ?? record['overtimeUsedMinutes'],
    );

    final rawMinutes = (raw.netHours * 60).round();
    final effectiveMinutes = rawMinutes + regularized;
    final remainingExtra =
        ((raw.extraHours * 60).round() - odUsed).clamp(0, 1000000);

    if (effectiveMinutes >= AttendanceCalculator.requiredMinutes) {
      return AttendanceResult(
        dayType: DayType.fullDay,
        netHours: effectiveMinutes / 60.0,
        shortfallHours: 0,
        extraHours: remainingExtra / 60.0,
        label: record['workFromHome'] == true
            ? 'Full Day (WFH)'
            : 'Full Day',
      );
    }

    final shortfall = AttendanceCalculator.requiredMinutes - effectiveMinutes;
    return AttendanceResult(
      dayType: DayType.workPending,
      netHours: effectiveMinutes / 60.0,
      shortfallHours: shortfall / 60.0,
      extraHours: 0,
      label: record['workFromHome'] == true
          ? 'Work-Pending (WFH)'
          : 'Work-Pending',
    );
  }

  int _remainingOdMinutes(Map<String, dynamic> record) {
    final calculation = _calculate(record);
    if (calculation == null) return 0;
    return (calculation.extraHours * 60).round();
  }

  int _remainingIdMinutes(Map<String, dynamic> record) {
    final calculation = _calculate(record);
    if (calculation == null) return 0;
    return (calculation.shortfallHours * 60).round();
  }

  bool _isMisPunch(Map<String, dynamic> record) {
    final status = _string(record['status']).toUpperCase();
    return status == 'MIS-PUNCH' ||
        record['misPunch'] == true ||
        record['mis_punch'] == true;
  }

  bool _isLeaveLike(Map<String, dynamic> record) {
    final status = _string(record['attendanceStatus']).toUpperCase();
    return status == 'LEAVE';
  }

  Future<void> _refreshSummary(
    String employeeId,
    Map<String, Map<String, dynamic>> attendance,
  ) async {
    var outstanding = 0;
    var availableOd = 0;

    for (final record in attendance.values) {
      if (_isMisPunch(record) || _isLeaveLike(record)) continue;
      outstanding += _remainingIdMinutes(record);
      availableOd += _remainingOdMinutes(record);
    }

    final summaryRef = dbRef.child('AttendanceSummary').child(employeeId);
    final previous = await summaryRef.get();
    final previousMap = previous.exists ? _map(previous.value) : <String, dynamic>{};
    final granted = _int(previousMap['compOffGrantedDays']);
    final used = _int(previousMap['compOffUsedDays']);

    await summaryRef.update({
      'outstandingMinutes': outstanding,
      'availableOvertimeMinutes': availableOd,
      'compOffGrantedDays': granted,
      'compOffUsedDays': used,
      'compOffAvailableDays': (granted - used).clamp(0, 1000000),
      'updatedAt': DateTime.now().toIso8601String(),
    });
  }

  Future<bool> _applyApprovedOvertime(
    String employeeId,
    Map<String, dynamic> request,
  ) async {
    final type = _string(request['compensationType']);
    final requested = _int(request['requestedMinutes']);
    final targetDate = _string(request['targetDate']);
    final sourceDate = _string(request['date']);

    if (requested <= 0) return false;

    final attendance = await _loadAttendance(employeeId);
    if (attendance.isEmpty) return false;

    // ---------------------------------------------------------------
    // REGULARIZE: OD -> the ID that needs the least time.
    // ---------------------------------------------------------------
    if (type == 'Regularize attendance') {
      if (targetDate.isEmpty || !attendance.containsKey(targetDate)) {
        throw StateError('The selected incomplete-duty day no longer exists.');
      }

      final target = attendance[targetDate]!;
      final targetMissing = _remainingIdMinutes(target);
      if (targetMissing <= 0) {
        throw StateError('The selected day is no longer an incomplete duty.');
      }

      // Recheck that the employee still has no other active ID conflict is not
      // necessary here; this request explicitly targets one ID day.
      var needed = targetMissing;
      var remainingToUse = requested < needed ? requested : needed;

      if (remainingToUse <= 0) return false;

      final sourceDates = <String>[];
      if (sourceDate.isNotEmpty && attendance.containsKey(sourceDate)) {
        sourceDates.add(sourceDate);
      }
      for (final entry in attendance.entries) {
        if (entry.key == sourceDate) continue;
        if (_remainingOdMinutes(entry.value) > 0) sourceDates.add(entry.key);
      }

      for (final date in sourceDates) {
        if (remainingToUse <= 0) break;
        final record = attendance[date]!;
        final od = _remainingOdMinutes(record);
        if (od <= 0) continue;

        final used = remainingToUse < od ? remainingToUse : od;
        record['odUsedMinutes'] = _int(record['odUsedMinutes']) + used;
        record['overtimeUsedMinutes'] = _int(record['overtimeUsedMinutes']) + used;
        attendance[date] = record;
        remainingToUse -= used;
      }

      final actuallyUsed = requested - remainingToUse;
      if (actuallyUsed <= 0) {
        throw StateError('There is not enough verified overtime available.');
      }

      target['regularizedMinutes'] =
          _int(target['regularizedMinutes'] ?? target['compensatedMinutes']) + actuallyUsed;
      target['compensatedMinutes'] = _int(target['compensatedMinutes']) + actuallyUsed;
      attendance[targetDate] = target;

      await _writeAttendanceMap(employeeId, attendance);
      return true;
    }

    // ---------------------------------------------------------------
    // COMP-OFF / EXTRA PAY: consume verified OD only.
    // ---------------------------------------------------------------
    var remainingToUse = requested;

    // Prefer the OD day the employee clicked, then use other OD days if
    // required. This makes comp-off work even when 9h is spread across days.
    final sourceDates = <String>[];
    if (sourceDate.isNotEmpty && attendance.containsKey(sourceDate)) {
      sourceDates.add(sourceDate);
    }
    final otherDates = attendance.entries
        .where((e) => e.key != sourceDate && _remainingOdMinutes(e.value) > 0)
        .map((e) => e.key)
        .toList()
      ..sort();
    sourceDates.addAll(otherDates);

    for (final date in sourceDates) {
      if (remainingToUse <= 0) break;
      final record = attendance[date]!;
      final od = _remainingOdMinutes(record);
      if (od <= 0) continue;

      final used = remainingToUse < od ? remainingToUse : od;
      record['odUsedMinutes'] = _int(record['odUsedMinutes']) + used;
      record['overtimeUsedMinutes'] = _int(record['overtimeUsedMinutes']) + used;
      attendance[date] = record;
      remainingToUse -= used;
    }

    final actuallyUsed = requested - remainingToUse;
    if (actuallyUsed <= 0) {
      throw StateError('There is not enough verified overtime available.');
    }

    if (type == 'Comp-off (extra day off)') {
      if (actuallyUsed % AttendanceCalculator.requiredMinutes != 0) {
        throw StateError('A comp-off day requires 9 verified overtime hours.');
      }

      final daysGranted = actuallyUsed ~/ AttendanceCalculator.requiredMinutes;
      final balanceRef = dbRef.child('CompOffBalances').child(employeeId);
      final balanceSnap = await balanceRef.get();
      final balance = balanceSnap.exists ? _map(balanceSnap.value) : <String, dynamic>{};
      final granted = _int(balance['grantedDays']);
      final used = _int(balance['usedDays']);

      await balanceRef.update({
        'grantedDays': granted + daysGranted,
        'usedDays': used,
        'availableDays': (granted + daysGranted - used).clamp(0, 1000000),
        'lastGrantedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      });
    } else if (type == 'Extra pay') {
      final payRef = dbRef.child('ExtraPayBalances').child(employeeId);
      final paySnap = await payRef.get();
      final pay = paySnap.exists ? _map(paySnap.value) : <String, dynamic>{};
      final approved = _int(pay['approvedMinutes']);

      await payRef.update({
        'approvedMinutes': approved + actuallyUsed,
        'updatedAt': DateTime.now().toIso8601String(),
      });
    }

    await _writeAttendanceMap(employeeId, attendance);
    return true;
  }

  Future<void> _writeAttendanceMap(
    String employeeId,
    Map<String, Map<String, dynamic>> attendance,
  ) async {
    final updates = <String, dynamic>{};
    for (final entry in attendance.entries) {
      updates['Attendance/$employeeId/${entry.key}'] = entry.value;
    }
    if (updates.isNotEmpty) {
      await dbRef.update(updates);
    }
  }

  String _requestDateLabel(Map<String, dynamic> request) {
    final type = _string(request['compensationType']);
    final targetDate = _string(request['targetDate']);
    final sourceDate = _string(request['date']);

    if (type == 'Regularize attendance') {
      final target = targetDate.isEmpty ? 'Not specified' : targetDate;
      final source = sourceDate.isEmpty ? 'Not specified' : sourceDate;
      return 'ID / Target: $target\nOD / Source: $source';
    }

    if (type == 'Comp-off (extra day off)' || type == 'Extra pay') {
      return 'OD / Source: ${sourceDate.isEmpty ? 'Not specified' : sourceDate}';
    }

    return 'Dates: ${_dates(request['selectedDates']).join(', ')}';
  }

  String _recordWorkedLabel(Map<String, dynamic> record) {
    final result = _calculate(record);
    if (result == null) {
      return _isMisPunch(record) ? 'MIS-PUNCH / checkout needs verification' : 'Open or incomplete punch data';
    }
    final worked = (result.netHours * 60).round();
    final id = _remainingIdMinutes(record);
    final od = _remainingOdMinutes(record);
    return '${result.label} • Worked ${_hours(worked)} • ID ${_hours(id)} • OD ${_hours(od)}';
  }

  Future<void> _showEmployeeAttendance(
    String employeeId,
    String employeeName,
    List<String> focusDates,
  ) async {
    try {
      final attendance = await _loadAttendance(employeeId);
      if (!mounted) return;

      final entries = attendance.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));
      final focused = focusDates.isEmpty
          ? entries
          : entries.where((e) => focusDates.contains(e.key)).toList();
      final visible = focused.isEmpty ? entries : focused;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (sheetContext) => Container(
          height: MediaQuery.of(sheetContext).size.height * .82,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '$employeeName — Attendance',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              Text(
                'Employee ID: $employeeId',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
              if (focusDates.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Verification dates: ${focusDates.join(', ')}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: visible.isEmpty
                    ? const Center(child: Text('No attendance records found.'))
                    : ListView.separated(
                        itemCount: visible.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, index) {
                          final entry = visible[index];
                          final date = entry.key;
                          final record = entry.value;
                          final sessions = _sessions(record);
                          final punchText = sessions.isEmpty
                              ? 'No punch sessions'
                              : sessions.map((session) {
                                  final out = session.punchOut == null || session.punchOut!.isEmpty
                                      ? 'OPEN'
                                      : session.punchOut!;
                                  return '${session.punchIn} → $out';
                                }).join('\n');

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.background,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.divider),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        date,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                    ),
                                    if (_isMisPunch(record))
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(alpha: .14),
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: const Text(
                                          'MIS-PUNCH',
                                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Text(_recordWorkedLabel(record)),
                                const SizedBox(height: 6),
                                Text(
                                  punchText,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                                if (_string(record['punchoutRequestStatus']).isNotEmpty) ...[
                                  const SizedBox(height: 5),
                                  Text(
                                    'Punch-out request: ${_string(record['punchoutRequestStatus']).toUpperCase()}',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load employee attendance: $e')),
      );
    }
  }

  Future<void> _review(Map<String, dynamic> request) async {
    final employeeId = _string(request['_employeeId']);
    final requestId = _string(request['_requestId']);
    final requestType = _string(request['requestType']).toLowerCase();
    final messageController = TextEditingController();
    final status = _string(request['status']).toLowerCase();
    final dates = _dates(request['selectedDates']);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  request['employeeName']?.toString() ?? employeeId,
                  style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  'Employee ID: $employeeId',
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 10),
                Text(
                  requestType == 'incomplete_duty'
                      ? 'Incomplete Duty Reason'
                      : 'Overtime Compensation Request',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  'Type: ${_string(request['compensationType']).isEmpty ? requestType : request['compensationType']}',
                  style: const TextStyle(fontSize: 12),
                ),
                if (_string(request['requestedMinutes']).isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Requested: ${_hours(_int(request['requestedMinutes']))}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Verification dates',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(_requestDateLabel(request)),
                ),
                if (dates.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Submitted dates: ${dates.join(', ')}',
                    style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  ),
                ],
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showEmployeeAttendance(
                      employeeId,
                      request['employeeName']?.toString() ?? employeeId,
                      <String>{
                        ...dates,
                        if (_string(request['targetDate']).isNotEmpty) request['targetDate'].toString(),
                        if (_string(request['date']).isNotEmpty) request['date'].toString(),
                      }.toList(),
                    ),
                    icon: const Icon(Icons.fact_check_outlined),
                    label: const Text('VIEW EMPLOYEE ATTENDANCE'),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Employee message',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _string(request['message']).isEmpty
                        ? _string(request['reason'])
                        : _string(request['message']),
                  ),
                ),
                if (_string(request['compensationDayMessage']).isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Text(
                    'Employee compensation-day note',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(_string(request['compensationDayMessage'])),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: status == 'returned'
                        ? 'Correction instructions'
                        : 'Message to employee',
                    hintText: 'Required when returning or rejecting.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.danger,
                        ),
                        onPressed: () => Navigator.pop(sheetContext, 'rejected'),
                        child: const Text('REJECT'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext, 'returned'),
                        child: const Text('RETURN'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(sheetContext, 'approved'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                        ),
                        child: Text(
                          requestType == 'incomplete_duty'
                              ? 'ACKNOWLEDGE'
                              : 'APPROVE',
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (action == null) {
      messageController.dispose();
      return;
    }

    if ((action == 'returned' || action == 'rejected') &&
        messageController.text.trim().isEmpty) {
      messageController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Please add a message before rejecting or returning the request.',
            ),
          ),
        );
      }
      return;
    }

    try {
      final ref = dbRef
          .child('CompensationRequests')
          .child(employeeId)
          .child(requestId);

      if (action == 'approved' && requestType == 'overtime') {
        final applied = await _applyApprovedOvertime(employeeId, request);
        if (!applied) {
          throw StateError('No verified overtime could be applied to this request.');
        }
      }

      await ref.update({
        'status': action,
        'adminId': widget.adminId,
        'adminName': widget.adminName,
        'reviewedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'adminMessage': (action == 'returned' || action == 'rejected')
            ? messageController.text.trim()
            : null,
        if (action == 'approved' && requestType == 'overtime')
          'appliedAt': DateTime.now().toIso8601String(),
      });

      if (action == 'approved' && requestType == 'overtime') {
        final attendance = await _loadAttendance(employeeId);
        await _refreshSummary(employeeId, attendance);
      }

      await dbRef.child('AdminActivityLog').push().set({
        'adminId': widget.adminId,
        'adminName': widget.adminName,
        'action': action == 'approved'
            ? requestType == 'incomplete_duty'
                ? 'Acknowledged incomplete-duty reason'
                : 'Applied overtime compensation'
            : action == 'rejected'
                ? 'Rejected compensation request'
                : 'Returned compensation request',
        'employeeId': employeeId,
        'requestId': requestId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final notificationTitle = action == 'approved'
          ? requestType == 'incomplete_duty'
              ? 'Incomplete-duty reason acknowledged'
              : 'Compensation request approved'
          : action == 'rejected'
              ? 'Compensation request rejected'
              : 'Compensation request returned';

      final notificationMessage = action == 'approved'
          ? requestType == 'incomplete_duty'
              ? 'Your incomplete-duty reason for ${dates.join(', ')} was acknowledged by the admin. The day is not regularized by this request.'
              : 'Your compensation request for ${dates.join(', ')} was approved and the verified overtime was applied.'
          : action == 'rejected'
              ? 'Your compensation request for ${dates.join(', ')} was rejected. ${messageController.text.trim()}'
              : 'Your compensation request for ${dates.join(', ')} was returned for correction. ${messageController.text.trim()}';

      await NotificationCenter.send(
        employeeId: employeeId,
        title: notificationTitle,
        message: notificationMessage,
      );

      if (!mounted) return;
      messageController.dispose();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'approved'
                ? requestType == 'incomplete_duty'
                    ? 'Incomplete-duty reason acknowledged.'
                    : 'Compensation approved and attendance updated.'
                : action == 'rejected'
                    ? 'Compensation request rejected.'
                    : 'Request returned to employee.',
          ),
        ),
      );
      await _load();
    } catch (e) {
      messageController.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update request: $e')),
      );
    }
  }

  String _hours(int minutes) {
    final safe = minutes < 0 ? 0 : minutes;
    return '${safe ~/ 60}h ${safe % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Compensation Requests'),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: requests.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 180),
                        Center(child: Text('No compensation requests.')),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: requests.length,
                      itemBuilder: (_, index) {
                        final request = requests[index];
                        final status =
                            _string(request['status']).toLowerCase();
                        final dates = _dates(request['selectedDates']);
                        final type =
                            _string(request['requestType']).toLowerCase();
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          child: InkWell(
                            onTap: () => _review(request),
                            borderRadius: BorderRadius.circular(14),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        child: Icon(Icons.person_outline),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              request['employeeName']?.toString() ??
                                                  request['_employeeId'].toString(),
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            Text(
                                              'ID: ${request['_employeeId']}',
                                              style: const TextStyle(
                                                color: AppColors.textSecondary,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: (status == 'returned'
                                                  ? AppColors.warning
                                                  : AppColors.primary)
                                              .withValues(alpha: .12),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            color: status == 'returned'
                                                ? AppColors.warning
                                                : AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    type == 'incomplete_duty'
                                        ? 'Incomplete duty reason'
                                        : _string(request['compensationType']).isEmpty
                                            ? 'Overtime compensation'
                                            : _string(request['compensationType']),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 5),
                                  Text(
                                    _requestDateLabel(request),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (dates.isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Submitted: ${dates.join(', ')}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ],
                                  if (_int(request['requestedMinutes']) > 0) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'Requested: ${_hours(_int(request['requestedMinutes']))}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                  const SizedBox(height: 6),
                                  Text(
                                    _string(request['message']).isEmpty
                                        ? _string(request['reason'])
                                        : _string(request['message']),
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  const Align(
                                    alignment: Alignment.centerRight,
                                    child: Icon(Icons.arrow_forward_rounded),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
