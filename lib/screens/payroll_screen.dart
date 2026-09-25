import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';

import '../utils/app_colors.dart';
import 'payslip_request_bottom_sheet.dart';

/// Employee Payroll
///
/// Payroll is read-only for employees.
/// The payroll values are expected to be written/updated by the
/// administration workflow at:
///
/// Payroll/{employeeId}/{yyyy-MM}
///
/// Supported payroll fields:
/// basicSalary, grossSalary, deductions, lopDays, lopDeduction,
/// netSalary, processingStatus, paymentStatus
///
/// Leave information is read from the same sources used by the employee
/// Leave screen:
/// LeaveBalances/{employeeId}/{year}
///
/// Earned leave/comp-off is read from:
/// CompOffBalances/{employeeId}/availableDays
///
/// Optional unpaid/LOP fields may be supplied by the admin payroll workflow
/// as unpaidLeaveDays, unpaidDays, lopDays or unpaidLeave.
class PayrollScreen extends StatefulWidget {
  final String employeeId;

  const PayrollScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  late DatabaseReference _dbRef;

  bool _loading = true;
  int _selectedYear = DateTime.now().year;
  int _selectedMonth = DateTime.now().month;

  Map<String, dynamic> _currentPayroll = <String, dynamic>{};
  List<_PayrollRecord> _history = <_PayrollRecord>[];

  int _casualLeave = 0;
  int _sickLeave = 0;
  int _earnedLeave = 0;
  int _unpaidLeave = 0;

  @override
  void initState() {
    super.initState();

    _dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadAll();
  }

  String get _monthKey =>
      '${_selectedYear.toString().padLeft(4, '0')}-'
      '${_selectedMonth.toString().padLeft(2, '0')}';

  String get _monthLabel =>
      DateFormat('MMMM yyyy').format(
        DateTime(_selectedYear, _selectedMonth, 1),
      );

