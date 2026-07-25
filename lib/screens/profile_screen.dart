import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import '../utils/session_manager.dart';
import '../utils/notification_center.dart';
import 'change_password_screen.dart';
import 'manage_admins_screen.dart';
import 'admin_activity_log_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_shell.dart';
import 'employee_shell.dart';
import 'login_screens.dart';
import 'notification_settings_screen.dart';
import 'language_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String employeeId;
  final bool viewOnly;
  final bool isAdmin;
  final bool isSuperAdmin;
  final bool hasAdminAccess;

  const ProfileScreen({
    super.key,
    required this.employeeId,
    this.viewOnly = false,
    this.isAdmin = false,
    this.isSuperAdmin = false,
    this.hasAdminAccess = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late DatabaseReference dbRef;

  bool loading = true;
  bool editing = false;
  bool saving = false;
  Map<dynamic, dynamic> profile = {};
  String selectedLanguage = "English (India)";

  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  File? pickedPhotoFile;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _loadProfile();
    _loadLanguage();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => selectedLanguage = prefs.getString("app_language") ?? "English (India)");
  }

  Future<void> _loadProfile() async {
    setState(() => loading = true);
    try {
      final snapshot = await dbRef.child("users").child(widget.employeeId).get();
      if (!mounted) return;
      if (snapshot.exists) {
        profile = Map<dynamic, dynamic>.from(snapshot.value as Map);
        _phoneController.text = profile["phone"]?.toString() ?? "";
        _emailController.text = profile["email"]?.toString() ?? "";
      }
      setState(() => loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  Future<void> _pickPhoto() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (_) => SafeArea(
        child: Wrap(children: [
          ListTile(leading: const Icon(Icons.photo_camera), title: const Text("Take Photo"), onTap: () => Navigator.pop(context, ImageSource.camera)),
          ListTile(leading: const Icon(Icons.photo_library), title: const Text("Choose from Gallery"), onTap: () => Navigator.pop(context, ImageSource.gallery)),
        ]),
      ),
    );
    if (source == null) return;

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 300, maxHeight: 300, imageQuality: 60);
    if (picked == null) return;
    setState(() => pickedPhotoFile = File(picked.path));
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final updates = <String, dynamic>{
        "phone": _phoneController.text.trim(),
        "email": _emailController.text.trim(),
      };
      if (pickedPhotoFile != null) {
        final bytes = await pickedPhotoFile!.readAsBytes();
        updates["photoBase64"] = base64Encode(bytes);
      }

      await dbRef.child("users").child(widget.employeeId).update(updates);

      if (!mounted) return;
      setState(() {
        profile = {...profile, ...updates};
        editing = false;
        saving = false;
        pickedPhotoFile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated")));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text("Logout"),
        content: const Text("Are you sure you want to logout?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Logout")),
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
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text("Close"))],
      ),
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.primary),
        const SizedBox(width: 10),
        Expanded(child: Text(value)),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard")));
          },
        ),
      ],
    );
  }

  void _comingSoon() => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Coming soon")));

  Widget _adminNotificationBell() {
    return GestureDetector(
      onTap: () {
        Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationsScreen()));
      },
      child: StreamBuilder<int>(
        stream: NotificationCenter.adminUnreadCount(),
        builder: (context, snapshot) {
          final count = snapshot.data ?? 0;
          return Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: Colors.white24, shape: BoxShape.circle),
            child: Badge(
              isLabelVisible: count > 0,
              label: Text("$count"),
              backgroundColor: AppColors.danger,
              child: const Icon(Icons.notifications_outlined, color: Colors.white, size: 18),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));
    }

    final photoBase64 = profile["photoBase64"]?.toString();
    final status = profile["status"]?.toString() ?? "active";
    final isActive = status.toLowerCase() == "active";
    final canEdit = !widget.viewOnly;

    ImageProvider? avatarImage;
    if (pickedPhotoFile != null) {
      avatarImage = FileImage(pickedPhotoFile!);
    } else if (photoBase64 != null && photoBase64.isNotEmpty) {
      avatarImage = MemoryImage(base64Decode(photoBase64));
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              decoration: const BoxDecoration(
                gradient: AppGradients.brand,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Profile", style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                      if (widget.isAdmin && !widget.viewOnly) _adminNotificationBell(),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      GestureDetector(
                        onTap: (canEdit && editing) ? _pickPhoto : null,
                        child: Stack(
                          children: [
                            CircleAvatar(
                              radius: 34,
                              backgroundColor: Colors.white24,
                              backgroundImage: avatarImage,
                              child: avatarImage == null ? const Icon(Icons.person, size: 34, color: Colors.white) : null,
                            ),
                            if (canEdit && editing)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                                  child: const Icon(Icons.camera_alt, size: 14, color: AppColors.primary),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    profile["name"]?.toString() ?? widget.employeeId,
                                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: (isActive ? AppColors.success : AppColors.danger).withOpacity(0.25),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    isActive ? "Active" : "Inactive",
                                    style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                            Text("ID: ${widget.employeeId}", style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            if (profile["designation"] != null && profile["designation"].toString().isNotEmpty)
                              Text(profile["designation"].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                            if (profile["department"] != null && profile["department"].toString().isNotEmpty)
                              Text(profile["department"].toString(), style: const TextStyle(color: Colors.white70, fontSize: 12)),
                          ],
                        ),
                      ),
                      if (canEdit)
                        IconButton(
                          icon: Icon(editing ? Icons.check : Icons.edit, color: Colors.white),
                          onPressed: saving
                              ? null
                              : () {
                                  if (editing) {
                                    _save();
                                  } else {
                                    setState(() => editing = true);
                                  }
                                },
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Transform.translate(
              offset: const Offset(0, -16),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), boxShadow: AppShadows.card),
                child: Row(
                  children: [
                    Expanded(child: _infoCol(Icons.email_outlined, "Email", canEdit && editing ? null : (profile["email"]?.toString() ?? "--"))),
                    Expanded(child: _infoCol(Icons.phone_outlined, "Phone", canEdit && editing ? null : (profile["phone"]?.toString() ?? "--"))),
                    Expanded(child: _infoCol(Icons.badge_outlined, "Role", (profile["role"]?.toString() ?? "employee").toUpperCase())),
                  ],
                ),
              ),
            ),
            if (widget.viewOnly)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Container(
                  decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.card),
                  child: Column(
                    children: [
                      _profileDetail(Icons.person_outline, "Full name", profile["name"]?.toString() ?? widget.employeeId),
                      _profileDetail(Icons.email_outlined, "Email", profile["email"]?.toString() ?? "Not provided"),
                      _profileDetail(Icons.phone_outlined, "Phone", profile["phone"]?.toString() ?? "Not provided"),
                      _profileDetail(Icons.badge_outlined, "Employee ID", widget.employeeId),
                      _profileDetail(Icons.work_outline, "Role", (profile["role"]?.toString() ?? "employee").toUpperCase()),
                      _profileDetail(Icons.business_outlined, "Department", profile["department"]?.toString() ?? "Not provided"),
                      _profileDetail(Icons.workspace_premium_outlined, "Designation", profile["designation"]?.toString() ?? "Not provided"),
                    ],
                  ),
                ),
              ),
            if (canEdit && editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Column(
                  children: [
                    TextField(controller: _phoneController, decoration: const InputDecoration(labelText: "Phone", prefixIcon: Icon(Icons.phone))),
                    const SizedBox(height: 10),
                    TextField(controller: _emailController, decoration: const InputDecoration(labelText: "Email", prefixIcon: Icon(Icons.email))),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            if (widget.hasAdminAccess && !widget.isAdmin)
              _section("Admin Access", [
                _tile(Icons.admin_panel_settings, "Switch to Admin Panel", () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminShell(employeeId: widget.employeeId, employeeName: profile["name"]?.toString(), isSuperAdmin: false),
                    ),
                  );
                }),
              ]),

            if (widget.isAdmin && !widget.isSuperAdmin)
              _section("Employee View", [
                _tile(Icons.home_outlined, "Back to My Dashboard", () {
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (_) => EmployeeShell(employeeId: widget.employeeId)),
                    (route) => false,
                  );
                }),
              ]),

            if (widget.isSuperAdmin)
              _section("Super Admin", [
                _tile(Icons.admin_panel_settings, "Grant Admin Access", () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ManageAdminsScreen(superAdminId: widget.employeeId, superAdminName: profile["name"]?.toString() ?? widget.employeeId),
                    ),
                  );
                }),
                _tile(Icons.history, "Activity Log", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminActivityLogScreen()));
                }),
              ]),

            if (!widget.viewOnly) ...[
              _section("Account", [
                _tile(Icons.lock_reset, "Change Password", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => ChangePasswordScreen(employeeId: widget.employeeId)));
                }),
              ]),
              _section("Support", [
                if (!widget.isAdmin) _tile(Icons.support_agent, "Contact HR / Support", _showContactHR),
                _tile(Icons.info_outline, "About App", _showAbout),
              ]),
              _section("Preferences", [
                _tile(Icons.notifications_outlined, "Notification Settings", () {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationSettingsScreen()));
                }),
                _tile(Icons.language, "Language \u2014 $selectedLanguage", () async {
                  final result = await Navigator.push(context, MaterialPageRoute(builder: (_) => const LanguageScreen()));
                  if (result != null) setState(() => selectedLanguage = result.toString());
                }),
              ]),
              _section("Other", [
                _tile(Icons.shield_outlined, "Privacy Policy", _comingSoon),
                _tile(Icons.description_outlined, "Terms & Conditions", _comingSoon),
              ]),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
                child: ListTile(
                  leading: const Icon(Icons.logout, color: AppColors.danger),
                  title: const Text("Logout", style: TextStyle(color: AppColors.danger, fontWeight: FontWeight.bold)),
                  onTap: _logout,
                ),
              ),
              const SizedBox(height: 20),
            ] else
              const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoCol(IconData icon, String label, String? value) {
    return Column(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 10)),
        if (value != null)
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11), overflow: TextOverflow.ellipsis, maxLines: 1),
      ],
    );
  }

  Widget _profileDetail(IconData icon, String label, String value) => ListTile(
        leading: Icon(icon, color: AppColors.primary),
        title: Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
        subtitle: Text(value, style: const TextStyle(color: AppColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
      );

  Widget _section(String title, List<Widget> tiles) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title.toUpperCase(), style: const TextStyle(color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), boxShadow: AppShadows.card),
            child: Column(children: tiles),
          ),
          const SizedBox(height: 14),
        ],
      ),
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
}
