import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';

class AdminActivityLogScreen extends StatefulWidget {
  const AdminActivityLogScreen({super.key});

  @override
  State<AdminActivityLogScreen> createState() => _AdminActivityLogScreenState();
}

class _AdminActivityLogScreenState extends State<AdminActivityLogScreen> {
  late DatabaseReference dbRef;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  IconData _iconFor(String action) {
    if (action.contains("Leave")) return Icons.event_note;
    if (action.contains("Employee")) return Icons.people;
    if (action.contains("Device")) return Icons.phone_android;
    if (action.contains("Admin")) return Icons.admin_panel_settings;
    if (action.contains("WFH") || action.contains("Home")) return Icons.home_work;
    return Icons.history;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Activity Log", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: dbRef.child("AdminActivityLog").onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("No activity recorded yet"));
          }

          final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
          final entries = data.values.map((v) => Map<dynamic, dynamic>.from(v as Map)).toList();

          entries.sort((a, b) => (b["timestamp"] ?? "").toString().compareTo((a["timestamp"] ?? "").toString()));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              final action = entry["action"]?.toString() ?? "";
              final adminName = entry["adminName"]?.toString() ?? "Unknown";
              final details = entry["details"]?.toString() ?? "";
              final timestampStr = entry["timestamp"]?.toString();
              final timestamp = timestampStr != null ? DateTime.tryParse(timestampStr) : null;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: AppShadows.card,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(action), color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(action, style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (details.isNotEmpty)
                            Text(details, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            "by $adminName"
                            "${timestamp != null ? ' \u00b7 ${DateFormat("dd MMM yyyy, h:mm a").format(timestamp)}' : ''}",
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}