  Future<void> _loadAll() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
    });

    // Each Firebase section handles its own missing/restricted data.
    // One unavailable node must not make the whole Payroll screen fail.
    await Future.wait<void>([
      _loadSelectedPayroll(),
      _loadPayrollHistory(),
      _loadLeaveInformation(),
    ]);

    if (!mounted) return;

    setState(() {
      _loading = false;
    });
  }

  Future<void> _loadSelectedPayroll() async {
    try {
      final snapshot = await _dbRef
          .child('Payroll')
          .child(widget.employeeId)
          .child(_monthKey)
          .get();

      if (!snapshot.exists || snapshot.value is! Map) {
        _currentPayroll = <String, dynamic>{};
        return;
      }

      _currentPayroll = _map(snapshot.value);
    } catch (_) {
      // Payroll has not been published or is not readable yet.
      _currentPayroll = <String, dynamic>{};
    }
  }

  Future<void> _loadPayrollHistory() async {
    try {
      final snapshot = await _dbRef
          .child('Payroll')
          .child(widget.employeeId)
          .get();

      final records = <_PayrollRecord>[];

      if (snapshot.exists && snapshot.value is Map) {
        final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);

        for (final entry in raw.entries) {
          if (entry.value is! Map) continue;

          final key = entry.key.toString();
          final data = _map(entry.value);

          final parsed = _parseMonthKey(key, data);
          if (parsed == null) continue;

          records.add(
            _PayrollRecord(
              year: parsed.year,
              month: parsed.month,
              data: data,
            ),
          );
        }
      }

      records.sort((a, b) {
        final aDate = DateTime(a.year, a.month);
        final bDate = DateTime(b.year, b.month);
        return bDate.compareTo(aDate);
      });

      _history = records;
    } catch (_) {
      _history = <_PayrollRecord>[];
    }
  }

  Future<void> _loadLeaveInformation() async {
    var casual = 0;
    var medical = 0;
    var earned = 0;
    var unpaid = 0;

    try {
      // Exactly the same balance source used by LeaveScreen.
      final leaveSnapshot = await _dbRef
          .child('LeaveBalances')
          .child(widget.employeeId)
          .child(_selectedYear.toString())
          .get();

      if (leaveSnapshot.exists && leaveSnapshot.value is Map) {
        final data = _map(leaveSnapshot.value);

        casual = _int(
          data['casual'],
          fallback: data['casualLeave'],
        );

        medical = _int(
          data['medical'],
          fallback: data['medicalLeave'],
        );
      }
    } catch (_) {
      // Keep zero if the leave balance node is unavailable.
    }

    try {
      // Approved overtime comp-off is the source of Earned Leave.
      final compOffSnapshot = await _dbRef
          .child('CompOffBalances')
          .child(widget.employeeId)
          .get();

      if (compOffSnapshot.exists && compOffSnapshot.value is Map) {
        final data = _map(compOffSnapshot.value);

        earned = _int(
          data['availableDays'],
          fallback: _int(
            data['grantedDays'],
            fallback: 0,
          ) -
              _int(
                data['usedDays'],
                fallback: 0,
              ),
        );

        if (earned < 0) earned = 0;
      }
    } catch (_) {
      earned = 0;
    }

    // Unpaid leave is leave taken after normal leave balances are exhausted.
    // Prefer the admin payroll value for the selected month.
    unpaid = _int(
      _currentPayroll['unpaidLeaveDays'],
      fallback: _int(
        _currentPayroll['unpaidDays'],
        fallback: _int(
          _currentPayroll['unpaidLeave'],
          fallback: _int(
            _currentPayroll['lopDays'],
            fallback: 0,
          ),
        ),
      ),
    );

    try {
      final unpaidSnapshot = await _dbRef
          .child('UnpaidLeave')
          .child(widget.employeeId)
          .child(_monthKey)
          .get();

      if (unpaidSnapshot.exists) {
        if (unpaidSnapshot.value is Map) {
          final data = _map(unpaidSnapshot.value);
          unpaid = _int(
            data['days'],
            fallback: _int(
              data['unpaidDays'],
              fallback: unpaid,
            ),
          );
        } else {
          unpaid = _toInt(unpaidSnapshot.value);
        }
      }
    } catch (_) {
      // Keep the admin payroll/LOP value if UnpaidLeave is not available.
    }

    _casualLeave = casual;
    _sickLeave = medical;
    _earnedLeave = earned;
    _unpaidLeave = unpaid < 0 ? 0 : unpaid;
  }

  DateTime? _parseMonthKey(
    String key,
    Map<String, dynamic> data,
  ) {
    final match = RegExp(r'^(\d{4})-(\d{1,2})$').firstMatch(key);

    if (match != null) {
      final year = int.tryParse(match.group(1)!);
      final month = int.tryParse(match.group(2)!);

      if (year != null && month != null && month >= 1 && month <= 12) {
        return DateTime(year, month, 1);
      }
    }

    final year = _int(
      data['year'],
      fallback: 0,
    );

    final month = _int(
      data['month'],
      fallback: 0,
    );

    if (year > 0 && month >= 1 && month <= 12) {
      return DateTime(year, month, 1);
    }

    return null;
  }

  void _showMonthPicker() {
    final months = <DateTime>[];

    final now = DateTime.now();

    for (var i = 0; i < 12; i++) {
      months.add(
        DateTime(
          now.year,
          now.month - i,
          1,
        ),
      );
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(26),
        ),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(
              18,
              12,
              18,
              20,
            ),
            itemCount: months.length,
            separatorBuilder: (_, _) => const Divider(
              height: 1,
              color: AppColors.divider,
            ),
            itemBuilder: (_, index) {
              final month = months[index];

              final selected =
                  month.year == _selectedYear &&
                  month.month == _selectedMonth;

              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: .10)
                        : AppColors.background,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    Icons.calendar_month_outlined,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                    size: 19,
                  ),
                ),
                title: Text(
                  DateFormat('MMMM yyyy').format(month),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight:
                        selected ? FontWeight.w900 : FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                trailing: selected
                    ? const Icon(
                        Icons.check_circle_rounded,
                        color: AppColors.primary,
                      )
                    : null,
                onTap: () {
                  setState(() {
                    _selectedYear = month.year;
                    _selectedMonth = month.month;
                  });

                  Navigator.of(sheetContext).pop();
                  _loadAll();
                },
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _requestPayslip() async {
    final name = await _employeeName();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(.45),
      enableDrag: true,
      builder: (_) => PayslipRequestBottomSheet(
        employeeId: widget.employeeId,
        employeeName: name,
      ),
    );
  }

  Future<String> _employeeName() async {
    try {
      final snapshot = await _dbRef
          .child('users')
          .child(widget.employeeId)
          .get();

      if (snapshot.exists && snapshot.value is Map) {
        final data = _map(snapshot.value);

        final name = data['name']?.toString().trim();

        if (name != null && name.isNotEmpty) {
          return name;
        }
      }
    } catch (_) {}

    return widget.employeeId;
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is Map) {
      return Map<String, dynamic>.from(
        value.map(
          (key, value) => MapEntry(
            key.toString(),
            value,
          ),
        ),
      );
    }

    return <String, dynamic>{};
  }

  int _int(
    dynamic value, {
    dynamic fallback,
  }) {
    if (value == null) {
      return _toInt(fallback);
    }

    return _toInt(value);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;

    if (value is double) {
      return value.round();
    }

    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(
          value?.toString() ?? '',
        ) ??
        0;
  }

  double _double(
    dynamic value, {
    dynamic fallback,
  }) {
    if (value == null) {
      return _toDouble(fallback);
    }

    return _toDouble(value);
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();

    return double.tryParse(
          value?.toString().replaceAll(',', '') ?? '',
        ) ??
        0;
  }

  String _money(dynamic value) {
    final amount = _double(value);

    if (amount == 0) return '₹0';

    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt()}';
    }

    return '₹${amount.toStringAsFixed(2)}';
  }

  String _statusText(
    dynamic value, {
    String fallback = 'Not available',
  }) {
    final text = value?.toString().trim();

    if (text == null || text.isEmpty) return fallback;

    return text
        .split(RegExp(r'[\s_-]+'))
        .where((part) => part.isNotEmpty)
        .map(
          (part) =>
              '${part[0].toUpperCase()}${part.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  Color _paymentColor(String value) {
    final lower = value.toLowerCase();

    if (lower == 'paid' || lower == 'ready') {
      return AppColors.success;
    }

    if (lower == 'rejected') {
      return AppColors.danger;
    }

    return AppColors.warning;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: AppColors.textPrimary,
          ),
        ),
        titleSpacing: 0,
        title: const Text(
          'Payroll',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w900,
            color: AppColors.textPrimary,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: _monthButton(),
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                color: AppColors.primary,
              ),
            )
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _loadAll,
              child: Stack(
                children: [
                  const _BackgroundDecor(),
                  ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      28,
                    ),
                    children: [
                      _buildIntro(),
                      const SizedBox(height: 12),
                      _buildPayrollOverview(),
                      _buildLeaveSummary(),
                      _buildMyPayroll(),
                      _buildPayrollHistory(),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _monthButton() {
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: _showMonthPicker,
        borderRadius: BorderRadius.circular(13),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: AppColors.divider,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.calendar_month_outlined,
                size: 17,
                color: AppColors.primary,
              ),
              const SizedBox(width: 6),
              Text(
                _monthLabel,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w900,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIntro() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your salary & payroll',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildPayrollOverview() {
    final gross = _currentPayroll['grossSalary'];
    final deductions = _currentPayroll['deductions'];
    final net = _currentPayroll['netSalary'];
    final lopDeduction = _currentPayroll['lopDeduction'];

    final paymentStatus = _statusText(
      _currentPayroll['paymentStatus'],
      fallback: 'Not available',
    );

    return _sectionCard(
      title: 'Payroll Overview',
      subtitle: '$_monthLabel payroll summary',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.account_balance_wallet_outlined,
                  title: 'Gross Salary',
                  value: _money(gross),
                  caption: 'Total earnings',
                  background: AppColors.successLight,
                  iconBackground: AppColors.successLight,
                  iconColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _overviewCard(
                  icon: Icons.remove_circle_outline_rounded,
                  title: 'Deductions',
                  value: _money(deductions),
                  caption: 'PF, tax & other',
                  background: AppColors.dangerLight,
                  iconBackground: AppColors.dangerLight,
                  iconColor: AppColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Expanded(
                child: _overviewCard(
                  icon: Icons.payments_outlined,
                  title: 'Net Salary',
                  value: _money(net),
                  caption: paymentStatus,
                  background: AppColors.successLight,
                  iconBackground: AppColors.successLight,
                  iconColor: AppColors.primary,
                  valueColor: AppColors.primary,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: _overviewCard(
                  icon: Icons.event_busy_outlined,
                  title: 'LOP Deduction',
                  value: _money(lopDeduction),
                  caption: '${_int(_currentPayroll['lopDays'])} LOP day(s)',
                  background: AppColors.warningLight,
                  iconBackground: AppColors.warningLight,
                  iconColor: AppColors.warning,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveSummary() {
    return _sectionCard(
      title: 'Leave & LOP Summary',
      subtitle: 'Leave impact on $_monthLabel payroll',
      child: Row(
        children: [
          Expanded(
            child: _leaveMetric(
              icon: Icons.event_available_outlined,
              title: 'Casual Leave',
              value: _casualLeave,
              caption: 'Available',
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _leaveMetric(
              icon: Icons.workspace_premium_outlined,
              title: 'Earned Leave',
              value: _earnedLeave,
              caption: 'Comp-off',
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _leaveMetric(
              icon: Icons.medical_services_outlined,
              title: 'Sick Leave',
              value: _sickLeave,
              caption: 'Available',
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: _leaveMetric(
              icon: Icons.warning_amber_rounded,
              title: 'Unpaid Leave',
              value: _unpaidLeave,
              caption: 'Affected',
              valueColor: _unpaidLeave > 0
                  ? AppColors.warning
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMyPayroll() {
    final basic = _currentPayroll['basicSalary'];
    final gross = _currentPayroll['grossSalary'];
    final deductions = _currentPayroll['deductions'];
    final net = _currentPayroll['netSalary'];

    final lopDays = _int(
      _currentPayroll['lopDays'],
      fallback: _unpaidLeave,
    );

    final lopDeduction = _currentPayroll['lopDeduction'];

    final processing = _statusText(
      _currentPayroll['processingStatus'],
      fallback: 'Not processed',
    );

    final payment = _statusText(
      _currentPayroll['paymentStatus'],
      fallback: 'Payment pending',
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(
        14,
        15,
        14,
        14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: .18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'My Payroll — $_monthLabel',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          const Text(
            'Salary, deductions, LOP and payment status',
            style: TextStyle(
              fontSize: 9.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 13),
          _detailRow(
            'Basic Salary',
            _money(basic),
          ),
          _detailRow(
            'Gross Salary',
            _money(gross),
          ),
          _detailRow(
            'LOP',
            '$lopDays day(s) • ${_money(lopDeduction)}',
          ),
          _detailRow(
            'Deductions',
            _money(deductions),
          ),
          const Divider(
            height: 22,
            color: AppColors.divider,
          ),
          _detailRow(
            'Net Salary',
            _money(net),
            emphasize: true,
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 6,
            children: [
              _statusChip(
                processing,
                positive: processing.toLowerCase() == 'processed',
              ),
              _statusChip(
                payment,
                positive: payment.toLowerCase() == 'paid' ||
                    payment.toLowerCase() == 'ready',
              ),
            ],
          ),
          const SizedBox(height: 13),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _requestPayslip,
              icon: const Icon(
                Icons.receipt_long_outlined,
                size: 19,
              ),
              label: const Text(
                'Request Payslip',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayrollHistory() {
    final visibleHistory = _history
        .where(
          (record) =>
              !(record.year == _selectedYear &&
                  record.month == _selectedMonth),
        )
        .toList();

    return _sectionCard(
      title: 'Payroll History',
      subtitle: 'Previously processed payroll records',
      child: visibleHistory.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'No previous payroll records available.',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.textSecondary,
                ),
              ),
            )
          : Column(
              children: visibleHistory.map((record) {
                final payment = _statusText(
                  record.data['paymentStatus'],
                  fallback: 'Pending',
                );

                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _historyTile(
                    record,
                    payment,
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _historyTile(
    _PayrollRecord record,
    String payment,
  ) {
    final net = record.data['netSalary'];

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedYear = record.year;
            _selectedMonth = record.month;
          });

          _loadAll();
        },
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: AppColors.divider,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.payments_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat(
                        'MMMM yyyy',
                      ).format(
                        DateTime(
                          record.year,
                          record.month,
                        ),
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w900,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Net salary: ${_money(net)}',
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              _statusChip(
                payment,
                positive: payment.toLowerCase() == 'paid' ||
                    payment.toLowerCase() == 'ready',
              ),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.mutedText,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(
        14,
        14,
        14,
        14,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(
          color: AppColors.divider,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 9,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _overviewCard({
    required IconData icon,
    required String title,
    required String value,
    required String caption,
    required Color background,
    required Color iconBackground,
    required Color iconColor,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: iconBackground,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 16,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 7.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _leaveMetric({
    required IconData icon,
    required String title,
    required int value,
    required String caption,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        5,
        10,
        5,
        9,
      ),
      decoration: BoxDecoration(
        color: AppColors.successLight,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 17,
            color: AppColors.primary,
          ),
          const SizedBox(height: 5),
          Text(
            title,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 7.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
          Text(
            caption,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 7,
              color: AppColors.mutedText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: emphasize ? 10.5 : 9.5,
                fontWeight:
                    emphasize ? FontWeight.w800 : FontWeight.w600,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: emphasize ? 16 : 10.5,
              fontWeight: FontWeight.w900,
              color: emphasize
                  ? AppColors.primary
                  : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusChip(
    String text, {
    required bool positive,
  }) {
    final color = _paymentColor(text);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 9,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
    );
  }
}

class _PayrollRecord {
  final int year;
  final int month;
  final Map<String, dynamic> data;

  const _PayrollRecord({
    required this.year,
    required this.month,
    required this.data,
  });
}

class _BackgroundDecor extends StatelessWidget {
  const _BackgroundDecor();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -45,
            right: -45,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: .045),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Positioned(
            top: 55,
            right: 20,
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.green.withValues(alpha: .035),
                shape: BoxShape.circle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
