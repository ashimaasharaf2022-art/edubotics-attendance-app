import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

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
            final req = Map<String, dynamic>.from(reqEntry.value as Map);
            final status = req['status']?.toString().toLowerCase();
            if (status != 'pending' && status != 'returned') continue;
            req['_employeeId'] = employeeId;
            req['_requestId'] = reqEntry.key.toString();
            req['employeeName'] = await _employeeName(employeeId, req['employeeName']?.toString());
            result.add(req);
          }
        }
      }

      result.sort((a, b) => (b['updatedAt']?.toString() ?? b['createdAt']?.toString() ?? '')
          .compareTo(a['updatedAt']?.toString() ?? a['createdAt']?.toString() ?? ''));

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
    if (value is Map) {
      return value.values.map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<void> _review(Map<String, dynamic> request) async {
    final employeeId = request['_employeeId'].toString();
    final requestId = request['_requestId'].toString();
    final messageController = TextEditingController();
    final status = request['status']?.toString().toLowerCase() ?? 'pending';
    final dates = _dates(request['selectedDates']);

    final action = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
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
                Text(request['employeeName']?.toString() ?? employeeId,
                    style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text('Employee ID: $employeeId', style: const TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 14),
                const Text('Selected pending dates', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                ...dates.map((d) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• $d'),
                    )),
                const SizedBox(height: 12),
                const Text('Employee message', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(request['message']?.toString() ?? ''),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: messageController,
                  maxLines: 4,
                  decoration: InputDecoration(
                    labelText: status == 'returned' ? 'Correction instructions' : 'Message to employee',
                    hintText: 'If returning the request, explain exactly what needs to be corrected.',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                        child: const Text('APPROVE'),
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

    if ((action == 'returned' || action == 'rejected') && messageController.text.trim().isEmpty) {
      messageController.dispose();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please add a message before rejecting or returning the request.')),
        );
      }
      return;
    }

    try {
      final ref = dbRef.child('CompensationRequests').child(employeeId).child(requestId);
      await ref.update({
        'status': action,
        'adminId': widget.adminId,
        'adminName': widget.adminName,
        'reviewedAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
        'adminMessage': (action == 'returned' || action == 'rejected')
            ? messageController.text.trim()
            : null,
      });

      await dbRef.child('AdminActivityLog').push().set({
        'adminId': widget.adminId,
        'adminName': widget.adminName,
        'action': action == 'approved'
            ? 'Approved compensation request'
            : action == 'rejected'
                ? 'Rejected compensation request'
                : 'Returned compensation request',
        'employeeId': employeeId,
        'requestId': requestId,
        'timestamp': DateTime.now().toIso8601String(),
      });

      final notificationTitle = action == 'approved'
          ? 'Compensation request approved'
          : action == 'rejected'
              ? 'Compensation request rejected'
              : 'Compensation request returned';

      final notificationMessage = action == 'approved'
          ? 'Your compensation request for ${dates.join(', ')} was approved by the admin.'
          : action == 'rejected'
              ? 'Your compensation request for ${dates.join(', ')} was rejected. ${messageController.text.trim()}'
              : 'Your compensation request for ${dates.join(', ')} was returned for correction. ${messageController.text.trim()}' ;

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
                ? 'Compensation request approved.'
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
                        final status = request['status']?.toString().toLowerCase() ?? 'pending';
                        final dates = _dates(request['selectedDates']);
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
                                      const CircleAvatar(child: Icon(Icons.person_outline)),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(request['employeeName']?.toString() ?? request['_employeeId'].toString(), style: const TextStyle(fontWeight: FontWeight.w800)),
                                            Text('ID: ${request['_employeeId']}', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                          ],
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: (status == 'returned' ? AppColors.warning : AppColors.primary).withOpacity(.12),
                                          borderRadius: BorderRadius.circular(20),
                                        ),
                                        child: Text(status.toUpperCase(), style: TextStyle(color: status == 'returned' ? AppColors.warning : AppColors.primary, fontWeight: FontWeight.bold, fontSize: 10)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Text('Dates: ${dates.join(', ')}', style: const TextStyle(fontSize: 12)),
                                  const SizedBox(height: 6),
                                  Text(request['message']?.toString() ?? '', maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: AppColors.textSecondary)),
                                  const SizedBox(height: 10),
                                  const Align(alignment: Alignment.centerRight, child: Icon(Icons.arrow_forward_rounded)),
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
