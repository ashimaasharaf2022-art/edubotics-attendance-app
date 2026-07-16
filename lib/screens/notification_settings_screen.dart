import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  bool leaveUpdates = true;
  bool wfhUpdates = true;
  bool dailyReminder = true;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      leaveUpdates = prefs.getBool("notif_leave") ?? true;
      wfhUpdates = prefs.getBool("notif_wfh") ?? true;
      dailyReminder = prefs.getBool("notif_daily") ?? true;
      loading = false;
    });
  }

  Future<void> _save(String key, bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Notification Settings", style: TextStyle(color: Colors.white)),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                  child: Column(
                    children: [
                      SwitchListTile(
                        secondary: const Icon(Icons.event_note, color: AppColors.primary),
                        title: const Text("Leave Updates"),
                        subtitle: const Text("Get notified when your leave is approved or rejected", style: TextStyle(fontSize: 12)),
                        value: leaveUpdates,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          setState(() => leaveUpdates = v);
                          _save("notif_leave", v);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.home_work, color: AppColors.primary),
                        title: const Text("Work From Home Updates"),
                        subtitle: const Text("Get notified when your WFH request is reviewed", style: TextStyle(fontSize: 12)),
                        value: wfhUpdates,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          setState(() => wfhUpdates = v);
                          _save("notif_wfh", v);
                        },
                      ),
                      const Divider(height: 1),
                      SwitchListTile(
                        secondary: const Icon(Icons.alarm, color: AppColors.primary),
                        title: const Text("Daily Punch Reminder"),
                        subtitle: const Text("Reminder at 9:25 AM to check in", style: TextStyle(fontSize: 12)),
                        value: dailyReminder,
                        activeColor: AppColors.primary,
                        onChanged: (v) {
                          setState(() => dailyReminder = v);
                          _save("notif_daily", v);
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}