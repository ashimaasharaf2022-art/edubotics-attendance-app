import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import '../utils/app_colors.dart';

class SupportRequestScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const SupportRequestScreen({super.key, required this.employeeId, required this.employeeName});
  @override State<SupportRequestScreen> createState() => _SupportRequestScreenState();
}

class _SupportRequestScreenState extends State<SupportRequestScreen> {
  final _message = TextEditingController();
  late DatabaseReference _db;
  bool _sending = false;
  @override void initState() { super.initState(); _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref(); }
  @override void dispose() { _message.dispose(); super.dispose(); }
  Future<void> _send() async {
    final text = _message.text.trim(); if (text.isEmpty) return;
    setState(() => _sending = true);
    await _db.child('AdminMessages').push().set({'employeeId': widget.employeeId, 'employeeName': widget.employeeName, 'message': text, 'status': 'open', 'createdAt': DateTime.now().toIso8601String()});
    await _db.child("AdminNotifications").push().set({
  "title": "New Employee Request",
  "message":
      "${widget.employeeName} (${widget.employeeId}) sent a request.",
  "read": false,
  "createdAt": DateTime.now().toIso8601String(),
});
    await _db.child("AdminNotifications").push().set({
  "title": "New Employee Request",
  "message":
      "${widget.employeeName} (${widget.employeeId}) sent a new request.",
  "read": false,
  "createdAt": DateTime.now().toIso8601String(),
});
    if (!mounted) return;
    setState(() => _sending = false); _message.clear();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your request was sent to the admin team.')));
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Message Admin')), body: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const Text('Send a request to the Admin and Super Admin', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)), const SizedBox(height: 8), const Text('Use this for attendance corrections, support, or work-related requests.', style: TextStyle(color: AppColors.textSecondary)), const SizedBox(height: 20), TextField(controller: _message, maxLines: 6, decoration: const InputDecoration(labelText: 'Your message', alignLabelWithHint: true)), const SizedBox(height: 18), SizedBox(height: 52, child: ElevatedButton(onPressed: _sending ? null : _send, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('SEND REQUEST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)) ))])));
}

class AdminMessagesScreen extends StatelessWidget {
  const AdminMessagesScreen({super.key});
  @override Widget build(BuildContext context) {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
    return Scaffold(
      appBar: AppBar(title: const Text('Employee Requests')),
      body: StreamBuilder<DatabaseEvent>(
        stream: db.child('AdminMessages').orderByChild('createdAt').onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text('No employee requests yet.'));
          final values = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map).entries.toList().reversed.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: values.length,
            itemBuilder: (_, index) {
              final entry = values[index];
              final data = Map<dynamic, dynamic>.from(entry.value as Map);
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                child: ListTile(
                  leading: const Icon(Icons.markunread_outlined, color: AppColors.primary),
                  title: Text(data['employeeName']?.toString() ?? data['employeeId'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(data['message']?.toString() ?? ''),
                  trailing: TextButton(onPressed: () => db.child('AdminMessages').child(entry.key.toString()).update({'status': 'resolved'}), child: const Text('Resolve')),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
