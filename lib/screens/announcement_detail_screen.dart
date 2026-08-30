import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../utils/attachment_upload.dart';

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

  void _showFullScreenImage(String url, String title) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: url.startsWith('data:image/')
                    ? Image.memory(
                        base64Decode(url.split(',').last),
                        fit: BoxFit.contain,
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.contain,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(child: CircularProgressIndicator(color: Colors.white));
                        },
                        errorBuilder: (_, __, ___) => Container(
                          padding: const EdgeInsets.all(20),
                          color: Colors.black87,
                          child: const Text("Failed to load image", style: TextStyle(color: Colors.white)),
                        ),
                      ),
              ),
            ),
            IconButton(
              onPressed: () => Navigator.pop(ctx),
              icon: const CircleAvatar(
                backgroundColor: Colors.black54,
                child: Icon(Icons.close, color: Colors.white, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachment(String? name, String? url, bool isImage, String title) {
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    if (isImage) {
      return Container(
        margin: const EdgeInsets.only(top: 12),
        child: GestureDetector(
          onTap: () => _showFullScreenImage(url, title),
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 220),
                  width: double.infinity,
                  color: AppColors.background,
                  child: url.startsWith('data:image/')
                      ? Image.memory(
                          base64Decode(url.split(',').last),
                          fit: BoxFit.cover,
                          width: double.infinity,
                        )
                      : Image.network(
                          url,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (_, child, progress) {
                            if (progress == null) return child;
                            return Container(
                              height: 140,
                              color: AppColors.background,
                              child: const Center(child: CircularProgressIndicator()),
                            );
                          },
                          errorBuilder: (_, __, ___) => Container(
                            height: 100,
                            color: AppColors.background,
                            child: const Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.broken_image, color: AppColors.textSecondary),
                                  SizedBox(width: 8),
                                  Text("Image unavailable", style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
              ),
              Container(
                margin: const EdgeInsets.all(8),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.zoom_in, color: Colors.white, size: 14),
                    SizedBox(width: 4),
                    Text("Tap to expand", style: TextStyle(color: Colors.white, fontSize: 10)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Document attachment
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.insert_drive_file, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name ?? 'Attached Document',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.textPrimary),
                ),
                const Text('Tap button to open or download', style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new, size: 16),
            label: const Text('Open', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.primary,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
          ),
        ],
      ),
    );
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
                  final att = item["attachment"];
                  String? attName;
                  String? attUrl;
                  bool isImg = false;
                  if (att is Map) {
                    final attMap = Map<dynamic, dynamic>.from(att);
                    attName = attMap["name"]?.toString();
                    attUrl = attMap["url"]?.toString();
                    isImg = attMap["isImage"] == true ||
                        AttachmentUpload.isImageName(attName ?? "") ||
                        (attUrl ?? "").startsWith("data:image/");
                  }

                  announcements.add({
                    "key": key.toString(),
                    "title": item["title"]?.toString() ?? "Announcement",
                    "message": item["message"]?.toString() ?? "",
                    "createdAt": item["createdAt"]?.toString(),
                    "attachmentName": attName,
                    "attachmentUrl": attUrl,
                    "isImage": isImg,
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
              final attachmentName = data['attachmentName']?.toString();
              final attachmentUrl = data['attachmentUrl']?.toString();
              final isImage = data['isImage'] == true;

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
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(message, style: const TextStyle(color: AppColors.textPrimary, fontSize: 14, height: 1.4)),
                          _buildAttachment(attachmentName, attachmentUrl, isImage, title),
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
