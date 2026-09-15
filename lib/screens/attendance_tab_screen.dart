import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/attendance_calculator.dart';
import '../widgets/punch_card.dart';

class AttendanceTabScreen extends StatefulWidget {
  final String employeeId;

  const AttendanceTabScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<AttendanceTabScreen> createState() =>
      _AttendanceTabScreenState();
}

class _AttendanceTabScreenState
    extends State<AttendanceTabScreen> {
  late DatabaseReference dbRef;

  bool showList = false;
  bool loading = true;

  Map<dynamic, dynamic> attendanceData = {};

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    _checkPreviousDayForMisPunch()
        .then((_) => _loadHistory());
  }

  // ============================================================
  // DATE KEY
  // ============================================================

  String _dateKey(DateTime date) {
    return "${date.year}-"
        "${date.month.toString().padLeft(2, '0')}-"
        "${date.day.toString().padLeft(2, '0')}";
  }

  bool _isToday(String dateKey) {
    return dateKey == _dateKey(DateTime.now());
  }

  // ============================================================
  // NEXT-DAY MIS-PUNCH DETECTION
  // ============================================================
  //
  // No Firebase Scheduled Function is used.
  //
  // When the employee opens the app, previous open
  // Checked In records are checked.
  //
  // If a previous record has:
  //   - Checked In status
  //   - punchIn
  //   - no punchOut
  //
  // it becomes:
  //   MIS-PUNCH
  //
  // IMPORTANT:
  // We DO NOT write punchOut = 11:59 PM.
  //
  // Instead, 11:59 PM is stored only as
  // temporaryPunchOut for display/workflow purposes.
  //
  // The actual working hours remain uncalculated until
  // an admin selects the real punch-out time.
  // ============================================================

  Future<void> _checkPreviousDayForMisPunch() async {
    try {
      final attendanceRef =
          dbRef.child("Attendance").child(widget.employeeId);

      final snapshot = await attendanceRef.get();

      if (!snapshot.exists || snapshot.value is! Map) {
        return;
      }

      final records =
          Map<dynamic, dynamic>.from(snapshot.value as Map);

      final todayKey = _dateKey(DateTime.now());

      for (final entry in records.entries) {
        final dateKey = entry.key.toString();

        // Never modify today's currently active attendance.
        if (dateKey == todayKey) {
          continue;
        }

        final rawRecord = entry.value;

        if (rawRecord is! Map) {
          continue;
        }

        final record =
            Map<dynamic, dynamic>.from(rawRecord);

        final status =
            record["status"]?.toString().toUpperCase();

        // Only an unfinished Checked In record can become MIS-PUNCH.
        if (status != "CHECKED IN") {
          continue;
        }

        final punchIn =
            record["punchIn"]?.toString();

        if (punchIn == null ||
            punchIn.trim().isEmpty) {
          continue;
        }

        final punchOut =
            record["punchOut"]?.toString();

        // Already has a real punch-out.
        if (punchOut != null &&
            punchOut.trim().isNotEmpty) {
          continue;
        }

        // Check sessions too.
        final sessions =
            _sessionsFromRecord(record);

        if (sessions.isEmpty) {
          continue;
        }

        final lastSession = sessions.last;

        final lastPunchOut =
            lastSession.punchOut?.trim();

        if (lastPunchOut != null &&
            lastPunchOut.isNotEmpty) {
          continue;
        }

        final dateRef =
            attendanceRef.child(dateKey);

        // Convert the unfinished record into a temporary
        // MIS-PUNCH workflow state.
        //
        // NO actual punchOut is written.
        await dateRef.update({
          "status": "MIS-PUNCH",
          "misPunch": true,
          "temporaryPunchOut":
              AttendanceCalculator.autoCheckoutTime,
          "misPunchDetectedAt":
              DateTime.now().toIso8601String(),
          "punchoutRequestStatus": "not_requested",
          "attendanceStatus":
              "MIS-PUNCH — awaiting admin correction",
        });

        // Do not create a PunchRequests entry automatically.
        // The employee must open the MIS-PUNCH record and explicitly
        // choose the existing "Send request to admin" workflow.
      }
    } catch (_) {
      // Do not prevent the Attendance screen from opening
      // if the MIS-PUNCH check fails.
    }
  }

  // ============================================================
  // LOAD ATTENDANCE HISTORY
  // ============================================================

  Future<void> _loadHistory() async {
    if (mounted) {
      setState(() => loading = true);
    }

    try {
      final snapshot = await dbRef
          .child("Attendance")
          .child(widget.employeeId)
          .get();

      if (snapshot.exists &&
          snapshot.value is Map) {
        attendanceData =
            Map<dynamic, dynamic>.from(
          snapshot.value as Map,
        );
      } else {
        attendanceData = {};
      }
    } catch (_) {
      attendanceData = {};
    }

    if (!mounted) return;

    setState(() => loading = false);
  }

  // ============================================================
  // SESSION EXTRACTION
  // ============================================================

  List<AttendanceSession> _sessionsFromRecord(
    Map data,
  ) {
    final sessions =
        <AttendanceSession>[];

    final raw =
        data["sessions"];

    // Newer records may store sessions as a List.
    if (raw is List) {
      for (final item in raw) {
        if (item is Map &&
            item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn:
                  item["punchIn"].toString(),
              punchOut:
                  item["punchOut"]?.toString(),
            ),
          );
        }
      }
    }

    // Some Firebase records may store sessions as a Map.
    else if (raw is Map) {
      final entries =
          raw.entries.toList()
            ..sort(
              (a, b) => a.key
                  .toString()
                  .compareTo(
                    b.key.toString(),
                  ),
            );

      for (final entry in entries) {
        final item = entry.value;

        if (item is Map &&
            item["punchIn"] != null) {
          sessions.add(
            AttendanceSession(
              punchIn:
                  item["punchIn"].toString(),
              punchOut:
                  item["punchOut"]?.toString(),
            ),
          );
        }
      }
    }

    // Backward compatibility with old single-session records.
    if (sessions.isEmpty &&
        data["punchIn"] != null) {
      sessions.add(
        AttendanceSession(
          punchIn:
              data["punchIn"].toString(),
          punchOut:
              data["punchOut"]?.toString(),
        ),
      );
    }

    return sessions;
  }

  // ============================================================
  // ATTENDANCE CLASSIFICATION
  // ============================================================
  //
  // FINAL classifications:
  //
  //   FULL DAY
  //   WORK-PENDING
  //   ABSENT
  //
  // Temporary UI states:
  //
  //   IN PROGRESS
  //   MIS-PUNCH
  //
  // MIS-PUNCH is NOT calculated using 11:59 PM.
  // ============================================================

  DayType? _classify(
    String dateKey,
    Map data,
  ) {
    final status =
        data["status"]
            ?.toString()
            .toUpperCase();

    // ----------------------------------------------------------
    // MIS-PUNCH
    // ----------------------------------------------------------
    //
    // This is a temporary workflow state.
    // It is NOT one of the three DayType values.
    //
    // Do not calculate using temporaryPunchOut.
    // ----------------------------------------------------------

    if (status == "MIS-PUNCH") {
      return null;
    }

    // ----------------------------------------------------------
    // Old automatic checkout fields
    // ----------------------------------------------------------
    //
    // These should no longer be generated by the new workflow.
    // If an old record still contains them, don't calculate
    // the temporary 11:59 PM value.
    // ----------------------------------------------------------

    if (status == "AUTO CHECKOUT PENDING" ||
        data["autoPunchOut"] == true) {
      return null;
    }

    final punchIn =
        data["punchIn"]?.toString();

    final punchOut =
        data["punchOut"]?.toString();

    // ----------------------------------------------------------
    // NO PUNCH-IN
    // ----------------------------------------------------------

    if (punchIn == null ||
        punchIn.trim().isEmpty) {
      return DayType.absent;
    }

    // ----------------------------------------------------------
    // NO PUNCH-OUT
    // ----------------------------------------------------------
    //
    // Today = employee is still working.
    //
    // Previous day = unfinished attendance.
    // Normally the next-day MIS-PUNCH check will convert it
    // into MIS-PUNCH before this classification is displayed.
    // ----------------------------------------------------------

    if (punchOut == null ||
        punchOut.trim().isEmpty) {
      return _isToday(dateKey)
          ? null
          : DayType.absent;
    }

    // ----------------------------------------------------------
    // FINAL CALCULATION
    // ----------------------------------------------------------

    return AttendanceCalculator.calculate(
      punchIn: punchIn,
      punchOut: punchOut,
      workFromHome:
          data["workFromHome"] == true,
    ).dayType;
  }

  // ============================================================
  // DAY TYPE COLOR
  // ============================================================

  Color _dayTypeColor(
    DayType? type,
  ) {
    switch (type) {
      case DayType.fullDay:
        return AppColors.success;

      case DayType.workPending:
        return AppColors.warning;

      case DayType.absent:
        return AppColors.danger;

      case null:
        return AppColors.info;
    }
  }

  // ============================================================
  // DAY TYPE TEXT
  // ============================================================

  String _dayTypeText(
    DayType? type,
  ) {
    switch (type) {
      case DayType.fullDay:
        return "FULL DAY";

      case DayType.workPending:
        return "WORK-PENDING";

      case DayType.absent:
        return "ABSENT";

      case null:
        return "IN PROGRESS";
    }
  }

  // ============================================================
  // TEMPORARY STATUS TEXT
  // ============================================================

  String _statusText(
    Map data,
  ) {
    final status =
        data["status"]
            ?.toString()
            .toUpperCase();

    if (status == "MIS-PUNCH") {
      return "MIS-PUNCH — ADMIN CORRECTION PENDING";
    }

    if (status == "AUTO CHECKOUT PENDING" ||
        data["autoPunchOut"] == true) {
      return "MIS-PUNCH — ADMIN CORRECTION PENDING";
    }

    return data["status"]?.toString() ??
        "Not Checked In";
  }

  // ============================================================
  // DISPLAY PUNCH-OUT
  // ============================================================
  //
  // For MIS-PUNCH:
  //
  // Do NOT display 11:59 PM as the actual punch-out.
  //
  // Display:
  //   Awaiting admin correction
  //
  // Once admin selects the real time, that real time is
  // displayed normally.
  // ============================================================

  String _punchOutText(
    Map data,
  ) {
    final status =
        data["status"]
            ?.toString()
            .toUpperCase();

    if (status == "MIS-PUNCH" ||
        status == "AUTO CHECKOUT PENDING" ||
        data["autoPunchOut"] == true) {
      return "Awaiting admin correction";
    }

    final punchOut =
        data["punchOut"]?.toString();

    if (punchOut == null ||
        punchOut.trim().isEmpty) {
      return "--";
    }

    return punchOut;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final dates =
        attendanceData.keys
            .map((e) => e.toString())
            .toList()
          ..sort(
            (a, b) => b.compareTo(a),
          );

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient:
              AppGradients.background,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // ==================================================
              // HEADER
              // ==================================================

              Padding(
                padding:
                    const EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  8,
                ),
                child: Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceBetween,
                  children: [
                    const Text(
                      "Attendance",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight:
                            FontWeight.bold,
                        color:
                            AppColors
                                .textPrimary,
                      ),
                    ),

                    // ============================================
                    // TODAY / LIST SWITCH
                    // ============================================

                    Container(
                      padding:
                          const EdgeInsets.all(
                        4,
                      ),
                      decoration:
                          BoxDecoration(
                        color:
                            AppColors.surface,
                        borderRadius:
                            BorderRadius
                                .circular(
                          24,
                        ),
                        boxShadow:
                            AppShadows.card,
                      ),
                      child: Row(
                        children: [
                          _toggleChip(
                            "Today",
                            !showList,
                            () => setState(
                              () => showList =
                                  false,
                            ),
                          ),
                          _toggleChip(
                            "List",
                            showList,
                            () => setState(
                              () => showList =
                                  true,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // ==================================================
              // CONTENT
              // ==================================================

              Expanded(
                child: showList
                    ? _buildList(dates)
                    : SingleChildScrollView(
                        padding:
                            const EdgeInsets.all(
                          20,
                        ),
                        child: PunchCard(
                          employeeId:
                              widget.employeeId,
                          compact: false,
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // TOGGLE CHIP
  // ============================================================

  Widget _toggleChip(
    String label,
    bool selected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 8,
        ),
        decoration:
            BoxDecoration(
          color: selected
              ? AppColors.primary
              : Colors.transparent,
          borderRadius:
              BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : AppColors.textSecondary,
            fontWeight:
                FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // LIST
  // ============================================================

  Widget _buildList(
    List<String> dates,
  ) {
    if (loading) {
      return const Center(
        child:
            CircularProgressIndicator(),
      );
    }

    if (dates.isEmpty) {
      return const Center(
        child: Text(
          "No Attendance Found",
          style: TextStyle(
            color:
                AppColors.textSecondary,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        // Run the MIS-PUNCH check again
        // when the employee refreshes history.
        await _checkPreviousDayForMisPunch();
        await _loadHistory();
      },
      child: ListView.builder(
        padding:
            const EdgeInsets.fromLTRB(
          20,
          0,
          20,
          20,
        ),
        itemCount: dates.length,
        itemBuilder:
            (context, index) {
          final date =
              dates[index];

          final rawData =
              attendanceData[date];

          if (rawData is! Map) {
            return const SizedBox
                .shrink();
          }

          final data =
              Map<dynamic, dynamic>.from(
            rawData,
          );

          final status =
              data["status"]
                  ?.toString()
                  .toUpperCase();

          final isMisPunch =
              status == "MIS-PUNCH";

          final isOldAutoCheckout =
              status ==
                      "AUTO CHECKOUT PENDING" ||
                  data["autoPunchOut"] ==
                      true;

          final dayType =
              _classify(
            date,
            data,
          );

          // ------------------------------------------------------
          // Temporary MIS-PUNCH card
          // ------------------------------------------------------

          final Color cardBackground =
              (isMisPunch ||
                      isOldAutoCheckout)
                  ? AppColors.warning
                      .withOpacity(.08)
                  : AppColors.surface;

          return Container(
            margin:
                const EdgeInsets.only(
              bottom: 10,
            ),
            padding:
                const EdgeInsets.all(
              14,
            ),
            decoration:
                BoxDecoration(
              color:
                  cardBackground,
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
              boxShadow:
                  AppShadows.card,
              border: (isMisPunch ||
                      isOldAutoCheckout)
                  ? Border.all(
                      color: AppColors
                          .warning
                          .withOpacity(
                        .25,
                      ),
                    )
                  : null,
            ),
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                // ================================================
                // DATE + STATUS
                // ================================================

                Row(
                  mainAxisAlignment:
                      MainAxisAlignment
                          .spaceBetween,
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    Text(
                      date,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.bold,
                        color:
                            AppColors
                                .textPrimary,
                      ),
                    ),

                    // --------------------------------------------
                    // TEMPORARY MIS-PUNCH
                    // --------------------------------------------

                    if (isMisPunch ||
                        isOldAutoCheckout)
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration:
                            BoxDecoration(
                          color: AppColors
                              .warning
                              .withOpacity(
                            .12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            20,
                          ),
                        ),
                        child:
                            const Text(
                          "MIS-PUNCH",
                          style:
                              TextStyle(
                            color: AppColors
                                .warning,
                            fontWeight:
                                FontWeight
                                    .bold,
                            fontSize: 11,
                          ),
                        ),
                      )

                    // --------------------------------------------
                    // FINAL CLASSIFICATION
                    // --------------------------------------------

                    else
                      Container(
                        padding:
                            const EdgeInsets
                                .symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration:
                            BoxDecoration(
                          color:
                              _dayTypeColor(
                            dayType,
                          ).withOpacity(
                            0.12,
                          ),
                          borderRadius:
                              BorderRadius
                                  .circular(
                            20,
                          ),
                        ),
                        child: Text(
                          _dayTypeText(
                            dayType,
                          ),
                          style:
                              TextStyle(
                            color:
                                _dayTypeColor(
                              dayType,
                            ),
                            fontWeight:
                                FontWeight
                                    .bold,
                            fontSize: 11,
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // ================================================
                // PUNCH-IN
                // ================================================

                Row(
                  children: [
                    const Icon(
                      Icons.login_rounded,
                      size: 16,
                      color:
                          AppColors.primary,
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    const Text(
                      "In:",
                      style:
                          TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Expanded(
                      child: Text(
                        data["punchIn"]
                                ?.toString() ??
                            "--",
                        style:
                            const TextStyle(
                          fontSize: 13,
                          fontWeight:
                              FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // ================================================
                // PUNCH-OUT
                // ================================================

                Row(
                  children: [
                    const Icon(
                      Icons.logout_rounded,
                      size: 16,
                      color:
                          AppColors.primary,
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    const Text(
                      "Out:",
                      style:
                          TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Expanded(
                      child: Text(
                        _punchOutText(
                          data,
                        ),
                        style:
                            TextStyle(
                          fontSize: 13,
                          fontWeight:
                              FontWeight.w600,
                          color: isMisPunch ||
                                  isOldAutoCheckout
                              ? AppColors
                                  .warning
                              : AppColors
                                  .textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // ================================================
                // STATUS
                // ================================================

                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 16,
                      color:
                          AppColors.primary,
                    ),
                    const SizedBox(
                      width: 7,
                    ),
                    const Text(
                      "Status:",
                      style:
                          TextStyle(
                        color: AppColors
                            .textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      width: 6,
                    ),
                    Expanded(
                      child: Text(
                        _statusText(
                          data,
                        ),
                        style:
                            TextStyle(
                          fontSize: 13,
                          fontWeight:
                              FontWeight.w600,
                          color: isMisPunch ||
                                  isOldAutoCheckout
                              ? AppColors
                                  .warning
                              : AppColors
                                  .textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),

                // ================================================
                // MIS-PUNCH EXPLANATION
                // ================================================

                if (isMisPunch ||
                    isOldAutoCheckout) ...[
                  const SizedBox(
                    height: 12,
                  ),
                  Container(
                    width:
                        double.infinity,
                    padding:
                        const EdgeInsets.all(
                      10,
                    ),
                    decoration:
                        BoxDecoration(
                      color: AppColors
                          .warning
                          .withOpacity(
                        .08,
                      ),
                      borderRadius:
                          BorderRadius
                              .circular(
                        10,
                      ),
                    ),
                    child:
                        const Row(
                      crossAxisAlignment:
                          CrossAxisAlignment
                              .start,
                      children: [
                        Icon(
                          Icons
                              .admin_panel_settings_outlined,
                          size: 18,
                          color:
                              AppColors
                                  .warning,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Expanded(
                          child: Text(
                            "You forgot to punch out. "
                            "This attendance is waiting for admin correction. "
                            "The temporary 11:59 PM time is not used for working-hour calculation.",
                            style:
                                TextStyle(
                              color: AppColors
                                  .textSecondary,
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}