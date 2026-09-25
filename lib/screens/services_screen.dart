
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/location_helper.dart';
import 'leave_screen.dart';
import 'documents_screen.dart';
import 'support_request_screen.dart';

class ServicesScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;

  const ServicesScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
  });

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  bool _showLeave = false;
  bool _showDocuments = false;
  bool _showTicket = false;
  int _totalLeaveBalance = 0;
  String? _wfhStatusToday;

  late DatabaseReference _dbRef;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
    _loadLeaveBalance();
    _loadWfhStatus();
  }

  Future<void> _loadLeaveBalance() async {
    try {
      final year = DateTime.now().year.toString();
      final snapshot = await _dbRef
          .child('LeaveBalances')
          .child(widget.employeeId)
          .child(year)
          .get();

      if (!snapshot.exists || snapshot.value is! Map) return;

      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      var total = 0;
      for (final value in data.values) {
        total += int.tryParse(value.toString()) ?? 0;
      }

      if (mounted) {
        setState(() => _totalLeaveBalance = total);
      }
    } catch (_) {
      // Keep the service card usable even if the balance cannot be loaded.
    }
  }

  void _openLeave() {
    setState(() => _showLeave = true);
  }

  void _closeLeave() {
    if (!mounted) return;
    setState(() => _showLeave = false);
    _loadLeaveBalance();
  }

  String _todayKey() {
    final now = DateTime.now();
    return '${now.year.toString().padLeft(4, '0')}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
  }

  Future<void> _loadWfhStatus() async {
    try {
      final snapshot = await _dbRef
          .child('WorkFromHomeRequests')
          .child(widget.employeeId)
          .child(_todayKey())
          .get();

      if (!mounted) return;

      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        setState(() {
          _wfhStatusToday = data['status']?.toString().toLowerCase();
        });
      } else {
        setState(() => _wfhStatusToday = null);
      }
    } catch (_) {
      // Keep the service card usable if the status cannot be loaded.
    }
  }

  Future<void> _requestWfh() async {
    final existingSnapshot = await _dbRef
        .child('WorkFromHomeRequests')
        .child(widget.employeeId)
        .child(_todayKey())
        .get();

    if (existingSnapshot.exists && existingSnapshot.value is Map) {
      final data =
          Map<dynamic, dynamic>.from(existingSnapshot.value as Map);
      final status = data['status']?.toString().toLowerCase();

      if (status == 'pending') {
        if (mounted) {
          _showWfhMessage('Your Work From Home request is waiting for admin approval.');
        }
        return;
      }

      if (status == 'approved') {
        if (mounted) {
          _showWfhMessage(
            'Your Work From Home request is approved for today.',
          );
        }
        return;
      }
    }

    final locationState = await LocationHelper.getCurrentLocation();
    final status = locationState.$1;
    final location = locationState.$2;

    if (status != LocationStatus.granted || location == null) {
      if (!mounted) return;

      String message = 'Unable to get your current location.';
      if (status == LocationStatus.denied) {
        message = 'Location permission is required to submit a WFH request.';
      } else if (status == LocationStatus.serviceDisabled) {
        message = 'Please enable location services and try again.';
      } else if (status == LocationStatus.mockDetected) {
        message = 'A mock location was detected. WFH request was not submitted.';
      }

      _showWfhMessage(message);
      return;
    }

    final date = _todayKey();
    final requestRef = _dbRef
        .child('WorkFromHomeRequests')
        .child(widget.employeeId)
        .child(date);

    await requestRef.update({
      'employeeId': widget.employeeId,
      'employeeName': widget.employeeName,
      'status': 'pending',
      'requestedAt': DateTime.now().toIso8601String(),
      'latitude': location.latitude,
      'longitude': location.longitude,
      'address': location.address,
    });

    if (!mounted) return;

    setState(() => _wfhStatusToday = 'pending');

    _showWfhMessage(
      'Work From Home request sent for admin approval.',
    );
  }

  void _showWfhMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openWfh() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final status = _wfhStatusToday;

        String statusTitle;
        String statusDescription;
        IconData statusIcon;

        switch (status) {
          case 'approved':
            statusTitle = 'Work From Home approved';
            statusDescription =
                'Your WFH request for today has been approved. Your next check-in can be recorded as WFH.';
            statusIcon = Icons.check_circle_outline_rounded;
            break;
          case 'pending':
            statusTitle = 'WFH request pending';
            statusDescription =
                'Your request has been sent to the admin and is waiting for approval.';
            statusIcon = Icons.hourglass_top_rounded;
            break;
          case 'rejected':
            statusTitle = 'WFH request rejected';
            statusDescription =
                'Your previous request was rejected. You can submit a new request for today.';
            statusIcon = Icons.cancel_outlined;
            break;
          default:
            statusTitle = 'Work From Home';
            statusDescription =
                'Request permission to work from home today. Admin approval is required before a WFH punch-in.';
            statusIcon = Icons.home_work_outlined;
        }

        return SafeArea(
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(28),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 38,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.divider,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: AppColors.veryLightGreen,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        statusIcon,
                        color: AppColors.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        statusTitle,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  statusDescription,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 16),
                Material(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Your current location will be saved with the request for admin verification.',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (status == 'approved') ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Approved for today',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ] else if (status == 'pending') ...[
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(50),
                        side: const BorderSide(color: AppColors.greenBorder),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: const Text(
                        'Request pending',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ] else ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(sheetContext);
                        await _requestWfh();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: Text(
                        status == 'rejected'
                            ? 'Request again'
                            : 'Request Work From Home',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  void _openDocuments() {
    setState(() => _showDocuments = true);
  }

  void _closeDocuments() {
    if (!mounted) return;
    setState(() => _showDocuments = false);
  }

  void _showComingSoon(BuildContext sheetContext, String title) {
    Navigator.pop(sheetContext);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$title will be available here when issued.')),
    );
  }

  void _openTicket() => setState(() => _showTicket = true);

  void _closeTicket() {
    if (!mounted) return;
    setState(() => _showTicket = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_showTicket) {
      return SupportRequestScreen(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        onBack: _closeTicket,
      );
    }

    if (_showDocuments) {
      return DocumentsScreen(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        onBack: _closeDocuments,
      );
    }

    if (_showLeave) {
      return LeaveScreen(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        onBack: _closeLeave,
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
          children: [
            const SizedBox(height: 4),
            const Text(
              'Services',
              style: TextStyle(
                fontSize: 21,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 3),
            const Text(
              'Leave, documents and support, in one place',
              style: TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            _serviceCard(
              icon: Icons.calendar_month_outlined,
              iconBackground: const Color(0xFFFFF1DE),
              iconColor: const Color(0xFFB87800),
              title: 'Leave',
              subtitle: 'Request time off, track\napprovals',
              trailing: '$_totalLeaveBalance left',
              onTap: _openLeave,
            ),
            const SizedBox(height: 10),
            _serviceCard(
              icon: Icons.home_work_outlined,
              iconBackground: const Color(0xFFE8F6EC),
              iconColor: AppColors.green,
              title: 'Work from home',
              subtitle: 'Request WFH and track approval',
              trailing: _wfhStatusLabel(),
              onTap: _openWfh,
            ),
            const SizedBox(height: 10),
            _serviceCard(
              icon: Icons.description_outlined,
              iconBackground: const Color(0xFFE9F0FF),
              iconColor: const Color(0xFF4A79D8),
              title: 'Documents',
              subtitle: 'Payslips, letters & certificates',
              onTap: _openDocuments,
            ),
            const SizedBox(height: 10),
            _serviceCard(
              icon: Icons.headset_mic_outlined,
              iconBackground: const Color(0xFFE8F6EC),
              iconColor: AppColors.green,
              title: 'Raise a ticket',
              subtitle: 'HR, IT, manager or leadership',
              onTap: _openTicket,
            ),
          ],
        ),
      ),
    );
  }

  String _wfhStatusLabel() {
    switch (_wfhStatusToday) {
      case 'approved':
        return 'Approved';
      case 'pending':
        return 'Pending';
      case 'rejected':
        return 'Rejected';
      default:
        return 'Request';
    }
  }

  Widget _serviceCard({
    required IconData icon,
    required Color iconBackground,
    required Color iconColor,
    required String title,
    required String subtitle,
    String? trailing,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          constraints: const BoxConstraints(minHeight: 70),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.divider),
            borderRadius: BorderRadius.circular(17),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 10.5,
                        height: 1.25,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.veryLightGreen,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    trailing,
                    style: const TextStyle(
                      fontSize: 9.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
