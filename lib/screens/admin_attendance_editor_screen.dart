import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/activity_logger.dart';
import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';

/// Admin-only correction tool. It deliberately writes to the same Attendance
/// records used by employee punch flows, so historic reports stay consistent.
class AdminAttendanceEditorScreen extends StatefulWidget {
  final String adminId;
  final String adminName;
  final String employeeId;
  final String employeeName;

  const AdminAttendanceEditorScreen({super.key, required this.adminId, required this.adminName, required this.employeeId, required this.employeeName});

  @override
  State<AdminAttendanceEditorScreen> createState() => _AdminAttendanceEditorScreenState();
}

class _AdminAttendanceEditorScreenState extends State<AdminAttendanceEditorScreen> {
  late DatabaseReference _db;
  DateTime _date = DateTime.now();
  TimeOfDay? _inTime;
  TimeOfDay? _outTime;
  bool _saving = false;

  String get _dateKey => DateFormat('yyyy-MM-dd').format(_date);
  String _format(TimeOfDay? time) => time == null ? '--:--' : time.format(context);

  @override
  void initState() {
    super.initState();
    _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
    _loadRecord();
  }

  Future<void> _loadRecord() async {
    final snap = await _db.child('Attendance').child(widget.employeeId).child(_dateKey).get();
    if (!mounted) return;
    if (!snap.exists) {
      setState(() { _inTime = null; _outTime = null; });
      return;
    }
    final data = Map<dynamic, dynamic>.from(snap.value as Map);
    TimeOfDay? parse(dynamic value) {
      if (value == null) return null;
      try { final d = DateFormat('h:mm a').parse(value.toString()); return TimeOfDay(hour: d.hour, minute: d.minute); } catch (_) { return null; }
    }
    setState(() { _inTime = parse(data['punchIn']); _outTime = parse(data['punchOut']); });
  }

  Future<void> _pickDate() async {
    final value = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime(2020), lastDate: DateTime.now());
    if (value == null) return;
    setState(() => _date = value);
    await _loadRecord();
  }

  Future<void> _pickTime(bool isIn) async {
    final picked = await showTimePicker(context: context, initialTime: isIn ? (_inTime ?? const TimeOfDay(hour: 9, minute: 30)) : (_outTime ?? const TimeOfDay(hour: 18, minute: 0)));
    if (picked != null) setState(() { if (isIn) _inTime = picked; else _outTime = picked; });
  }

  Future<void> _save() async {
    if (_inTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a check-in time.')));
      return;
    }
    setState(() => _saving = true);
    final inText = _format(_inTime);
    final outText = _outTime == null ? null : _format(_outTime);
    final result = AttendanceCalculator.calculate(punchIn: inText, punchOut: outText);
    await _db.child('Attendance').child(widget.employeeId).child(_dateKey).update({
      'employeeId': widget.employeeId,
      'date': _dateKey,
      'punchIn': inText,
      'punchOut': outText,
      'status': outText == null ? 'Checked In' : 'Checked Out',
      'dayType': result.label,
      'manualEdited': true,
      'manualEditedBy': widget.adminId,
      'manualEditedAt': DateTime.now().toIso8601String(),
    });
    await ActivityLogger.log(adminId: widget.adminId, adminName: widget.adminName, action: 'Edited Attendance', details: '${widget.employeeId} · $_dateKey');
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance saved.')));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(title: const Text('Edit Attendance')),
    body: ListView(padding: const EdgeInsets.all(20), children: [
      Text(widget.employeeName, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
      Text(widget.employeeId, style: const TextStyle(color: AppColors.textSecondary)),
      const SizedBox(height: 22),
      _pickerTile(Icons.calendar_today_outlined, 'Attendance date', DateFormat('EEE, dd MMM yyyy').format(_date), _pickDate),
      _pickerTile(Icons.login_rounded, 'Check in', _format(_inTime), () => _pickTime(true)),
      _pickerTile(Icons.logout_rounded, 'Check out', _format(_outTime), () => _pickTime(false)),
      const SizedBox(height: 12),
      const Text('Manual edits are recorded in the activity log and may be made for previous dates.', style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
      const SizedBox(height: 24),
      SizedBox(height: 52, child: ElevatedButton(onPressed: _saving ? null : _save, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: _saving ? const CircularProgressIndicator(color: Colors.white) : const Text('SAVE ATTENDANCE', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
    ]),
  );

  Widget _pickerTile(IconData icon, String title, String value, VoidCallback onTap) => Container(margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card), child: ListTile(onTap: onTap, leading: Icon(icon, color: AppColors.primary), title: Text(title), trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w800))));
}
