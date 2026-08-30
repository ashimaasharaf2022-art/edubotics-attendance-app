import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../utils/app_colors.dart';
import '../utils/app_constants.dart';
import '../utils/session_manager.dart';
import '../utils/activity_logger.dart';
import 'change_password_screen.dart';
import 'manage_admins_screen.dart';
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
  final bool viewerIsAdmin;
  final bool viewerIsSuperAdmin;
  final String? viewerAdminId;
  final String? viewerAdminName;

  const ProfileScreen({
    super.key,
    required this.employeeId,
    this.viewOnly = false,
    this.isAdmin = false,
    this.isSuperAdmin = false,
    this.hasAdminAccess = false,
    this.viewerIsAdmin = false,
    this.viewerIsSuperAdmin = false,
    this.viewerAdminId,
    this.viewerAdminName,
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
  String? loggedInEmpId;
  bool loggedInUserIsAdmin = false;
  bool loggedInUserIsSuperAdmin = false;

  final _nameController = TextEditingController();
  final _designationController = TextEditingController();
  final _departmentController = TextEditingController();
  final _workLocationController = TextEditingController();
  final _workEmailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _personalEmailController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  String _dateOfJoining = "";
  String _employmentType = "Full-Time";
  String _bloodGroup = "O+";
  String _status = "active";
  bool _adminAccess = false;
  File? pickedPhotoFile;

  final List<String> _employmentTypes = ["Full-Time", "Part-Time", "Contract", "Intern", "Probation"];
  final List<String> _bloodGroups = ["A+", "A-", "B+", "B-", "O+", "O-", "AB+", "AB-", "Unknown"];

  @override
  void initState() {
    super.initState();
    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL: "https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app",
    ).ref();
    _initSessionAndLoad();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _designationController.dispose();
    _departmentController.dispose();
    _workLocationController.dispose();
    _workEmailController.dispose();
    _phoneController.dispose();
    _personalEmailController.dispose();
    _addressController.dispose();
    _emergencyContactController.dispose();
    super.dispose();
  }

  Future<void> _initSessionAndLoad() async {
    final empId = await SessionManager.getEmployeeId();
    final role = await SessionManager.getRole();
    if (mounted) {
      setState(() {
        loggedInEmpId = empId;
        loggedInUserIsSuperAdmin = widget.isSuperAdmin || widget.viewerIsSuperAdmin || (role?.toLowerCase() == "superadmin");
        loggedInUserIsAdmin = widget.isAdmin || widget.viewerIsAdmin || loggedInUserIsSuperAdmin || widget.hasAdminAccess || (role?.toLowerCase() == "admin");
      });
    }
    await _loadProfile();
    await _loadLanguage();
  }

  bool get _isViewingSelf => loggedInEmpId != null && loggedInEmpId == widget.employeeId;

  bool get _canEditCompanyDetails {
    if (widget.viewOnly && !loggedInUserIsAdmin) return false;
    return loggedInUserIsAdmin;
  }

  bool get _canEditPersonalDetails {
    if (widget.viewOnly && !loggedInUserIsAdmin) return false;
    return _isViewingSelf || loggedInUserIsAdmin;
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
      if (snapshot.exists && snapshot.value is Map) {
        profile = Map<dynamic, dynamic>.from(snapshot.value as Map);
        _populateControllers(profile);
      }
      setState(() => loading = false);
    } catch (_) {
      if (!mounted) return;
      setState(() => loading = false);
    }
  }

  void _populateControllers(Map<dynamic, dynamic> data) {
    _nameController.text = data["name"]?.toString() ?? "";
    _designationController.text = data["designation"]?.toString() ?? "";
    _departmentController.text = data["department"]?.toString() ?? "";
    _workLocationController.text = data["place"]?.toString() ?? data["workLocation"]?.toString() ?? "Edappally, Kochi";
    _workEmailController.text = data["email"]?.toString() ?? "";
    _phoneController.text = data["phone"]?.toString() ?? "";
    _personalEmailController.text = data["personalEmail"]?.toString() ?? "";
    _addressController.text = data["address"]?.toString() ?? "";
    _emergencyContactController.text = data["emergencyContact"]?.toString() ?? "";

    _dateOfJoining = data["dateOfJoining"]?.toString() ?? data["joiningDate"]?.toString() ?? "";
    _employmentType = data["employmentType"]?.toString() ?? "Full-Time";
    if (!_employmentTypes.contains(_employmentType)) _employmentType = _employmentTypes.first;

    _bloodGroup = data["bloodGroup"]?.toString() ?? "O+";
    if (!_bloodGroups.contains(_bloodGroup)) _bloodGroup = "Unknown";

    _status = (data["status"]?.toString() ?? "active").toLowerCase();
    _adminAccess = data["adminAccess"] == true;
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

    final picked = await ImagePicker().pickImage(source: source, maxWidth: 500, maxHeight: 500, imageQuality: 70);
    if (picked == null) return;
    setState(() => pickedPhotoFile = File(picked.path));
  }

  Future<void> _selectDateOfJoining() async {
    DateTime initial = DateTime.now();
    if (_dateOfJoining.isNotEmpty) {
      try {
        initial = DateFormat("dd MMM yyyy").parse(_dateOfJoining);
      } catch (_) {
        try {
          initial = DateTime.parse(_dateOfJoining);
        } catch (_) {}
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        _dateOfJoining = DateFormat("dd MMM yyyy").format(picked);
      });
    }
  }

  Future<void> _save() async {
    setState(() => saving = true);
    try {
      final updates = <String, dynamic>{};

      if (_canEditPersonalDetails) {
        updates["phone"] = _phoneController.text.trim();
        updates["personalEmail"] = _personalEmailController.text.trim();
        updates["address"] = _addressController.text.trim();
        updates["emergencyContact"] = _emergencyContactController.text.trim();
        updates["bloodGroup"] = _bloodGroup;
      }

      // Name is a personal field for the employee. Company-managed fields
      // remain editable only by an admin.
      if (_canEditPersonalDetails && _nameController.text.trim().isNotEmpty) {
        updates["name"] = _nameController.text.trim();
      }

      if (_canEditCompanyDetails) {
        updates["designation"] = _designationController.text.trim();
        updates["department"] = _departmentController.text.trim();
        updates["place"] = _workLocationController.text.trim();
        updates["workLocation"] = _workLocationController.text.trim();
        updates["email"] = _workEmailController.text.trim();
        updates["dateOfJoining"] = _dateOfJoining;
        updates["employmentType"] = _employmentType;
        updates["status"] = _status;
        updates["adminAccess"] = _adminAccess;
      }

      if (pickedPhotoFile != null) {
        final bytes = await pickedPhotoFile!.readAsBytes();
        updates["photoBase64"] = base64Encode(bytes);
      }

      await dbRef.child("users").child(widget.employeeId).update(updates);

      if (loggedInUserIsAdmin && widget.viewerAdminId != null) {
        await ActivityLogger.log(
          adminId: widget.viewerAdminId!,
          adminName: widget.viewerAdminName ?? "Admin",
          action: "Updated Employee Profile",
          details: "${_nameController.text.trim()} (${widget.employeeId})",
        );
      }

      if (!mounted) return;
      setState(() {
        profile = {...profile, ...updates};
        editing = false;
        saving = false;
        pickedPhotoFile = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profile updated successfully")));
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error updating profile: $e")));
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
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text("Logout", style: TextStyle(color: AppColors.danger))),
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
        Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: "Copy",
          onPressed: () {
            Clipboard.setData(ClipboardData(text: value));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied to clipboard")));
          },
        ),
      ],
    );
  }

  String get _initials {
    final name = profile["name"]?.toString() ?? widget.employeeId;
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(backgroundColor: AppColors.background, body: Center(child: CircularProgressIndicator()));
    }

    final photoBase64 = profile["photoBase64"]?.toString();
    final role = (profile["role"]?.toString() ?? "employee").toLowerCase();
    final isSuper = role == "superadmin";
    final isAdmin = role == "admin" || profile["adminAccess"] == true;
    final isActive = _status == "active";

    ImageProvider? avatarImage;
    if (pickedPhotoFile != null) {
      avatarImage = FileImage(pickedPhotoFile!);
    } else if (photoBase64 != null && photoBase64.isNotEmpty) {
      try {
        avatarImage = MemoryImage(base64Decode(photoBase64));
      } catch (_) {
        avatarImage = null;
      }
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.viewOnly || !_isViewingSelf ? "Employee Profile" : "My Profile"),
        actions: [
          if (_canEditPersonalDetails || _canEditCompanyDetails)
            IconButton(
              icon: Icon(editing ? Icons.check : Icons.edit),
              tooltip: editing ? "Save Changes" : "Edit Profile",
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
      body: SafeArea(
        child: saving
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadProfile,
                child: ListView(
                  padding: const EdgeInsets.only(bottom: 30),
                  children: [
                    _buildHeroHeader(avatarImage, isSuper, isAdmin, isActive),
                    const SizedBox(height: 16),
                    _buildCompanyInfoCard(),
                    const SizedBox(height: 16),
                    _buildPersonalInfoCard(),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeroHeader(ImageProvider? avatarImage, bool isSuper, bool isAdmin, bool isActive) {
    final name = profile["name"]?.toString() ?? widget.employeeId;
    final designation = _designationController.text.isNotEmpty ? _designationController.text : "Team Member";
    final department = _departmentController.text.isNotEmpty ? _departmentController.text : "Edubotics";

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
        boxShadow: AppShadows.hero,
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: editing ? _pickPhoto : null,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white24,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          _initials,
                          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, color: Colors.white),
                        )
                      : null,
                ),
                if (editing)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                      child: const Icon(Icons.camera_alt, size: 18, color: AppColors.primary),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (editing && _canEditPersonalDetails)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 55),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _nameController,
                  textAlign: TextAlign.center,
                  cursorColor: Colors.white,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                  decoration: const InputDecoration(
                    hintText: "Full Name",
                    hintStyle: TextStyle(
                      color: Colors.white70,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
            )
          else
            Text(
              name,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 4),
          Text(
            "$designation • $department",
            style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: [
              _badge("ID: ${widget.employeeId}", Colors.white.withOpacity(0.2)),
              if (isSuper)
                _badge("Super Admin", Colors.amber.withOpacity(0.3))
              else if (isAdmin)
                _badge("Admin", Colors.blue.withOpacity(0.3))
              else
                _badge("Employee", Colors.white.withOpacity(0.2)),
              _badge(isActive ? "Active" : "Inactive", isActive ? Colors.green.withOpacity(0.3) : Colors.red.withOpacity(0.3)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildCompanyInfoCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Row(
                  children: [
                    Icon(Icons.business_center_rounded, color: AppColors.primary, size: 20),
                    SizedBox(width: 8),
                    Text("Company Information", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ],
                ),
                if (!_canEditCompanyDetails)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: AppColors.background, borderRadius: BorderRadius.circular(10)),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 12, color: AppColors.textSecondary),
                        SizedBox(width: 4),
                        Text("Company Managed", style: TextStyle(fontSize: 10, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),
            _infoItem(
              icon: Icons.badge_outlined,
              label: "Employee ID",
              value: widget.employeeId,
              isEditable: false,
            ),
            _infoItem(
              icon: Icons.work_outline,
              label: "Designation",
              value: _designationController.text.isEmpty ? "Not Assigned" : _designationController.text,
              isEditable: editing && _canEditCompanyDetails,
              controller: _designationController,
              hint: "e.g. Flutter Developer, Manager",
            ),
            _infoItem(
              icon: Icons.apartment_outlined,
              label: "Department",
              value: _departmentController.text.isEmpty ? "General" : _departmentController.text,
              isEditable: editing && _canEditCompanyDetails,
              controller: _departmentController,
              hint: "e.g. Engineering, Sales, HR",
            ),
            if (editing && _canEditCompanyDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 18)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Date of Joining", style: TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(_dateOfJoining.isEmpty ? "Select Date" : _dateOfJoining, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        ],
                      ),
                    ),
                    OutlinedButton(
                      onPressed: _selectDateOfJoining,
                      child: const Text("Pick Date"),
                    ),
                  ],
                ),
              )
            else
              _infoItem(
                icon: Icons.calendar_today_outlined,
                label: "Date of Joining",
                value: _dateOfJoining.isEmpty ? "Not Specified" : _dateOfJoining,
                isEditable: false,
              ),
            if (editing && _canEditCompanyDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.access_time_outlined, color: AppColors.primary, size: 18)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text("Employment Type", style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                    DropdownButton<String>(
                      value: _employmentType,
                      underline: const SizedBox.shrink(),
                      items: _employmentTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                      onChanged: (v) => setState(() => _employmentType = v ?? _employmentType),
                    ),
                  ],
                ),
              )
            else
              _infoItem(
                icon: Icons.access_time_outlined,
                label: "Employment Type",
                value: _employmentType,
                isEditable: false,
              ),
            _infoItem(
              icon: Icons.location_on_outlined,
              label: "Work Location / Place",
              value: _workLocationController.text.isEmpty ? "Edappally, Kochi" : _workLocationController.text,
              isEditable: editing && _canEditCompanyDetails,
              controller: _workLocationController,
              hint: "e.g. Edappally, Kochi",
            ),
            _infoItem(
              icon: Icons.alternate_email,
              label: "Official Work Email",
              value: _workEmailController.text.isEmpty ? "Not Provided" : _workEmailController.text,
              isEditable: editing && _canEditCompanyDetails,
              controller: _workEmailController,
              hint: "name@company.com",
            ),
            if (_canEditCompanyDetails && editing)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text("Status Active", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(_status == "active" ? "User can sign in and log attendance" : "Account disabled", style: const TextStyle(fontSize: 11)),
                  value: _status == "active",
                  onChanged: (val) => setState(() => _status = val ? "active" : "inactive"),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(18), boxShadow: AppShadows.card),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_pin_circle_outlined, color: AppColors.indigo, size: 20),
                SizedBox(width: 8),
                Text("Personal & Contact Details", style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ],
            ),
            const Divider(height: 24),
            _infoItem(
              icon: Icons.phone_outlined,
              label: "Phone / Contact Number",
              value: _phoneController.text.isEmpty ? "Not Provided" : _phoneController.text,
              isEditable: editing && _canEditPersonalDetails,
              controller: _phoneController,
              hint: "+91 98765 43210",
              actionButton: _phoneController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.call, size: 18, color: AppColors.success),
                      onPressed: () => launchUrl(Uri.parse("tel:${_phoneController.text}")),
                    )
                  : null,
            ),
            _infoItem(
              icon: Icons.email_outlined,
              label: "Personal Email",
              value: _personalEmailController.text.isEmpty ? "Not Provided" : _personalEmailController.text,
              isEditable: editing && _canEditPersonalDetails,
              controller: _personalEmailController,
              hint: "personal@gmail.com",
            ),
            _infoItem(
              icon: Icons.home_outlined,
              label: "Residential Place / Address",
              value: _addressController.text.isEmpty ? "Not Provided" : _addressController.text,
              isEditable: editing && _canEditPersonalDetails,
              controller: _addressController,
              hint: "City, State",
            ),
            _infoItem(
              icon: Icons.contact_emergency_outlined,
              label: "Emergency Contact",
              value: _emergencyContactController.text.isEmpty ? "Not Provided" : _emergencyContactController.text,
              isEditable: editing && _canEditPersonalDetails,
              controller: _emergencyContactController,
              hint: "Name & Phone Number",
            ),
            if (editing && _canEditPersonalDetails)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.danger.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.favorite_outline, color: AppColors.danger, size: 18)),
                    const SizedBox(width: 12),
                    const Expanded(child: Text("Blood Group", style: TextStyle(color: AppColors.textSecondary, fontSize: 13))),
                    DropdownButton<String>(
                      value: _bloodGroup,
                      underline: const SizedBox.shrink(),
                      items: _bloodGroups.map((b) => DropdownMenuItem(value: b, child: Text(b, style: const TextStyle(fontWeight: FontWeight.bold)))).toList(),
                      onChanged: (v) => setState(() => _bloodGroup = v ?? _bloodGroup),
                    ),
                  ],
                ),
              )
            else
              _infoItem(
                icon: Icons.favorite_outline,
                label: "Blood Group",
                value: _bloodGroup,
                isEditable: false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _infoItem({
    required IconData icon,
    required String label,
    required String value,
    required bool isEditable,
    TextEditingController? controller,
    String? hint,
    Widget? actionButton,
  }) {
    if (isEditable && controller != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(icon, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.textPrimary),
                ),
              ],
            ),
          ),
          if (actionButton != null) actionButton,
        ],
      ),
    );
  }


}