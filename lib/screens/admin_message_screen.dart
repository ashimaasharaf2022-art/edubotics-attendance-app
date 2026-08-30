import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../utils/attachment_upload.dart';

class SupportRequestScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  const SupportRequestScreen({super.key, required this.employeeId, required this.employeeName});
  @override State<SupportRequestScreen> createState() => _SupportRequestScreenState();
}

class _SupportRequestScreenState extends State<SupportRequestScreen> {
  final _message = TextEditingController();
  late final DatabaseReference _db;
  bool _sending = false;
  UploadedAttachment? _attachment;
  @override void initState() { super.initState(); _db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref(); }
  @override void dispose() { _message.dispose(); super.dispose(); }

  Future<void> _attach() async {
    try { final file = await AttachmentUpload.pickAndUpload('request_proofs/${widget.employeeId}'); if (mounted && file != null) setState(() => _attachment = file); }
    catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not upload the document. Please try again.'))); }
  }
  Future<void> _send() async {
    final text = _message.text.trim(); if (text.isEmpty) return;
    setState(() => _sending = true);
    final request = _db.child('AdminMessages').push();
    await request.set({'employeeId': widget.employeeId, 'employeeName': widget.employeeName, 'message': text, 'status': 'open', 'createdAt': DateTime.now().toIso8601String(), if (_attachment != null) 'attachment': _attachment!.toMap()});
    await _db.child('AdminNotifications').push().set({'title': 'New Employee Request', 'message': '${widget.employeeName} (${widget.employeeId}) sent a request.', 'read': false, 'createdAt': DateTime.now().toIso8601String()});
    if (!mounted) return;
    setState(() { _sending = false; _message.clear(); _attachment = null; });
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your request was sent to the admin team.')));
  }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Message Admin')),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Send a request to the Admin and Super Admin', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8), const Text('You can add a document or file as proof.', style: TextStyle(color: AppColors.textSecondary)), const SizedBox(height: 14),
        TextField(controller: _message, maxLines: 4, decoration: const InputDecoration(labelText: 'Your message', alignLabelWithHint: true)),
        TextButton.icon(onPressed: _attach, icon: const Icon(Icons.attach_file), label: Text(_attachment?.name ?? 'Add proof or document')),
        SizedBox(height: 52, child: ElevatedButton(onPressed: _sending ? null : _send, style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary), child: const Text('SEND REQUEST', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
      ])),
      const Divider(height: 1), const Padding(padding: EdgeInsets.all(12), child: Text('Your sent requests', style: TextStyle(fontWeight: FontWeight.bold))),
      Expanded(child: StreamBuilder<DatabaseEvent>(stream: _db.child('AdminMessages').orderByChild('employeeId').equalTo(widget.employeeId).onValue, builder: (_, snapshot) {
        if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text('No requests sent yet.'));
        final entries = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map).entries.toList().reversed.toList();
        return ListView.builder(itemCount: entries.length, itemBuilder: (_, i) { final entry = entries[i]; final data = Map<dynamic, dynamic>.from(entry.value as Map); final attachment = data['attachment'] is Map ? Map<dynamic, dynamic>.from(data['attachment'] as Map) : null;
          return ListTile(title: Text(data['message']?.toString() ?? ''), subtitle: attachment == null ? Text(data['status']?.toString() ?? '') : Text('Proof: ${attachment['name']}'), trailing: IconButton(tooltip: 'Delete request', icon: const Icon(Icons.delete_outline, color: AppColors.danger), onPressed: () => _db.child('AdminMessages').child(entry.key.toString()).remove()), onTap: attachment?['url'] == null ? null : () => launchUrl(Uri.parse(attachment!['url'].toString()), mode: LaunchMode.externalApplication));
        });
      }))
    ]),
  );
}

class AdminMessagesScreen extends StatelessWidget {
  const AdminMessagesScreen({super.key});
  @override Widget build(BuildContext context) {
    final db = FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app').ref();
    return Scaffold(appBar: AppBar(title: const Text('Employee Requests')), body: StreamBuilder<DatabaseEvent>(stream: db.child('AdminMessages').orderByChild('createdAt').onValue, builder: (_, snapshot) {
      if (!snapshot.hasData || snapshot.data!.snapshot.value == null) return const Center(child: Text('No employee requests yet.'));
      final values = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map).entries.toList().reversed.toList();
      return ListView.builder(padding: const EdgeInsets.all(16), itemCount: values.length, itemBuilder: (_, index) { final entry = values[index]; final data = Map<dynamic, dynamic>.from(entry.value as Map); return ListTile(title: Text(data['employeeName']?.toString() ?? data['employeeId'].toString()), subtitle: Text(data['message']?.toString() ?? ''), trailing: TextButton(onPressed: () => db.child('AdminMessages').child(entry.key.toString()).update({'status': 'resolved'}), child: const Text('Resolve'))); });
    }));
  }
}
