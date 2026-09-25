import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';
import '../utils/session_manager.dart';
import 'login_screens.dart';

/// Profile belonging only to the CEO / Super Admin.
///
/// The Super Admin is NOT treated as an employee and does not
/// have the employee/admin dashboard switching functionality.
class SuperAdminProfileScreen extends StatefulWidget {
  final String superAdminId;

  const SuperAdminProfileScreen({
    super.key,
    required this.superAdminId,
  });

  @override
  State<SuperAdminProfileScreen> createState() =>
      _SuperAdminProfileScreenState();
}

class _SuperAdminProfileScreenState
    extends State<SuperAdminProfileScreen> {
  late final DatabaseReference dbRef;

  bool loading = true;
  bool saving = false;

  Map<String, dynamic> profile = {};

  final nameController = TextEditingController();
  final designationController = TextEditingController();
  final emailController = TextEditingController();
  final phoneController = TextEditingController();
  final addressController = TextEditingController();

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _loadProfile();
  }

  @override
  void dispose() {
    nameController.dispose();
    designationController.dispose();
    emailController.dispose();
    phoneController.dispose();
    addressController.dispose();

    super.dispose();
  }

  // ============================================================
  // LOAD PROFILE
  // ============================================================

  Future<void> _loadProfile() async {
    try {
      final snap = await dbRef
          .child('users')
          .child(widget.superAdminId)
          .get();

      if (snap.exists && snap.value is Map) {
        final raw =
            Map<dynamic, dynamic>.from(snap.value as Map);

        profile = {
          for (final entry in raw.entries)
            entry.key.toString(): entry.value,
        };
      }

      nameController.text =
          profile['name']?.toString() ??
          widget.superAdminId;

      designationController.text =
          profile['designation']?.toString() ??
          'Chief Executive Officer';

      emailController.text =
          profile['email']?.toString() ?? '';

      phoneController.text =
          profile['phone']?.toString() ?? '';

      addressController.text =
          profile['address']?.toString() ?? '';

      if (!mounted) return;

      setState(() {
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _message(
        'Unable to load profile: $e',
      );
    }
  }

  // ============================================================
  // SAVE PROFILE
  // ============================================================

  Future<void> _save() async {
    if (saving) return;

    setState(() {
      saving = true;
    });

    try {
      await dbRef
          .child('users')
          .child(widget.superAdminId)
          .update({
        // These values must always remain Super Admin values.
        'employeeId': widget.superAdminId,
        'role': 'superadmin',

        'name': nameController.text.trim(),

        'designation':
            designationController.text.trim(),

        'email':
            emailController.text.trim(),

        'phone':
            phoneController.text.trim(),

        'address':
            addressController.text.trim(),
      });

      if (!mounted) return;

      setState(() {
        saving = false;
      });

      _message(
        'Super Admin profile updated.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      _message(
        'Could not save profile: $e',
      );
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> _logout() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text(
            'Do you want to log out of the Super Admin account?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx, false);
              },
              child: const Text('CANCEL'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx, true);
              },
              child: const Text('LOG OUT'),
            ),
          ],
        );
      },
    );

    if (yes != true) return;

    await SessionManager.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  // ============================================================
  // MESSAGE
  // ============================================================

  void _message(String text) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
      ),
    );
  }

  // ============================================================
  // TEXT FIELD
  // ============================================================

  Widget _field(
    IconData icon,
    String label,
    TextEditingController controller, {
    bool readOnly = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          labelText: label,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Super Admin Profile',
        ),
      ),

      body: RefreshIndicator(
        onRefresh: _loadProfile,

        child: ListView(
          physics:
              const AlwaysScrollableScrollPhysics(),

          padding: const EdgeInsets.fromLTRB(
            18,
            20,
            18,
            30,
          ),

          children: [
            // ==================================================
            // PROFILE ICON
            // ==================================================

            Center(
              child: CircleAvatar(
                radius: 46,
                backgroundColor:
                    AppColors.primary.withValues(alpha: .12),

                child: const Icon(
                  Icons.verified_user_rounded,
                  size: 48,
                  color: AppColors.primary,
                ),
              ),
            ),

            const SizedBox(height: 14),

            // ==================================================
            // NAME
            // ==================================================

            Center(
              child: Text(
                nameController.text.isEmpty
                    ? widget.superAdminId
                    : nameController.text,

                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),

            const SizedBox(height: 4),

            // ==================================================
            // ROLE
            // ==================================================

            const Center(
              child: Text(
                'Chief Executive Officer • Super Admin',

                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ==================================================
            // PROFILE CARD
            // ==================================================

            Container(
              padding: const EdgeInsets.all(18),

              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.circular(18),
                boxShadow: AppShadows.card,
              ),

              child: Column(
                children: [
                  // ------------------------------------------
                  // SUPER ADMIN ID
                  // ------------------------------------------

                  _field(
                    Icons.badge_outlined,
                    'Super Admin ID',

                    TextEditingController(
                      text: widget.superAdminId,
                    ),

                    readOnly: true,
                  ),

                  // ------------------------------------------
                  // ROLE
                  // ------------------------------------------

                  _field(
                    Icons.admin_panel_settings_outlined,
                    'Role',

                    TextEditingController(
                      text: 'superadmin',
                    ),

                    readOnly: true,
                  ),

                  // ------------------------------------------
                  // NAME
                  // ------------------------------------------

                  _field(
                    Icons.person_outline,
                    'Name',
                    nameController,
                  ),

                  // ------------------------------------------
                  // DESIGNATION
                  // ------------------------------------------

                  _field(
                    Icons.work_outline,
                    'Designation',
                    designationController,
                  ),

                  // ------------------------------------------
                  // EMAIL
                  // ------------------------------------------

                  _field(
                    Icons.email_outlined,
                    'Official Email',
                    emailController,
                  ),

                  // ------------------------------------------
                  // PHONE
                  // ------------------------------------------

                  _field(
                    Icons.phone_outlined,
                    'Phone',
                    phoneController,
                  ),

                  // ------------------------------------------
                  // ADDRESS
                  // ------------------------------------------

                  _field(
                    Icons.location_on_outlined,
                    'Address',
                    addressController,
                  ),

                  const SizedBox(height: 4),

                  // ------------------------------------------
                  // SAVE BUTTON
                  // ------------------------------------------

                  SizedBox(
                    width: double.infinity,
                    height: 48,

                    child: FilledButton(
                      onPressed:
                          saving ? null : _save,

                      child: saving
                          ? const SizedBox(
                              height: 20,
                              width: 20,

                              child:
                                  CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'SAVE PROFILE',
                            ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ==================================================
            // LOGOUT
            // ==================================================

            OutlinedButton.icon(
              onPressed: _logout,

              icon: const Icon(
                Icons.logout,
              ),

              label: const Text(
                'LOG OUT',
              ),
            ),
          ],
        ),
      ),
    );
  }
}