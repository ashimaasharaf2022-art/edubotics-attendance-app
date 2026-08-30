import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import '../utils/session_manager.dart';
import 'admin_shell.dart';
import 'change_password_screen.dart';
import 'language_screen.dart';
import 'login_screens.dart';
import 'notification_settings_screen.dart';

/// Settings/account menu opened from the profile avatar in the dashboard.
///
/// This is deliberately separate from ProfileScreen. ProfileScreen is the
/// employee-detail page opened from the bottom Profile tab; this screen only
/// contains account-level actions and preferences.
class AccountSettingsScreen extends StatefulWidget {
  final String employeeId;

  const AccountSettingsScreen({super.key, required this.employeeId});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  late DatabaseReference dbRef;

  bool loading = true;
  bool hasAdminAccess = false;
  bool isSuperAdmin = false;
  String employeeName = "";
  String? photoBase64;
  String selectedLanguage = "English (India)";

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadAccount();
  }

  Future<void> _loadAccount() async {
    try {
      final snapshot = await dbRef.child("users").child(widget.employeeId).get();
      final prefs = await SessionManager.getRole();

      if (!mounted) return;

      if (snapshot.exists && snapshot.value is Map) {
        final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
        final role = (data["role"]?.toString() ?? prefs ?? "employee").toLowerCase();
        setState(() {
          employeeName = data["name"]?.toString() ?? widget.employeeId;
          photoBase64 = data["photoBase64"]?.toString();
          hasAdminAccess = data["adminAccess"] == true || role == "admin" || role == "superadmin";
          isSuperAdmin = role == "superadmin";
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }

      // Keep the language preference consistent with the existing settings screen.
      // This is intentionally loaded locally and does not modify Firebase.
      // ignore: use_build_context_synchronously
      final language = await _loadSavedLanguage();
      if (!mounted) return;
      setState(() => selectedLanguage = language);
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<String> _loadSavedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString("app_language") ?? "English (India)";
  }

  String get _initials {
    final name = employeeName.isEmpty ? widget.employeeId : employeeName;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  ImageProvider? get _avatarImage {
    if (photoBase64 == null || photoBase64!.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(photoBase64!));
    } catch (_) {
      return null;
    }
  }

  Future<void> _changeLanguage() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LanguageScreen()),
    );
    if (!mounted || result == null) return;
    setState(() => selectedLanguage = result.toString());
  }

  void _switchToAdminPanel() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShell(
          employeeId: widget.employeeId,
          employeeName: employeeName,
          isSuperAdmin: isSuperAdmin,
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text("Logout", style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    await SessionManager.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationLegalese: "© ${DateTime.now().year} ${AppConstants.companyName}",
    );
  }

  void _showContactHR() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Contact HR / Support"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _contactRow(Icons.phone, AppConstants.hrPhone),
            const SizedBox(height: 12),
            _contactRow(Icons.email, AppConstants.hrEmail),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close")),
        ],
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  _section("Account Settings", [
                    _tile(Icons.lock_reset, "Change Password", () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ChangePasswordScreen(employeeId: widget.employeeId),
                        ),
                      );
                    }),
                  ]),
                  const SizedBox(height: 10),
                  _section("Support & Help", [
                    _tile(Icons.support_agent, "Contact HR / Support", _showContactHR),
                    _tile(Icons.info_outline, "About App", _showAbout),
                  ]),
                  const SizedBox(height: 10),
                  _section("Preferences", [
                    _tile(Icons.notifications_outlined, "Notification Settings", () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()),
                      );
                    }),
                    _tile(Icons.language, "Language — $selectedLanguage", _changeLanguage),
                  ]),
                  if (hasAdminAccess) ...[
                    const SizedBox(height: 10),
                    _section("Admin", [
                      _tile(Icons.admin_panel_settings_outlined, "Switch to Admin Panel", _switchToAdminPanel),
                    ]),
                  ],
                  const SizedBox(height: 10),
                  _logoutTile(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final avatar = _avatarImage;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0B0F1F), Color(0xFF171B3D)],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back, color: Colors.white),
              ),
              const Spacer(),
              Image.asset(
                'assets/images/workora_logo.png',
                height: 28,
                width: 28,
                errorBuilder: (_, __, ___) => const Icon(Icons.blur_circular_rounded, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 7),
              const Text(
                "workora",
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              const SizedBox(width: 48),
            ],
          ),
          const SizedBox(height: 18),
          CircleAvatar(
            radius: 38,
            backgroundColor: Colors.white24,
            backgroundImage: avatar,
            child: avatar == null
                ? Text(_initials, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800))
                : null,
          ),
          const SizedBox(height: 10),
          Text(
            employeeName.isEmpty ? widget.employeeId : employeeName,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            "ID: ${widget.employeeId}",
            style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> tiles) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            boxShadow: AppShadows.card,
          ),
          child: Column(children: tiles),
        ),
      ],
    );
  }

  Widget _tile(IconData icon, String title, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: AppColors.primary),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: const Icon(Icons.chevron_right, size: 20, color: AppColors.textSecondary),
      onTap: onTap,
    );
  }

  Widget _logoutTile() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppShadows.card,
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: AppColors.danger),
        title: const Text("Logout", style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.w700)),
        onTap: _logout,
      ),
    );
  }
}
