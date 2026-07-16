import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';
import '../utils/notification_center.dart';

class NotificationsScreen extends StatefulWidget {
  final String employeeId;

  const NotificationsScreen({super.key, required this.employeeId});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  late DatabaseReference dbRef;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();

    NotificationCenter.markAllRead(widget.employeeId);
  }

  IconData _iconFor(String title) {
    if (title.contains("Leave")) return Icons.event_note;
    if (title.contains("Home")) return Icons.home_work;
    if (title.contains("Device")) return Icons.phone_android;
    return Icons.notifications;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Notifications", style: TextStyle(color: Colors.white)),
      ),
      body: StreamBuilder<DatabaseEvent>(
        stream: dbRef.child("Notifications").child(widget.employeeId).onValue,
        builder: (context, snapshot) {
          if (!snapshot.hasData || snapshot.data!.snapshot.value == null) {
            return const Center(child: Text("No notifications yet", style: TextStyle(color: AppColors.textSecondary)));
          }

          final data = Map<dynamic, dynamic>.from(snapshot.data!.snapshot.value as Map);
          final items = data.values.map((v) => Map<dynamic, dynamic>.from(v as Map)).toList()
            ..sort((a, b) => (b["createdAt"] ?? "").toString().compareTo((a["createdAt"] ?? "").toString()));

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              final title = item["title"]?.toString() ?? "";
              final createdAt = DateTime.tryParse(item["createdAt"]?.toString() ?? "");

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(_iconFor(title), color: AppColors.primary, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 4),
                          Text(item["message"]?.toString() ?? "", style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                          if (createdAt != null) ...[
                            const SizedBox(height: 4),
                            Text(DateFormat("dd MMM, h:mm a").format(createdAt), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          ],
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