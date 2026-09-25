import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class SupportRequestScreen extends StatefulWidget {
  final String employeeId;
  final String employeeName;
  final VoidCallback? onBack;

  const SupportRequestScreen({
    super.key,
    required this.employeeId,
    required this.employeeName,
    this.onBack,
  });

  @override
  State<SupportRequestScreen> createState() => _SupportRequestScreenState();
}

class _SupportRequestScreenState extends State<SupportRequestScreen> {
  late final DatabaseReference _dbRef;
  String _department = 'HR';

  @override
  void initState() {
    super.initState();
    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
  }

  void _goBack() {
    if (widget.onBack != null) {
      widget.onBack!();
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _showNewTicketSheet() async {
    final subjectController = TextEditingController();
    final descriptionController = TextEditingController();
    var priority = 'Normal';
    var submitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      enableDrag: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

            Future<void> submit() async {
              if (submitting) return;
              final subject = subjectController.text.trim();
              final description = descriptionController.text.trim();

              if (subject.isEmpty || description.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Please enter a subject and description.'),
                  ),
                );
                return;
              }

              setSheetState(() => submitting = true);

              try {
                final ref = _dbRef
                    .child('HelpdeskRequests')
                    .child(widget.employeeId)
                    .push();

                await ref.set({
                  'employeeId': widget.employeeId,
                  'employeeName': widget.employeeName,
                  'department': _department,
                  'priority': priority.toLowerCase(),
                  'subject': subject,
                  'message': description,
                  'description': description,
                  'status': 'pending',
                  'createdAt': DateTime.now().toIso8601String(),
                });

                await NotificationCenter.sendAdmin(
                  title: 'New Helpdesk Ticket',
                  message:
                      '${widget.employeeName} raised a $_department ticket: $subject',
                );

                if (!sheetContext.mounted) return;
                Navigator.pop(sheetContext);

                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Ticket submitted successfully.')),
                );
              } catch (_) {
                if (!sheetContext.mounted) return;
                setSheetState(() => submitting = false);
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  const SnackBar(content: Text('Unable to submit the ticket.')),
                );
              }
            }

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(
                    top: Radius.circular(26),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
                          const Expanded(
                            child: Text(
                              'New ticket',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          _closeButton(() => Navigator.pop(sheetContext)),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Routing to: $_department team',
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Priority',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _priorityChip('Low', priority, (value) {
                            setSheetState(() => priority = value);
                          }),
                          const SizedBox(width: 6),
                          _priorityChip('Normal', priority, (value) {
                            setSheetState(() => priority = value);
                          }),
                          const SizedBox(width: 6),
                          _priorityChip('Urgent', priority, (value) {
                            setSheetState(() => priority = value);
                          }),
                        ],
                      ),
                      const SizedBox(height: 11),
                      _fieldLabel('Subject'),
                      const SizedBox(height: 5),
                      _textField(
                        controller: subjectController,
                        hint: 'e.g. Laptop battery draining fast',
                      ),
                      const SizedBox(height: 10),
                      _fieldLabel('Description'),
                      const SizedBox(height: 5),
                      _textField(
                        controller: descriptionController,
                        hint: 'Describe the issue in detail',
                        minLines: 3,
                        maxLines: 4,
                      ),
                      const SizedBox(height: 13),
                      SizedBox(
                        width: double.infinity,
                        height: 44,
                        child: ElevatedButton(
                          onPressed: submitting ? null : submit,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.green,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                          child: submitting
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Submit ticket',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    subjectController.dispose();
    descriptionController.dispose();
  }

  Widget _fieldLabel(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      );

  Widget _textField({
    required TextEditingController controller,
    required String hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 11.5, color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          fontSize: 11,
          color: AppColors.mutedText,
        ),
        filled: true,
        fillColor: AppColors.background,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 10,
        ),
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
      ),
    );
  }

  Widget _priorityChip(
    String label,
    String selected,
    ValueChanged<String> onSelected,
  ) {
    final active = selected == label;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(label),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? AppColors.veryLightGreen : AppColors.background,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: active ? AppColors.green : AppColors.divider,
              width: active ? 1.1 : .8,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: active ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _closeButton(VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(
        side: BorderSide(color: AppColors.divider),
      ),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: const SizedBox(
          width: 28,
          height: 28,
          child: Icon(Icons.close_rounded, size: 15),
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
            final horizontal = constraints.maxWidth >= 600 ? 28.0 : 20.0;
            final maxWidth = constraints.maxWidth >= 900 ? 720.0 : 520.0;

            return Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 13, horizontal, 0),
                      sliver: SliverToBoxAdapter(child: _header()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 16, horizontal, 0),
                      sliver: SliverToBoxAdapter(
                        child: const Text(
                          'Choose a department',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
                      sliver: SliverToBoxAdapter(child: _departments()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 18, horizontal, 0),
                      sliver: SliverToBoxAdapter(
                        child: const Text(
                          'Your tickets',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 0),
                      sliver: SliverToBoxAdapter(child: _tickets()),
                    ),
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 26),
                      sliver: SliverToBoxAdapter(
                        child: SizedBox(
                          height: 44,
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _showNewTicketSheet,
                            icon: const Icon(Icons.add_rounded, size: 17),
                            label: const Text(
                              'New ticket',
                              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
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

  Widget _header() {
    return Row(
      children: [
        _circleButton(Icons.chevron_left_rounded, _goBack),
        const SizedBox(width: 10),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Raise a ticket',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                'Get help from the right team',
                style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _circleButton(IconData icon, VoidCallback onTap) {
    return Material(
      color: AppColors.surface,
      shape: const CircleBorder(side: BorderSide(color: AppColors.divider)),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 34,
          height: 34,
          child: Icon(icon, size: 18, color: AppColors.textPrimary),
        ),
      ),
    );
  }

  Widget _departments() {
    const items = [
      _Department('HR', 'Policies, payroll, leave', Icons.person_outline, Color(0xFFE8F6EA), AppColors.green),
      _Department('IT Helpdesk', 'Devices, access, software', Icons.desktop_windows_outlined, Color(0xFFEAF1FF), Color(0xFF4C7EDB)),
      _Department('Managerial team', 'Your reporting manager', Icons.bar_chart_rounded, Color(0xFFFFF2DF), Color(0xFFB77816)),
      _Department('High table', 'Leadership escalation', Icons.edit_outlined, Color(0xFFF0E8FF), Color(0xFF8351C7)),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.36,
      ),
      itemBuilder: (_, index) {
        final item = items[index];
        final selected = _department == item.title;
        return InkWell(
          onTap: () => setState(() => _department = item.title),
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected ? AppColors.green : AppColors.divider,
                width: selected ? 1.1 : .8,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: item.iconBackground,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(item.icon, color: item.iconColor, size: 16),
                ),
                const Spacer(),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 8.5, height: 1.2, color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _tickets() {
    return StreamBuilder<DatabaseEvent>(
      stream: _dbRef.child('HelpdeskRequests').child(widget.employeeId).onValue,
      builder: (context, snapshot) {
        final items = <Map<dynamic, dynamic>>[];
        final raw = snapshot.data?.snapshot.value;
        if (raw is Map) {
          for (final entry in Map<dynamic, dynamic>.from(raw).entries) {
            if (entry.value is Map) {
              final data = Map<dynamic, dynamic>.from(entry.value as Map);
              data['_id'] = entry.key.toString();
              items.add(data);
            }
          }
        }

        items.sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));

        if (items.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: const Text(
              'Your submitted tickets and their current status will appear here.',
              style: TextStyle(fontSize: 10.5, color: AppColors.textSecondary),
            ),
          );
        }

        return Column(
          children: items.take(4).map((data) {
            final status = data['status']?.toString() ?? 'pending';
            final createdAt = DateTime.tryParse(data['createdAt']?.toString() ?? '');
            final date = createdAt == null ? '' : '${createdAt.day} ${_month(createdAt.month)}';
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['subject']?.toString() ?? 'Support ticket',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${data['department'] ?? 'Support'}${date.isEmpty ? '' : ' · $date'}',
                          style: const TextStyle(fontSize: 8.5, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  _statusPill(status),
                ],
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _statusPill(String raw) {
    final status = raw.toLowerCase();
    final isResolved = status == 'resolved' || status == 'closed' || status == 'completed';
    final isOpen = status == 'open' || status == 'in progress' || status == 'processing';
    final color = isResolved ? AppColors.success : isOpen ? AppColors.info : AppColors.warning;
    final bg = isResolved ? AppColors.successLight : isOpen ? AppColors.infoLight : AppColors.warningLight;
    final label = isResolved ? 'Resolved' : isOpen ? 'Open' : 'Pending';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label, style: TextStyle(fontSize: 8, fontWeight: FontWeight.w800, color: color)),
    );
  }

  String _month(int month) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return months[month - 1];
  }
}

class _Department {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color iconBackground;
  final Color iconColor;

  const _Department(this.title, this.subtitle, this.icon, this.iconBackground, this.iconColor);
}
