import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';

/// Lists every company announcement published by an Admin or Super Admin,
/// newest first. Used from both the employee dashboard (read-only) and the
/// admin dashboard's "View Details" button (with delete support).
class AnnouncementDetailScreen extends StatefulWidget {
  final bool isAdmin;

  const AnnouncementDetailScreen({super.key, this.isAdmin = false});

  @override
  State<AnnouncementDetailScreen> createState() => _AnnouncementDetailScreenState();
}

class _AnnouncementDetailScreenState extends State<AnnouncementDetailScreen> {
  late final DatabaseReference dbRef;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  Future<void> _confirmDelete(String key, String title) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Delete Announcement"),
        content: Text('Delete "$title"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await dbRef.child('Announcements').child(key).remove();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Announcement deleted")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(title: const Text('Announcements')),
      body: StreamBuilder<DatabaseEvent>(
        stream: dbRef.child('Announcements').onValue,
        builder: (context, snapshot) {
          final List<Map<String, dynamic>> announcements = [];
          if (snapshot.hasData && snapshot.data!.snapshot.value != null) {
            final value = snapshot.data!.snapshot.value;
            if (value is Map) {
              final raw = Map<dynamic, dynamic>.from(value);
              raw.forEach((key, v) {
                if (v is Map) {
                  final item = Map<dynamic, dynamic>.from(v);
                  announcements.add({
                    "key": key.toString(),
                    "title": item["title"]?.toString() ?? "Announcement",
                    "message": item["message"]?.toString() ?? "",
                    "createdAt": item["createdAt"]?.toString(),
                  });
                }
              });
              announcements.sort((a, b) => (b["createdAt"] ?? "").toString().compareTo((a["createdAt"] ?? "").toString()));
            }
          }

          if (announcements.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  "No announcements have been published yet.",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: announcements.length,
            itemBuilder: (context, index) {
              final data = announcements[index];
              final key = data["key"].toString();
              final title = data["title"]?.toString() ?? "Announcement";
              final message = data["message"]?.toString() ?? "";
              final createdAtRaw = data["createdAt"]?.toString();
              String? postedOn;
              if (createdAtRaw != null) {
                final parsed = DateTime.tryParse(createdAtRaw);
                if (parsed != null) {
                  postedOn = DateFormat("EEE, dd MMM yyyy \u2022 hh:mm a").format(parsed);
                }
              }

              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(gradient: AppGradients.brand, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.hero),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.campaign_rounded, color: Colors.white, size: 28),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Company announcement', style: TextStyle(color: Colors.white70, fontSize: 11)),
                                const SizedBox(height: 3),
                                Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800)),
                                if (postedOn != null) ...[
                                  const SizedBox(height: 3),
                                  Text(postedOn, style: const TextStyle(color: Colors.white70, fontSize: 11)),
                                ],
                              ],
                            ),
                          ),
                          if (widget.isAdmin)
                            IconButton(
                              onPressed: () => _confirmDelete(key, title),
                              icon: const Icon(Icons.delete_outline, color: Colors.white),
                              tooltip: "Delete",
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                      child: Text(message, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4)),
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
