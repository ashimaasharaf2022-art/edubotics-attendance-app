import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import '../utils/app_colors.dart';
import '../utils/session_manager.dart';
import '../utils/device_helper.dart';
import 'employee_shell.dart';
import 'admin_shell.dart';
import 'login_screens.dart';

class DeviceApprovalScreen extends StatefulWidget {
  final String employeeId;
  final String requestId;
  final String role;
  final String? employeeName;

  const DeviceApprovalScreen({
    super.key,
    required this.employeeId,
    required this.requestId,
    required this.role,
    this.employeeName,
  });

  @override
  State<DeviceApprovalScreen> createState() => _DeviceApprovalScreenState();
}

class _DeviceApprovalScreenState extends State<DeviceApprovalScreen> {
  late DatabaseReference dbRef;
  final _otpController = TextEditingController();

  String status = "pending";
  bool verifying = false;

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _listen();
  }

  void _listen() {
    dbRef
        .child("DeviceApprovalRequests")
        .child(widget.employeeId)
        .child(widget.requestId)
        .onValue
        .listen((event) {
      if (!mounted || event.snapshot.value == null) return;
      final data = Map<dynamic, dynamic>.from(event.snapshot.value as Map);
      setState(() => status = data["status"]?.toString() ?? "pending");
    });
  }

  Future<void> _verifyOtp() async {
    final entered = _otpController.text.trim();
    if (entered.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter the 6-digit code")));
      return;
    }

    setState(() => verifying = true);

    try {
      final snapshot = await dbRef
          .child("DeviceApprovalRequests")
          .child(widget.employeeId)
          .child(widget.requestId)
          .get();

      if (!snapshot.exists) {
        setState(() => verifying = false);
        return;
      }

      final data = Map<dynamic, dynamic>.from(snapshot.value as Map);
      final storedOtp = data["otpCode"]?.toString();
      final expiryStr = data["otpExpiry"]?.toString();

      if (storedOtp == null || expiryStr == null) {
        setState(() => verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("OTP not generated yet. Please wait for admin.")),
        );
        return;
      }

      final expiry = DateTime.tryParse(expiryStr);
      if (expiry == null || DateTime.now().isAfter(expiry)) {
        setState(() => verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("OTP expired. Ask admin to generate a new one.")),
        );
        return;
      }

      if (entered != storedOtp) {
        setState(() => verifying = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Incorrect OTP")));
        return;
      }

      // OTP correct — register this device and complete login.
      final currentDeviceId = await DeviceHelper.getDeviceId();
      await dbRef.child("users").child(widget.employeeId).update({
        "registeredDeviceId": currentDeviceId,
      });
      await dbRef
          .child("DeviceApprovalRequests")
          .child(widget.employeeId)
          .child(widget.requestId)
          .update({"status": "approved"});

      await SessionManager.saveSession(
        employeeId: widget.employeeId,
        role: widget.role,
        employeeName: widget.employeeName,
      );

      if (!mounted) return;

     if (widget.role == "superadmin") {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(
      builder: (_) => AdminShell(
        employeeId: widget.employeeId,
        employeeName: widget.employeeName,
        isSuperAdmin: true,
      ),
    ),
    (route) => false,
  );
} else {
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (_) => EmployeeShell(employeeId: widget.employeeId)),
    (route) => false,
  );
}
    } catch (e) {
      if (!mounted) return;
      setState(() => verifying = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final otpReady = status == "otp_ready";
    final rejected = status == "rejected";

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text("New Device Verification", style: TextStyle(color: Colors.white)),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              rejected ? Icons.block : (otpReady ? Icons.lock_open : Icons.hourglass_top),
              size: 60,
              color: rejected ? AppColors.danger : AppColors.primary,
            ),
            const SizedBox(height: 20),
            Text(
              rejected
                  ? "Request Rejected"
                  : (otpReady ? "Enter the OTP" : "Waiting for Admin Approval"),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              rejected
                  ? "This device login was rejected by the admin."
                  : (otpReady
                      ? "Enter the 6-digit code your admin gave you."
                      : "This is a new device. Ask your admin to check the app and generate an OTP for you."),
              style: const TextStyle(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 30),
            if (otpReady) ...[
              TextField(
                controller: _otpController,
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 24, letterSpacing: 8),
                decoration: InputDecoration(
                  counterText: "",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                  onPressed: verifying ? null : _verifyOtp,
                  child: verifying
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text("Verify & Login", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ] else if (!rejected) ...[
              const CircularProgressIndicator(color: AppColors.primary),
            ],
            const SizedBox(height: 20),
            TextButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
              child: const Text("Back to Login"),
            ),
          ],
        ),
      ),
    );
  }
}