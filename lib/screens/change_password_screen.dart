import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../utils/app_colors.dart';

class ChangePasswordScreen extends StatefulWidget {
  final String employeeId;

  const ChangePasswordScreen({super.key, required this.employeeId});

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();

  bool isSaving = false;
  bool obscureCurrent = true;
  bool obscureNew = true;
  bool obscureConfirm = true;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _submit() async {
    final current = _currentController.text.trim();
    final newPass = _newController.text.trim();
    final confirm = _confirmController.text.trim();

    if (current.isEmpty || newPass.isEmpty || confirm.isEmpty) {
      _showMessage("Please fill in all fields");
      return;
    }

    if (newPass.length < 6) {
      _showMessage("New password must be at least 6 characters");
      return;
    }

    if (newPass != confirm) {
      _showMessage("New password and confirmation do not match");
      return;
    }

    if (newPass == current) {
      _showMessage("New password must be different from current password");
      return;
    }

    setState(() => isSaving = true);

    try {
      final user = FirebaseAuth.instance.currentUser;
      final email = user?.email;
      if (user == null || email == null) {
        throw StateError('Please sign in again before changing your password.');
      }

      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: current),
      );
      await user.updatePassword(newPass);

      if (!mounted) return;
      setState(() => isSaving = false);
      _showMessage("Password changed successfully");
      Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        _showMessage('Current password is incorrect');
      } else if (e.code == 'requires-recent-login') {
        _showMessage('Please sign out and sign in again, then retry.');
      } else {
        _showMessage(e.message ?? 'Unable to change password.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      _showMessage("Error : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text(
          "Change Password",
          style: TextStyle(color: Colors.white),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _currentController,
              obscureText: obscureCurrent,
              decoration: InputDecoration(
                labelText: "Current Password",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscureCurrent ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscureCurrent = !obscureCurrent),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _newController,
              obscureText: obscureNew,
              decoration: InputDecoration(
                labelText: "New Password",
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(obscureNew ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscureNew = !obscureNew),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _confirmController,
              obscureText: obscureConfirm,
              decoration: InputDecoration(
                labelText: "Confirm New Password",
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(obscureConfirm ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscureConfirm = !obscureConfirm),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                onPressed: isSaving ? null : _submit,
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        "UPDATE PASSWORD",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
