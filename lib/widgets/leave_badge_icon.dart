import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';

class LeaveBadgeIcon extends StatefulWidget {
  final Widget icon;

  const LeaveBadgeIcon({super.key, required this.icon});

  @override
  State<LeaveBadgeIcon> createState() => _LeaveBadgeIconState();
}

class _LeaveBadgeIconState extends State<LeaveBadgeIcon> {
  late DatabaseReference dbRef;
  int pendingCount = 0;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _listen();
  }

  void _listen() {
    dbRef.child("LeaveRequests").onValue.listen((event) {
      if (!mounted || event.snapshot.value == null) {
        if (mounted) setState(() => pendingCount = 0);
        return;
      }
      int count = 0;
      final empMap = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      empMap.forEach((empId, requestsMap) {
        final requests = Map<dynamic, dynamic>.from(requestsMap as Map);
        requests.forEach((_, value) {
          final req = Map<dynamic, dynamic>.from(value as Map);
          if (req["status"] == "pending") count++;
        });
      });
      setState(() => pendingCount = count);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (pendingCount == 0) return widget.icon;
    return Badge(
      label: Text(pendingCount > 9 ? "9+" : "$pendingCount"),
      backgroundColor: AppColors.danger,
      child: widget.icon,
    );
  }
}