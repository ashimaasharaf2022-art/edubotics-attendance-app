import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../utils/app_colors.dart';

class DashboardHeader extends StatelessWidget {
  final String name;
  final String employeeId;
  final String? photoBase64;

  const DashboardHeader({
    super.key,
    required this.name,
    required this.employeeId,
    this.photoBase64,
  });

  @override
  Widget build(BuildContext context) {
    ImageProvider? avatarImage;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(photoBase64!));
      } catch (_) {
        avatarImage = null;
      }
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppShadows.card,
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: AppColors.primary.withOpacity(0.12),
            backgroundImage: avatarImage,
            child: avatarImage == null
                ? const Icon(Icons.person, color: AppColors.primary, size: 26)
                : null,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Welcome, $name",
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text("ID: $employeeId", style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                Text(
                  DateFormat("EEE, dd MMM yyyy").format(DateTime.now()),
                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}