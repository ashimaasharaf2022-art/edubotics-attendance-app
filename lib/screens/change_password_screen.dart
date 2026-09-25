import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../utils/app_colors.dart';

/// Changes the password stored in the existing RTDB /users/{employeeId}
/// record used by the current login system.
///
/// This intentionally does not use Firebase Authentication because this app's
/// current login flow validates the password from Realtime Database.
class ChangePasswordScreen extends StatefulWidget {
  final String employeeId;

  const ChangePasswordScreen({
    super.key,
    required this.employeeId,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  late final DatabaseReference dbRef;

  final currentController = TextEditingController();
  final newController = TextEditingController();
  final confirmController = TextEditingController();

  bool isSaving = false;
  bool hideCurrent = true;
  bool hideNew = true;
  bool hideConfirm = true;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();
  }

  @override
  void dispose() {
    currentController.dispose();
    newController.dispose();
    confirmController.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    if (isSaving) return;

    final current = currentController.text;
    final newPassword = newController.text;
    final confirm = confirmController.text;

    if (current.isEmpty || newPassword.isEmpty || confirm.isEmpty) {
      _message('Please fill in all password fields.');
      return;
    }

    if (newPassword.length < 6) {
      _message('New password must be at least 6 characters.');
      return;
    }

    if (newPassword != confirm) {
      _message('New password and confirmation do not match.');
      return;
    }

    if (newPassword == current) {
      _message('New password must be different from the current password.');
      return;
    }

    setState(() => isSaving = true);

    try {
      final userRef = dbRef.child('users').child(widget.employeeId);
      final snapshot = await userRef.get();

      if (!snapshot.exists || snapshot.value is! Map) {
        _message('Employee account was not found.');
        return;
      }

      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      final storedPassword = data['password']?.toString() ?? '';

      if (storedPassword != current) {
        _message('Current password is incorrect.');
        return;
      }

      await userRef.update({'password': newPassword});

      if (!mounted) return;

      currentController.clear();
      newController.clear();
      confirmController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password changed successfully.')),
      );
    } catch (e) {
      if (mounted) {
        _message('Could not change password: $e');
      }
    } finally {
      if (mounted) {
        setState(() => isSaving = false);
      }
    }
  }

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
    required VoidCallback onToggle,
    required bool hidden,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      suffixIcon: IconButton(
        tooltip: hidden ? 'Show password' : 'Hide password',
        onPressed: onToggle,
        icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Change Password'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: AppShadows.card,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Update your password',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Employee ID: ${widget.employeeId}',
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: currentController,
                  obscureText: hideCurrent,
                  enabled: !isSaving,
                  decoration: _decoration(
                    label: 'Current password',
                    icon: Icons.lock_outline_rounded,
                    hidden: hideCurrent,
                    onToggle: () => setState(() => hideCurrent = !hideCurrent),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: newController,
                  obscureText: hideNew,
                  enabled: !isSaving,
                  decoration: _decoration(
                    label: 'New password',
                    icon: Icons.lock_reset_rounded,
                    hidden: hideNew,
                    onToggle: () => setState(() => hideNew = !hideNew),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: confirmController,
                  obscureText: hideConfirm,
                  enabled: !isSaving,
                  onSubmitted: (_) => _changePassword(),
                  decoration: _decoration(
                    label: 'Confirm new password',
                    icon: Icons.verified_user_outlined,
                    hidden: hideConfirm,
                    onToggle: () => setState(() => hideConfirm = !hideConfirm),
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: isSaving ? null : _changePassword,
                    icon: isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_rounded),
                    label: Text(isSaving ? 'Updating...' : 'Change Password'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'The current Workora login system stores the password in the existing RTDB user record.',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
