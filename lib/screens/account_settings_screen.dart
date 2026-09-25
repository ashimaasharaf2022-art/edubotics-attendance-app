import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_colors.dart';
import '../utils/session_manager.dart';
import '../utils/workora_app_settings.dart';
import 'admin_shell.dart';
import 'employee_shell.dart';
import 'change_password_screen.dart';
import 'profile_screen.dart';
import 'login_screens.dart';

/// Settings/account menu opened from the profile avatar in the dashboard.
///
/// This is deliberately separate from ProfileScreen. ProfileScreen is the
/// employee-detail page opened from the bottom Profile tab; this screen only
/// contains account-level actions and preferences.
class AccountSettingsScreen extends StatefulWidget {
  final String employeeId;

  /// True when this screen was opened from the Admin Dashboard.
  /// In that mode an admin should see "Switch to My Employee Dashboard".
  final bool isAdminPanel;

  const AccountSettingsScreen({
    super.key,
    required this.employeeId,
    this.isAdminPanel = false,
  });

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
  bool _isDarkMode = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadAccount();
    _loadThemePreference();
    WorkoraAppSettings.isDarkMode.addListener(_syncGlobalTheme);
  }

  @override
  void dispose() {
    WorkoraAppSettings.isDarkMode.removeListener(_syncGlobalTheme);
    super.dispose();
  }

  void _syncGlobalTheme() {
    if (!mounted) return;
    final value = WorkoraAppSettings.isDarkMode.value;
    if (value != _isDarkMode) {
      setState(() => _isDarkMode = value);
    }
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
          hasAdminAccess =
              data["adminAccess"] == true ||
              role == "admin" ||
              role == "superadmin";
          isSuperAdmin = role == "superadmin";
          _accountRole = role;
          _accountHrAccess =
              data["hrAccess"] == true ||
              data["hr_access"] == true ||
              role == "hr" ||
              role == "humanresources" ||
              role == "human_resources" ||
              role == "human resources";
          loading = false;
        });
      } else {
        setState(() => loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => loading = false);
    }
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

  void _switchToAdminPanel() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => AdminShell(
          employeeId: widget.employeeId,
          employeeName: employeeName,
          isSuperAdmin: isSuperAdmin,
        ),
      ),
      (route) => false,
    );
  }

  void _switchToMyEmployeeDashboard() {
    if (isSuperAdmin) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => EmployeeShell(
          employeeId: widget.employeeId,
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

  Future<void> _loadThemePreference() async {
    await WorkoraAppSettings.load();
    if (!mounted) return;

    setState(() {
      _isDarkMode = WorkoraAppSettings.isDarkMode.value;
    });
  }

  Future<void> _toggleTheme() async {
    final next = !_isDarkMode;

    setState(() => _isDarkMode = next);
    await WorkoraAppSettings.setDarkMode(next);
  }

  bool get hasHrAccess {
    return _accountRole == 'hr' ||
        _accountRole == 'humanresources' ||
        _accountRole == 'human_resources' ||
        _accountRole == 'human resources' ||
        _accountHrAccess;
  }

  String _accountRole = 'employee';
  bool _accountHrAccess = false;

  Color get _sheetBackground =>
      _isDarkMode ? const Color(0xFF0F1F1A) : AppColors.surface;

  Color get _contentBackground =>
      _isDarkMode ? const Color(0xFF14251F) : AppColors.background;

  Color get _primaryText =>
      _isDarkMode ? Colors.white : AppColors.textPrimary;

  Color get _secondaryText =>
      _isDarkMode ? const Color(0xFFB7C6C0) : AppColors.textSecondary;

  Color get _dividerColor =>
      _isDarkMode ? const Color(0xFF2B4038) : AppColors.divider;

  @override
  Widget build(BuildContext context) {

    final topInset = MediaQuery.of(context).padding.top;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Leave the system status-bar area untouched so the dashboard's
          // notification/status icons remain visible.
          Positioned(
            top: topInset,
            left: 0,
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Container(
                color: Colors.black.withValues(alpha: .34),
              ),
            ),
          ),

          // The drawer begins below the status bar instead of covering it.
          Positioned(
            top: topInset,
            left: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * .71,
            child: Material(
                  color: _sheetBackground,
                  elevation: 20,
                  shadowColor: Colors.black.withValues(alpha: .30),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(24),
                    bottomRight: Radius.circular(24),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: loading
                      ? Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        )
                      : Column(
                          children: [
                            _buildProfileHeader(context),
                            Expanded(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  18,
                                  18,
                                  24,
                                ),
                                child: Column(
                                  children: [
                                    _drawerTile(
                                      icon: Icons.person_outline_rounded,
                                      title: 'My profile',
                                      onTap: _openMyProfile,
                                    ),
                                  
                                    const SizedBox(height: 18),
                                    _drawerDivider(),
                                    const SizedBox(height: 18),
                                    _drawerTile(
                                      icon: Icons.lock_reset_rounded,
                                      title: 'Change password',
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => ChangePasswordScreen(
                                              employeeId: widget.employeeId,
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    _drawerTile(
                                      icon: _isDarkMode
                                          ? Icons.light_mode_rounded
                                          : Icons.dark_mode_rounded,
                                      title: _isDarkMode
                                          ? 'Switch to light mode'
                                          : 'Switch to dark mode',
                                      onTap: _toggleTheme,
                                    ),
                                    if (hasAdminAccess && !isSuperAdmin) ...[
                                      const SizedBox(height: 18),
                                      _drawerDivider(),
                                      const SizedBox(height: 18),
                                      _drawerTile(
                                        icon: widget.isAdminPanel
                                            ? Icons.dashboard_outlined
                                            : Icons.admin_panel_settings_outlined,
                                        title: widget.isAdminPanel
                                            ? 'Switch to employee dashboard'
                                            : 'Switch to admin dashboard',
                                        onTap: widget.isAdminPanel
                                            ? _switchToMyEmployeeDashboard
                                            : _switchToAdminPanel,
                                      ),
                                    ],
                                    if (hasHrAccess && !isSuperAdmin) ...[
                                      const SizedBox(height: 10),
                                      _drawerTile(
                                        icon: Icons.badge_outlined,
                                        title: 'Switch to HR dashboard',
                                        onTap: _switchToHrDashboard,
                                      ),
                                    ],
                                    const SizedBox(height: 18),
                                    _drawerDivider(),
                                    const SizedBox(height: 18),
                                    _logoutDrawerTile(),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ),
          ],
        ),
      );
  }

  Widget _buildProfileHeader(BuildContext context) {
    final avatar = _avatarImage;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 46, 18, 22),
      decoration: BoxDecoration(
        color: _sheetBackground,
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 78,
                height: 78,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.primary,
                    width: 3,
                  ),
                  color: AppColors.primary.withValues(alpha: .08),
                ),
                child: ClipOval(
                  child: avatar == null
                      ? Center(
                          child: Text(
                            _initials,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        )
                      : Image(
                          image: avatar,
                          fit: BoxFit.cover,
                        ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              employeeName.isEmpty
                                  ? widget.employeeId
                                  : employeeName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 18,
                                height: 1.15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Material(
                            color: _contentBackground,
                            shape: const CircleBorder(),
                            child: InkWell(
                              onTap: () => Navigator.maybePop(context),
                              customBorder: const CircleBorder(),
                              child: const SizedBox(
                                width: 42,
                                height: 42,
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 25,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Employee ID: ${widget.employeeId}',
                        style: TextStyle(
                          color: _secondaryText,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _drawerTile({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Material(
      color: _contentBackground,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: _dividerColor,
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: .10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  icon,
                  color: AppColors.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _primaryText,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: _secondaryText,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _drawerDivider() {
    return Divider(
      height: 1,
      thickness: 1,
      color: _dividerColor,
    );
  }

  Widget _logoutDrawerTile() {
    return Material(
      color: _isDarkMode
          ? const Color(0xFF321D20)
          : const Color(0xFFFFF0F1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: _logout,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(
            horizontal: 13,
            vertical: 11,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AppColors.danger.withValues(alpha: .20),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.danger.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.logout_rounded,
                  color: AppColors.danger,
                  size: 25,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Log out',
                  style: TextStyle(
                    color: AppColors.danger,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.danger,
                size: 23,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openMyProfile() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          employeeId: widget.employeeId,
        ),
      ),
    );
  }

  void _openAssets() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Assets screen is not connected yet.'),
      ),
    );
  }

  void _switchToHrDashboard() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('HR dashboard is not connected yet.'),
      ),
    );
  }

  Widget _logoutTileNew() {
    return _logoutDrawerTile();
  }
}
