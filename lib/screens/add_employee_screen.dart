import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';

class AddEmployeeScreen extends StatefulWidget {
  const AddEmployeeScreen({super.key});

  @override
  State<AddEmployeeScreen> createState() => _AddEmployeeScreenState();
}

class _AddEmployeeScreenState extends State<AddEmployeeScreen> {
  late DatabaseReference dbRef;

  final _idController = TextEditingController();
  final _nameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _passwordController = TextEditingController();

  bool obscurePassword = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _save() async {
    final id = _idController.text.trim().toUpperCase();
    final name = _nameController.text.trim();
    final department = _departmentController.text.trim();
    final password = _passwordController.text.trim();

    if (id.isEmpty || name.isEmpty || password.isEmpty) {
      _showMessage("Please fill in Employee ID, Name and Password");
      return;
    }

    setState(() => isSaving = true);

    try {
      final userRef = dbRef.child("users").child(id);
      final existing = await userRef.get();
      if (existing.exists) {
        setState(() => isSaving = false);
        _showMessage("Employee ID '$id' already exists");
        return;
      }

      await userRef.set({
        "name": name,
        "role": "employee",
        "adminAccess": false,
        "status": "active",
        "department": department,
        "password": password,
      });

      if (!mounted) return;
      _showMessage("Employee added successfully");
      setState(() => isSaving = false);
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => isSaving = false);
      _showMessage("Error : $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("Add Employee", style: TextStyle(color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _idController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "Employee ID",
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Full Name",
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _departmentController,
              decoration: InputDecoration(
                labelText: "Department",
                prefixIcon: const Icon(Icons.apartment_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: "Password",
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(obscurePassword ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => obscurePassword = !obscurePassword),
                ),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              "New employees start with no admin access. Grant it later "
              "from Settings \u2192 Grant Admin Access if needed.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                ),
                onPressed: isSaving ? null : _save,
                child: isSaving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text(
                        "ADD EMPLOYEE",
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