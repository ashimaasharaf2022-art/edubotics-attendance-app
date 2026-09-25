import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/notification_center.dart';

import '../utils/app_colors.dart';
import 'relieving_letter_bottom_sheet.dart';
import 'experience_letter_bottom_sheet.dart';
import 'onboarding_letter_bottom_sheet.dart';
import 'payslip_request_bottom_sheet.dart';

class DocumentsScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onBack;

  const DocumentsScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onBack,
  });

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen> {
  late final DatabaseReference _dbRef;

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: 'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
  }
  final List<_DocumentItem> _documents = const [
    _DocumentItem(
      icon: Icons.receipt_long_rounded,
      title: 'Salary slip',
      subtitle: 'Pick a month to download',
      iconBackground: Color(0xFFE6F6EA),
      iconColor: Color(0xFF16965A),
      type: _DocumentType.salarySlip,
    ),
    _DocumentItem(
      icon: Icons.badge_outlined,
      title: 'Relieving letter',
      subtitle: 'For your last working day',
      iconBackground: Color(0xFFEAF1FF),
      iconColor: Color(0xFF4C7EDB),
      type: _DocumentType.relieving,
    ),
    _DocumentItem(
      icon: Icons.workspace_premium_outlined,
      title: 'Experience letter',
      subtitle: 'Verified record of tenure & role',
      iconBackground: Color(0xFFF0E8FF),
      iconColor: Color(0xFF8351C7),
      type: _DocumentType.experience,
    ),
    _DocumentItem(
      icon: Icons.emoji_people_outlined,
      title: 'Onboarding letter',
      subtitle: 'Confirmation of joining details',
      iconBackground: Color(0xFFFFF2DF),
      iconColor: Color(0xFFB77816),
      type: _DocumentType.onboarding,
    ),
    _DocumentItem(
      icon: Icons.add_rounded,
      title: 'Something else',
      subtitle: 'Request any other document',
      iconBackground: Colors.transparent,
      iconColor: AppColors.textSecondary,
      type: _DocumentType.other,
      dashed: true,
    ),
  ];

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _openDocument(_DocumentItem item) {
    switch (item.type) {
      case _DocumentType.salarySlip:
        _showSalarySlipRequest();
        return;
      case _DocumentType.relieving:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: .45),
          enableDrag: true,
          builder: (_) => RelievingLetterBottomSheet(
            employeeId: widget.employeeId,
            employeeName: widget.employeeName,
          ),
        );
        return;
      case _DocumentType.experience:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: .45),
          enableDrag: true,
          builder: (_) => ExperienceLetterBottomSheet(
            employeeId: widget.employeeId,
            employeeName: widget.employeeName,
          ),
        );
        return;
      case _DocumentType.onboarding:
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.black.withValues(alpha: .45),
          enableDrag: true,
          builder: (_) => OnboardingLetterBottomSheet(
            employeeId: widget.employeeId,
            employeeName: widget.employeeName,
          ),
        );
        return;
      case _DocumentType.other:
        _showOtherDocumentRequest();
        return;
    }
  }

  Future<void> _showSalarySlipRequest() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      enableDrag: true,
      builder: (_) => PayslipRequestBottomSheet(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
      ),
    );
  }

  Future<void> _showOtherDocumentRequest() async {
    final nameController = TextEditingController();
    final purposeController = TextEditingController();
    var submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              if (submitting) return;
              final name = nameController.text.trim();
              final purpose = purposeController.text.trim();
              if (name.isEmpty || purpose.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please complete both fields.')),
                );
                return;
              }

              setSheetState(() => submitting = true);
              try {
                // Create one unique request record for the admin workflow.
                final requestRef = _dbRef
                    .child('DocumentRequests')
                    .child(widget.employeeId)
                    .push();

                final requestedAt = DateTime.now().toIso8601String();

                await requestRef.set({
                  'requestId': requestRef.key,
                  'employeeId': widget.employeeId,
                  'employeeName': widget.employeeName,
                  'documentType': name,
                  'description': purpose,
                  'status': 'pending',
                  'requestedAt': requestedAt,
                });

                // The Firebase record is the actual request.
                // Notification is only an additional admin alert, so a
                // notification failure must not make the request fail.
                try {
                  await NotificationCenter.sendAdmin(
                    title: 'Document Request',
                    message: '${widget.employeeName} requested $name.',
                  );
                } catch (_) {
                  // Request was already saved successfully.
                }

                if (!sheetContext.mounted) return;

                Navigator.pop(sheetContext);

                if (!mounted) return;

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Document request sent to admin.'),
                  ),
                );
              } catch (_) {
                if (!sheetContext.mounted) return;

                setSheetState(() => submitting = false);

                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(
                    content: Text('Could not submit document request.'),
                  ),
                );
              }
            }

            return _requestSheetContainer(
              context: context,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _sheetHeader(
                    context,
                    title: 'Request something else',
                    subtitle: 'Tell HR what document you need.',
                  ),
                  const SizedBox(height: 14),
                  const Text('Document name', style: _sheetLabelStyle),
                  const SizedBox(height: 5),
                  TextField(
                    controller: nameController,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: _sheetInputDecoration(
                      hintText: 'e.g. Address proof letter',
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text('Purpose', style: _sheetLabelStyle),
                  const SizedBox(height: 5),
                  TextField(
                    controller: purposeController,
                    minLines: 2,
                    maxLines: 3,
                    style: const TextStyle(fontSize: 11.5),
                    decoration: _sheetInputDecoration(
                      hintText: 'Any extra detail HR should know',
                    ),
                  ),
                  const SizedBox(height: 13),
                  _submitButton(
                    label: 'Submit request',
                    loading: submitting,
                    onPressed: submit,
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameController.dispose();
    purposeController.dispose();
  }

  Widget _requestSheetContainer({
    required BuildContext context,
    required Widget child,
  }) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: inset),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 9, 16, 18),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: SingleChildScrollView(child: child),
      ),
    );
  }

  Widget _sheetHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: Container(
            width: 30,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.divider,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            Material(
              color: AppColors.surface,
              shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
              child: InkWell(
                onTap: () => Navigator.pop(context),
                customBorder: const CircleBorder(),
                child: const SizedBox(
                  width: 28,
                  height: 28,
                  child: Icon(Icons.close_rounded, size: 15),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  static const _sheetLabelStyle = TextStyle(
    fontSize: 10.5,
    fontWeight: FontWeight.w700,
    color: AppColors.textSecondary,
  );

  InputDecoration _sheetInputDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(fontSize: 11, color: AppColors.mutedText),
      filled: true,
      fillColor: AppColors.background,
      contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.divider),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: const BorderSide(color: AppColors.green, width: 1.2),
      ),
    );
  }

  Widget _submitButton({
    required String label,
    required bool loading,
    required VoidCallback onPressed,
  }) {
    return SizedBox(
      width: double.infinity,
      height: 44,
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.green,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: loading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
            : Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontalPadding = constraints.maxWidth >= 600 ? 28.0 : 24.0;
            final maxContentWidth = constraints.maxWidth >= 900 ? 720.0 : 520.0;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxContentWidth),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        12,
                        horizontalPadding,
                        0,
                      ),
                      sliver: SliverToBoxAdapter(child: _buildHeader()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        16,
                        horizontalPadding,
                        0,
                      ),
                      sliver: SliverList.separated(
                        itemCount: _documents.length,
                        itemBuilder: (context, index) {
                          final item = _documents[index];
                          return _DocumentCard(
                            item: item,
                            onTap: () => _openDocument(item),
                          );
                        },
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: 9),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        horizontalPadding,
                        17,
                        horizontalPadding,
                        24,
                      ),
                      sliver: SliverToBoxAdapter(
                        child: _buildRecentRequests(),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _roundIconButton(
          icon: Icons.chevron_left_rounded,
          onTap: _goBack,
        ),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Documents',
                style: TextStyle(
                  fontSize: 20,
                  height: 1.05,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Request letters & certificates',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(
            icon,
            size: 19,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentRequests() {
    return StreamBuilder<DatabaseEvent>(
      stream: _dbRef.child('DocumentRequests').child(widget.employeeId).onValue,
      builder: (context, documentSnapshot) {
        return StreamBuilder<DatabaseEvent>(
          stream: _dbRef.child('PayslipRequests').child(widget.employeeId).onValue,
          builder: (context, payslipSnapshot) {
            final requests = <_RecentRequestData>[];

            final documentValue = documentSnapshot.data?.snapshot.value;
            if (documentValue is Map) {
              for (final entry in Map<dynamic, dynamic>.from(documentValue).entries) {
                if (entry.value is! Map) continue;
                final data = Map<dynamic, dynamic>.from(entry.value as Map);
                requests.add(_RecentRequestData(
                  title: data['documentType']?.toString() ?? 'Document request',
                  requestedAt: data['requestedAt']?.toString(),
                  status: data['status']?.toString() ?? 'pending',
                ));
              }
            }

            final payslipValue = payslipSnapshot.data?.snapshot.value;
            if (payslipValue is Map) {
              for (final entry in Map<dynamic, dynamic>.from(payslipValue).entries) {
                if (entry.value is! Map) continue;
                final data = Map<dynamic, dynamic>.from(entry.value as Map);
                requests.add(_RecentRequestData(
                  title: 'Salary slip — ${data['monthLabel']?.toString() ?? data['month']?.toString() ?? 'Request'}',
                  requestedAt: data['requestedAt']?.toString(),
                  status: data['status']?.toString() ?? 'pending',
                ));
              }
            }

            requests.sort((a, b) => (b.requestedAt ?? '').compareTo(a.requestedAt ?? ''));
            final recent = requests.take(5).toList();

            if (recent.isEmpty) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text(
                    'Recent requests',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  SizedBox(height: 7),
                  Text(
                    'Your document requests and their current status will appear here.',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent requests',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 7),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Column(
                    children: [
                      for (var i = 0; i < recent.length; i++) ...[
                        _RecentRequestRow.fromData(recent[i]),
                        if (i != recent.length - 1) const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _RecentRequestData {
  final String title;
  final String? requestedAt;
  final String status;

  const _RecentRequestData({
    required this.title,
    required this.requestedAt,
    required this.status,
  });
}

class _RecentRequestRow extends StatelessWidget {
  final Color dotColor;
  final String title;
  final String subtitle;
  final String status;
  final Color statusBackground;
  final Color statusColor;

  const _RecentRequestRow({
    required this.dotColor,
    required this.title,
    required this.subtitle,
    required this.status,
    required this.statusBackground,
    required this.statusColor,
  });

  factory _RecentRequestRow.fromData(_RecentRequestData data) {
    final normalized = data.status.toLowerCase();
    final isReady = normalized == 'ready' || normalized == 'approved' || normalized == 'completed';
    final isRejected = normalized == 'rejected' || normalized == 'declined';
    final isProgress = normalized == 'in progress' || normalized == 'processing' || normalized == 'reviewing';

    final status = isReady
        ? 'Ready'
        : isRejected
            ? 'Rejected'
            : isProgress
                ? 'In progress'
                : 'Pending';

    final dotColor = isReady
        ? AppColors.success
        : isRejected
            ? AppColors.danger
            : isProgress
                ? AppColors.info
                : AppColors.warning;

    final statusBackground = isReady
        ? AppColors.successLight
        : isRejected
            ? AppColors.dangerLight
            : isProgress
                ? AppColors.infoLight
                : AppColors.warningLight;

    final statusColor = isReady
        ? AppColors.success
        : isRejected
            ? AppColors.danger
            : isProgress
                ? AppColors.info
                : AppColors.warning;

    return _RecentRequestRow(
      dotColor: dotColor,
      title: data.title,
      subtitle: _formatRequestedDate(data.requestedAt),
      status: status,
      statusBackground: statusBackground,
      statusColor: statusColor,
    );
  }

  static String _formatRequestedDate(String? value) {
    if (value == null || value.isEmpty) return 'Request date unavailable';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return 'Requested recently';
    return 'Requested ${DateFormat('d MMM').format(parsed.toLocal())}';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: dotColor,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 9,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
          decoration: BoxDecoration(
            color: statusBackground,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            status,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: statusColor,
            ),
          ),
        ),
      ],
    );
  }
}

enum _DocumentType {
  salarySlip,
  relieving,
  experience,
  onboarding,
  other,
}

class _DocumentItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color iconBackground;
  final Color iconColor;
  final _DocumentType type;
  final bool dashed;

  const _DocumentItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.iconBackground,
    required this.iconColor,
    required this.type,
    this.dashed = false,
  });
}

class _DocumentCard extends StatelessWidget {
  final _DocumentItem item;
  final VoidCallback onTap;

  const _DocumentCard({
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          height: 57,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: item.iconBackground,
                  borderRadius: BorderRadius.circular(10),
                  border: item.dashed
                      ? Border.all(
                          color: AppColors.mutedText,
                          width: 1,
                        )
                      : null,
                ),
                child: Icon(
                  item.icon,
                  size: 17,
                  color: item.iconColor,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
