import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:intl/intl.dart';
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
  final _designationController = TextEditingController();
  final _departmentController = TextEditingController();
  final _dojController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
  final _placeController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String _employmentType = "Full-time";
  final List<String> _employmentTypes = ["Full-time", "Part-time", "Contract", "Intern", "Probation"];

  bool obscurePassword = true;
  bool isSaving = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _dojController.dispose();
    _placeController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _showMessage(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _pickDateOfJoining() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2015),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _dojController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _save() async {
    final id = _idController.text.trim().toUpperCase();
    final name = _nameController.text.trim();
    final designation = _designationController.text.trim();
    final department = _departmentController.text.trim();
    final doj = _dojController.text.trim();
    final place = _placeController.text.trim();
    final email = _emailController.text.trim();
    final phone = _phoneController.text.trim();
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
        "designation": designation.isEmpty ? "Employee" : designation,
        "department": department.isEmpty ? "General" : department,
        "dateOfJoining": doj,
        "employmentType": _employmentType,
        "place": place,
        "workLocation": place,
        "email": email,
        "phone": phone,
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
        title: const Text("Add New Employee"),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader("Identification"),
            TextField(
              controller: _idController,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                labelText: "Employee ID *",
                hintText: "e.g. EMP001",
                prefixIcon: const Icon(Icons.badge_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: "Full Name *",
                hintText: "e.g. John Doe",
                prefixIcon: const Icon(Icons.person_outline),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader("Role & Company Details"),
            TextField(
              controller: _designationController,
              decoration: InputDecoration(
                labelText: "Designation / Position",
                hintText: "e.g. Senior Software Engineer",
                prefixIcon: const Icon(Icons.workspace_premium_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _departmentController,
              decoration: InputDecoration(
                labelText: "Department",
                hintText: "e.g. Engineering, Sales, HR",
                prefixIcon: const Icon(Icons.apartment_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _dojController,
                    readOnly: true,
                    onTap: _pickDateOfJoining,
                    decoration: InputDecoration(
                      labelText: "Date of Joining",
                      prefixIcon: const Icon(Icons.calendar_today_outlined),
                      suffixIcon: const Icon(Icons.edit_calendar, size: 18),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _employmentType,
                    decoration: InputDecoration(
                      labelText: "Type",
                      prefixIcon: const Icon(Icons.access_time_outlined),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: _employmentTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
                    onChanged: (val) => setState(() => _employmentType = val ?? _employmentType),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _placeController,
              decoration: InputDecoration(
                labelText: "Work Location / Place",
                hintText: "e.g. Kochi Office / Bangalore HQ",
                prefixIcon: const Icon(Icons.location_city_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader("Contact Information"),
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: InputDecoration(
                labelText: "Company Email",
                hintText: "e.g. employee@edubotics.com",
                prefixIcon: const Icon(Icons.email_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: "Phone Number",
                hintText: "e.g. +91 9876543210",
                prefixIcon: const Icon(Icons.phone_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            _buildSectionHeader("Account Credentials"),
            TextField(
              controller: _passwordController,
              obscureText: obscurePassword,
              decoration: InputDecoration(
                labelText: "Password *",
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
              "New employees start with standard employee access. You can grant admin rights from SuperAdmin settings if needed.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
            const SizedBox(height: 28),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 2,
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
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 4),
      child: Text(
        title.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: AppColors.textSecondary,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}