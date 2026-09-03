import 'dart:convert';
import 'dart:typed_data';

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
import 'login_screens.dart';

/// Profile screen used for both:
/// 1. an employee viewing their own profile
/// 2. an admin/superadmin viewing an employee profile
///
/// Rules implemented here:
/// - Admin/superadmin can edit company information.
/// - Admin/superadmin can edit Employee ID, Name, Designation, joining date,
///   employment type, work location, official work email and account status.
/// - Admin/superadmin CANNOT edit profile picture or personal/contact details.
/// - Employee can edit their own personal/contact details and profile picture.
/// - Employee name is locked; only admin/superadmin can change it.
/// - Department has been removed and replaced by Designation.
/// - Changing Employee ID migrates the Firebase `users/<oldId>` record to
///   `users/<newId>` and updates the employeeId stored in that record.
/// - The screen does NOT create or require a Firebase Authentication user.
///   This app currently uses the Realtime Database user record for employee
///   profile data.
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
  late final DatabaseReference dbRef;

  bool loading = true;
  bool editing = false;
  bool saving = false;

  Map<String, dynamic> profile = <String, dynamic>{};

  String selectedLanguage = 'English (India)';
  String? loggedInEmpId;
  bool loggedInUserIsAdmin = false;
  bool loggedInUserIsSuperAdmin = false;

  final _nameController = TextEditingController();
  final _employeeIdController = TextEditingController();
  final _designationController = TextEditingController();
  final _workLocationController = TextEditingController();
  final _workEmailController = TextEditingController();

  final _phoneController = TextEditingController();
  final _personalEmailController = TextEditingController();
  final _addressController = TextEditingController();
  final _emergencyContactController = TextEditingController();

  String _currentEmployeeId = '';
  String _dateOfJoining = '';
  String _employmentType = 'Full-Time';
  String _bloodGroup = 'O+';
  String _status = 'active';

  Uint8List? pickedPhotoBytes;

  final List<String> _employmentTypes = <String>[
    'Full-Time',
    'Part-Time',
    'Contract',
    'Intern',
    'Probation',
  ];

  final List<String> _bloodGroups = <String>[
    'A+',
    'A-',
    'B+',
    'B-',
    'O+',
    'O-',
    'AB+',
    'AB-',
    'Unknown',
  ];

  String get _employeeId =>
      _currentEmployeeId.isEmpty ? widget.employeeId : _currentEmployeeId;

  bool get _isViewingSelf =>
      loggedInEmpId != null && loggedInEmpId == _employeeId;

  /// Only admin/superadmin can edit company information.
  bool get _canEditCompanyDetails {
    if (widget.viewOnly) return false;
    return loggedInUserIsAdmin;
  }

  /// Employees can edit their own personal/contact information.
  /// Admins are deliberately excluded when they are editing another
  /// employee's profile.
  bool get _canEditPersonalDetails {
    if (widget.viewOnly) return false;
    return _isViewingSelf && !loggedInUserIsAdmin;
  }

  /// Employee name is admin-managed.
  bool get _canEditName {
    if (widget.viewOnly) return false;
    return loggedInUserIsAdmin;
  }

  /// Profile picture is a personal detail. Admins cannot change it.
  bool get _canEditPhoto {
    if (widget.viewOnly) return false;
    return _isViewingSelf && !loggedInUserIsAdmin;
  }

  @override
  void initState() {
    super.initState();

    dbRef = FirebaseDatabase.instanceFor(
      app: Firebase.app(),
      databaseURL:
          'https://edubotics-attendance-default-rtdb.asia-southeast1.firebasedatabase.app',
    ).ref();

    _currentEmployeeId = widget.employeeId;
    _initSessionAndLoad();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _employeeIdController.dispose();
    _designationController.dispose();
    _workLocationController.dispose();
    _workEmailController.dispose();

    _phoneController.dispose();
    _personalEmailController.dispose();
    _addressController.dispose();
    _emergencyContactController.dispose();

    super.dispose();
  }

  Future<void> _initSessionAndLoad() async {
    try {
      final empId = await SessionManager.getEmployeeId();
      final role = await SessionManager.getRole();

      final normalizedRole = (role ?? '').trim().toLowerCase();
      final superAdmin =
          widget.isSuperAdmin ||
          widget.viewerIsSuperAdmin ||
          normalizedRole == 'superadmin';

      final admin =
          widget.isAdmin ||
          widget.viewerIsAdmin ||
          widget.hasAdminAccess ||
          superAdmin ||
          normalizedRole == 'admin';

      if (!mounted) return;

      setState(() {
        loggedInEmpId = empId;
        loggedInUserIsSuperAdmin = superAdmin;
        loggedInUserIsAdmin = admin;
      });

      await _loadProfile();
      await _loadLanguage();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _showMessage('Unable to load profile: $e');
    }
  }

  Future<void> _loadLanguage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;

      setState(() {
        selectedLanguage =
            prefs.getString('app_language') ?? 'English (India)';
      });
    } catch (_) {
      // Language is optional and must never stop the profile screen.
    }
  }

  Future<void> _loadProfile() async {
    if (mounted) {
      setState(() {
        loading = true;
      });
    }

    try {
      final snapshot =
          await dbRef.child('users').child(_employeeId).get();

      if (!snapshot.exists || snapshot.value == null) {
        if (!mounted) return;

        setState(() {
          profile = <String, dynamic>{
            'employeeId': _employeeId,
            'name': _employeeId,
          };
          _populateControllers(profile);
          loading = false;
        });

        return;
      }

      if (snapshot.value is! Map) {
        throw Exception('The users/$_employeeId record is not a map.');
      }

      final raw = Map<dynamic, dynamic>.from(snapshot.value as Map);
      final converted = <String, dynamic>{};

      raw.forEach((key, value) {
        converted[key.toString()] = value;
      });

      _populateControllers(converted);

      if (!mounted) return;

      setState(() {
        profile = converted;
        loading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        loading = false;
      });

      _showMessage('Error loading profile: $e');
    }
  }

  void _populateControllers(Map<String, dynamic> data) {
    final firebaseId =
        data['employeeId']?.toString().trim().isNotEmpty == true
            ? data['employeeId'].toString().trim()
            : _employeeId;

    _currentEmployeeId = firebaseId;

    _employeeIdController.text = firebaseId;
    _nameController.text = data['name']?.toString() ?? '';
    _designationController.text =
        data['designation']?.toString() ?? '';

    _workLocationController.text =
        data['place']?.toString() ??
        data['workLocation']?.toString() ??
        '';

    _workEmailController.text = data['email']?.toString() ?? '';

    _phoneController.text = data['phone']?.toString() ?? '';
    _personalEmailController.text =
        data['personalEmail']?.toString() ?? '';
    _addressController.text = data['address']?.toString() ?? '';
    _emergencyContactController.text =
        data['emergencyContact']?.toString() ?? '';

    _dateOfJoining =
        data['dateOfJoining']?.toString() ??
        data['joiningDate']?.toString() ??
        '';

    _employmentType =
        data['employmentType']?.toString() ?? 'Full-Time';

    if (!_employmentTypes.contains(_employmentType)) {
      _employmentType = _employmentTypes.first;
    }

    _bloodGroup = data['bloodGroup']?.toString() ?? 'O+';

    if (!_bloodGroups.contains(_bloodGroup)) {
      _bloodGroup = 'Unknown';
    }

    _status =
        (data['status']?.toString() ?? 'active').toLowerCase();

    _status = _status == 'inactive' ? 'inactive' : 'active';
  }

  Future<void> _pickPhoto() async {
    if (!_canEditPhoto) {
      _showMessage('Only the employee can change their profile picture.');
      return;
    }

    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.photo_camera),
                title: const Text('Take Photo'),
                onTap: () {
                  Navigator.pop(sheetContext, ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(sheetContext, ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );

    if (source == null) return;

    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 500,
      maxHeight: 500,
      imageQuality: 70,
    );

    if (picked == null || !mounted) return;

    // XFile.readAsBytes() works identically on mobile and web, unlike
    // dart:io.File which only works on mobile (picked.path is a blob:
    // URL on web, not a real filesystem path).
    final bytes = await picked.readAsBytes();

    if (!mounted) return;

    setState(() {
      pickedPhotoBytes = bytes;
    });
  }

  Future<void> _selectDateOfJoining() async {
    if (!_canEditCompanyDetails) return;

    DateTime initial = DateTime.now();

    if (_dateOfJoining.isNotEmpty) {
      try {
        initial = DateFormat('dd MMM yyyy').parse(_dateOfJoining);
      } catch (_) {
        try {
          initial = DateTime.parse(_dateOfJoining);
        } catch (_) {
          initial = DateTime.now();
        }
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _dateOfJoining = DateFormat('dd MMM yyyy').format(picked);
    });
  }

  Future<void> _save() async {
    if (saving) return;

    if (!_canEditCompanyDetails && !_canEditPersonalDetails) {
      _showMessage('You do not have permission to edit this profile.');
      return;
    }

    final newEmployeeId = _employeeIdController.text.trim();

    if (_canEditCompanyDetails) {
      if (newEmployeeId.isEmpty) {
        _showMessage('Employee ID cannot be empty.');
        return;
      }

      if (!_isValidFirebaseKey(newEmployeeId)) {
        _showMessage(
          'Employee ID contains invalid characters. Use letters, numbers, _ or -.',
        );
        return;
      }
    }

    setState(() {
      saving = true;
    });

    try {
      final oldEmployeeId = _employeeId;

      final updates = <String, dynamic>{};

      // Employee-owned personal information.
      if (_canEditPersonalDetails) {
        updates['phone'] = _phoneController.text.trim();
        updates['personalEmail'] =
            _personalEmailController.text.trim();
        updates['address'] = _addressController.text.trim();
        updates['emergencyContact'] =
            _emergencyContactController.text.trim();
        updates['bloodGroup'] = _bloodGroup;

        if (pickedPhotoBytes != null) {
          updates['photoBase64'] = base64Encode(pickedPhotoBytes!);
        }
      }

      // Admin-managed company information.
      if (_canEditCompanyDetails) {
        updates['employeeId'] = newEmployeeId;
        updates['name'] = _nameController.text.trim();
        updates['designation'] =
            _designationController.text.trim();
        updates['place'] = _workLocationController.text.trim();
        updates['workLocation'] =
            _workLocationController.text.trim();
        updates['email'] = _workEmailController.text.trim();
        updates['dateOfJoining'] = _dateOfJoining;
        updates['employmentType'] = _employmentType;
        updates['status'] = _status;

        // Keep the existing role/adminAccess values unless this profile
        // already contains them. We deliberately do not turn an employee
        // into an admin from this generic profile editor.
        if (profile.containsKey('adminAccess')) {
          updates['adminAccess'] = profile['adminAccess'];
        }
      }

      if (updates.isEmpty) {
        throw Exception('There are no changes to save.');
      }

      // If the admin changed the Employee ID, migrate the complete Firebase
      // users/<oldId> record to users/<newId>.
      if (_canEditCompanyDetails &&
          oldEmployeeId != newEmployeeId) {
        await _changeEmployeeId(
          oldEmployeeId: oldEmployeeId,
          newEmployeeId: newEmployeeId,
          updates: updates,
        );
      } else {
        await dbRef
            .child('users')
            .child(oldEmployeeId)
            .update(updates);
      }

      // Keep the local screen synchronized with Firebase.
      final finalSnapshot = await dbRef
          .child('users')
          .child(_canEditCompanyDetails ? newEmployeeId : oldEmployeeId)
          .get();

      if (finalSnapshot.exists && finalSnapshot.value is Map) {
        final raw = Map<dynamic, dynamic>.from(
          finalSnapshot.value as Map,
        );

        final newProfile = <String, dynamic>{};
        raw.forEach((key, value) {
          newProfile[key.toString()] = value;
        });

        _populateControllers(newProfile);

        if (mounted) {
          setState(() {
            profile = newProfile;
            _currentEmployeeId = _employeeIdController.text.trim();
            editing = false;
            pickedPhotoBytes = null;
            saving = false;
          });
        }
      } else {
        if (!mounted) return;

        setState(() {
          profile = <String, dynamic>{...profile, ...updates};
          _currentEmployeeId =
              _canEditCompanyDetails ? newEmployeeId : oldEmployeeId;
          editing = false;
          pickedPhotoBytes = null;
          saving = false;
        });
      }

      if (loggedInUserIsAdmin) {
        final adminId =
            widget.viewerAdminId ?? loggedInEmpId;

        if (adminId != null && adminId.isNotEmpty) {
          await ActivityLogger.log(
            adminId: adminId,
            adminName: widget.viewerAdminName ?? 'Admin',
            action: 'Updated Employee Profile',
            details:
                '${_nameController.text.trim()} ($_employeeId)',
          );
        }
      }

      if (!mounted) return;

      _showMessage('Profile updated successfully.');
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      _showMessage('Error updating profile: $e');
    }
  }

  Future<void> _changeEmployeeId({
    required String oldEmployeeId,
    required String newEmployeeId,
    required Map<String, dynamic> updates,
  }) async {
    final oldRef = dbRef.child('users').child(oldEmployeeId);
    final newRef = dbRef.child('users').child(newEmployeeId);

    final existingNew = await newRef.get();

    if (existingNew.exists) {
      throw Exception(
        'Employee ID $newEmployeeId already exists. Choose another ID.',
      );
    }

    final oldSnapshot = await oldRef.get();

    if (!oldSnapshot.exists || oldSnapshot.value is! Map) {
      throw Exception(
        'Could not find the existing employee record $oldEmployeeId.',
      );
    }

    final oldData = Map<dynamic, dynamic>.from(
      oldSnapshot.value as Map,
    );

    final migrated = <String, dynamic>{};

    oldData.forEach((key, value) {
      migrated[key.toString()] = value;
    });

    migrated.addAll(updates);
    migrated['employeeId'] = newEmployeeId;

    // Write the new record first. This prevents losing the employee if the
    // old record is removed after a successful write.
    await newRef.set(migrated);

    try {
      await oldRef.remove();
    } catch (e) {
      // Roll back the newly created record if deletion of the old record
      // failed, so two employee records are not accidentally left behind.
      await newRef.remove();
      rethrow;
    }

    _currentEmployeeId = newEmployeeId;
  }

  bool _isValidFirebaseKey(String value) {
    // Realtime Database keys cannot contain . # $ [ ] /.
    return !RegExp(r'[.#$\[\]/]').hasMatch(value);
  }

  Future<void> _adminResetPassword() async {
    if (!loggedInUserIsAdmin) return;

    final passCtrl = TextEditingController();
    bool obscure = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return AlertDialog(
              title: const Text('Reset Employee Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'Set a new password for '
                    '${profile['name'] ?? _employeeId}:',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: passCtrl,
                    obscureText: obscure,
                    decoration: InputDecoration(
                      labelText: 'New Password',
                      prefixIcon:
                          const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          obscure
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setModalState(() {
                            obscure = !obscure;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (passCtrl.text.trim().length < 4) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password must be at least 4 characters.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(dialogContext, true);
                  },
                  child: const Text('Set Password'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || passCtrl.text.trim().isEmpty) {
      passCtrl.dispose();
      return;
    }

    try {
      await dbRef
          .child('users')
          .child(_employeeId)
          .update({
        'password': passCtrl.text.trim(),
      });

      if (!mounted) return;

      _showMessage('Password reset successfully.');
    } catch (e) {
      if (!mounted) return;

      _showMessage('Unable to reset password: $e');
    } finally {
      passCtrl.dispose();
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Logout'),
          content:
              const Text('Are you sure you want to logout?'),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, true),
              child: const Text(
                'Logout',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await SessionManager.clearSession();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
      ),
      (_) => false,
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: AppConstants.appName,
      applicationVersion: AppConstants.appVersion,
      applicationLegalese:
          '© ${DateTime.now().year} ${AppConstants.companyName}',
    );
  }

  void _showContactHR() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Contact HR / Support'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: <Widget>[
              _contactRow(
                Icons.phone,
                AppConstants.hrPhone,
              ),
              const SizedBox(height: 12),
              _contactRow(
                Icons.email,
                AppConstants.hrEmail,
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _contactRow(IconData icon, String value) {
    return Row(
      children: <Widget>[
        Icon(
          icon,
          size: 20,
          color: AppColors.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            value,
            style:
                const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.copy, size: 18),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(
              ClipboardData(text: value),
            );
            _showMessage('Copied to clipboard.');
          },
        ),
      ],
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message)),
      );
  }

  String get _initials {
    final name =
        profile['name']?.toString() ?? _employeeId;

    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();

    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts.first.substring(0, 1).toUpperCase();
    }

    return (
      parts[0].substring(0, 1) +
      parts[1].substring(0, 1)
    ).toUpperCase();
  }

  ImageProvider<Object>? _getAvatarImage() {
    if (pickedPhotoBytes != null) {
      return MemoryImage(pickedPhotoBytes!);
    }

    final photoBase64 =
        profile['photoBase64']?.toString();

    if (photoBase64 == null || photoBase64.isEmpty) {
      return null;
    }

    try {
      return MemoryImage(base64Decode(photoBase64));
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    final role =
        (profile['role']?.toString() ?? 'employee')
            .trim()
            .toLowerCase();

    final isSuper = role == 'superadmin';

    final isAdmin =
        role == 'admin' && profile['adminAccess'] == true;

    final isActive = _status == 'active';

    return PopScope(
      canPop: true,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            _isViewingSelf
                ? 'My Profile'
                : 'Employee Profile',
          ),
          actions: <Widget>[
            if (_canEditCompanyDetails ||
                _canEditPersonalDetails)
              IconButton(
                icon: Icon(
                  editing
                      ? Icons.check
                      : Icons.edit_outlined,
                ),
                tooltip:
                    editing ? 'Save Changes' : 'Edit Profile',
                onPressed: saving
                    ? null
                    : () {
                        if (editing) {
                          _save();
                        } else {
                          setState(() {
                            editing = true;
                          });
                        }
                      },
              ),
          ],
        ),
        body: SafeArea(
          child: saving
              ? const Center(
                  child: CircularProgressIndicator(),
                )
              : RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: ListView(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding:
                        const EdgeInsets.only(bottom: 30),
                    children: <Widget>[
                      _buildHeroHeader(
                        _getAvatarImage(),
                        isSuper,
                        isAdmin,
                        isActive,
                      ),
                      const SizedBox(height: 16),
                      _buildCompanyInfoCard(),
                      const SizedBox(height: 16),
                      _buildPersonalInfoCard(),
                      const SizedBox(height: 16),
                      _buildActionSections(
                        isSuper,
                        isAdmin,
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }

  Widget _buildHeroHeader(
    ImageProvider<Object>? avatarImage,
    bool isSuper,
    bool isAdmin,
    bool isActive,
  ) {
    final name =
        profile['name']?.toString() ?? _employeeId;

    final designation =
        _designationController.text.trim().isNotEmpty
            ? _designationController.text.trim()
            : 'Team Member';

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(20, 20, 20, 24),
      decoration: BoxDecoration(
        gradient: AppGradients.brand,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(28),
        ),
        boxShadow: AppShadows.hero,
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            onTap: editing && _canEditPhoto
                ? _pickPhoto
                : null,
            child: Stack(
              children: <Widget>[
                CircleAvatar(
                  radius: 46,
                  backgroundColor: Colors.white24,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          _initials,
                          style: const TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                          ),
                        )
                      : null,
                ),
                if (editing && _canEditPhoto)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration:
                          const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Only an admin/superadmin can change the employee name.
          if (editing && _canEditName)
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 35),
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
                  hintText: 'Full Name',
                  hintStyle: TextStyle(
                    color: Colors.white70,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
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
            designation,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: <Widget>[
              _badge(
                'ID: $_employeeId',
                Colors.white.withValues(alpha: 0.20),
              ),
              if (isSuper)
                _badge(
                  'Super Admin',
                  Colors.amber.withValues(alpha: 0.30),
                )
              else if (isAdmin)
                _badge(
                  'Admin',
                  Colors.blue.withValues(alpha: 0.30),
                )
              else
                _badge(
                  'Employee',
                  Colors.white.withValues(alpha: 0.20),
                ),
              _badge(
                isActive ? 'Active' : 'Inactive',
                isActive
                    ? Colors.green.withValues(alpha: 0.30)
                    : Colors.red.withValues(alpha: 0.30),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(String text, Color bg) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCompanyInfoCard() {
    final canEdit = editing && _canEditCompanyDetails;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment:
                  MainAxisAlignment.spaceBetween,
              children: <Widget>[
                const Row(
                  children: <Widget>[
                    Icon(
                      Icons.business_center_rounded,
                      color: AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Company Information',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                if (!canEdit)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius:
                          BorderRadius.circular(10),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons.lock_outline,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Company Managed',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(height: 24),

            // Employee ID — editable only by admin/superadmin.
            if (canEdit)
              _editableTextItem(
                icon: Icons.badge_outlined,
                label: 'Employee ID',
                controller: _employeeIdController,
                hint: 'e.g. EMP001',
              )
            else
              _infoItem(
                icon: Icons.badge_outlined,
                label: 'Employee ID',
                value: _employeeId,
                isEditable: false,
              ),

            // Designation replaces Department.
            _infoItem(
              icon: Icons.work_outline,
              label: 'Designation',
              value:
                  _designationController.text.trim().isEmpty
                      ? 'Not Assigned'
                      : _designationController.text.trim(),
              isEditable: canEdit,
              controller: _designationController,
              hint: 'e.g. Software Engineer, Manager',
            ),

            if (canEdit)
              _buildDatePickerRow()
            else
              _infoItem(
                icon: Icons.calendar_today_outlined,
                label: 'Date of Joining',
                value: _dateOfJoining.isEmpty
                    ? 'Not Specified'
                    : _dateOfJoining,
                isEditable: false,
              ),

            if (canEdit)
              _buildEmploymentTypeRow()
            else
              _infoItem(
                icon: Icons.access_time_outlined,
                label: 'Employment Type',
                value: _employmentType,
                isEditable: false,
              ),

            _infoItem(
              icon: Icons.location_on_outlined,
              label: 'Work Location / Place',
              value:
                  _workLocationController.text.trim().isEmpty
                      ? 'Not Provided'
                      : _workLocationController.text.trim(),
              isEditable: canEdit,
              controller: _workLocationController,
              hint: 'e.g. Edappally, Kochi',
            ),

            _infoItem(
              icon: Icons.alternate_email,
              label: 'Official Work Email',
              value:
                  _workEmailController.text.trim().isEmpty
                      ? 'Not Provided'
                      : _workEmailController.text.trim(),
              isEditable: canEdit,
              controller: _workEmailController,
              hint: 'name@company.com',
            ),

            if (canEdit)
              Padding(
                padding:
                    const EdgeInsets.only(top: 4),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Status Active',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  subtitle: Text(
                    _status == 'active'
                        ? 'User can sign in and log attendance'
                        : 'Account disabled',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: _status == 'active',
                  onChanged: (value) {
                    setState(() {
                      _status =
                          value ? 'active' : 'inactive';
                    });
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildDatePickerRow() {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  AppColors.primary.withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.calendar_today_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Date of Joining',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _dateOfJoining.isEmpty
                      ? 'Select Date'
                      : _dateOfJoining,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed: _selectDateOfJoining,
            child: const Text('Pick Date'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmploymentTypeRow() {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  AppColors.primary.withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.access_time_outlined,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Employment Type',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _employmentType,
            underline: const SizedBox.shrink(),
            items: _employmentTypes
                .map(
                  (type) => DropdownMenuItem<String>(
                    value: type,
                    child: Text(
                      type,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                _employmentType = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    final canEdit = editing && _canEditPersonalDetails;

    return Padding(
      padding:
          const EdgeInsets.symmetric(horizontal: 18),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons.person_pin_circle_outlined,
                  color: AppColors.indigo,
                  size: 20,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Personal & Contact Details',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!canEdit)
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
              ],
            ),
            const Divider(height: 24),

            _infoItem(
              icon: Icons.phone_outlined,
              label: 'Phone / Contact Number',
              value:
                  _phoneController.text.trim().isEmpty
                      ? 'Not Provided'
                      : _phoneController.text.trim(),
              isEditable: canEdit,
              controller: _phoneController,
              hint: '+91 98765 43210',
              actionButton:
                  !canEdit &&
                          _phoneController.text
                              .trim()
                              .isNotEmpty
                      ? IconButton(
                          icon: const Icon(
                            Icons.call,
                            size: 18,
                            color: AppColors.success,
                          ),
                          onPressed: () {
                            launchUrl(
                              Uri.parse(
                                'tel:${_phoneController.text.trim()}',
                              ),
                            );
                          },
                        )
                      : null,
            ),

            _infoItem(
              icon: Icons.email_outlined,
              label: 'Personal Email',
              value:
                  _personalEmailController.text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _personalEmailController.text.trim(),
              isEditable: canEdit,
              controller: _personalEmailController,
              hint: 'personal@gmail.com',
            ),

            _infoItem(
              icon: Icons.home_outlined,
              label: 'Residential Place / Address',
              value:
                  _addressController.text.trim().isEmpty
                      ? 'Not Provided'
                      : _addressController.text.trim(),
              isEditable: canEdit,
              controller: _addressController,
              hint: 'City, State',
            ),

            _infoItem(
              icon: Icons.contact_emergency_outlined,
              label: 'Emergency Contact',
              value:
                  _emergencyContactController.text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _emergencyContactController.text.trim(),
              isEditable: canEdit,
              controller: _emergencyContactController,
              hint: 'Name & Phone Number',
            ),

            if (canEdit)
              _buildBloodGroupRow()
            else
              _infoItem(
                icon: Icons.favorite_outline,
                label: 'Blood Group',
                value: _bloodGroup,
                isEditable: false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodGroupRow() {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  AppColors.danger.withValues(alpha: 0.10),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.favorite_outline,
              color: AppColors.danger,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Blood Group',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          DropdownButton<String>(
            value: _bloodGroup,
            underline: const SizedBox.shrink(),
            items: _bloodGroups
                .map(
                  (blood) => DropdownMenuItem<String>(
                    value: blood,
                    child: Text(
                      blood,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;

              setState(() {
                _bloodGroup = value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _editableTextItem({
    required IconData icon,
    required String label,
    required TextEditingController controller,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textCapitalization:
            TextCapitalization.sentences,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(12),
          ),
          contentPadding:
              const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
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
      return _editableTextItem(
        icon: icon,
        label: label,
        controller: controller,
        hint: hint,
      );
    }

    return Padding(
      padding:
          const EdgeInsets.only(bottom: 14),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color:
                  AppColors.primary.withValues(alpha: 0.08),
              borderRadius:
                  BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          if (actionButton != null) actionButton,
        ],
      ),
    );
  }

  Widget _buildActionSections(
    bool isSuper,
    bool isAdmin,
  ) {
    // Admin management actions section is no longer shown on this screen.
    return const SizedBox.shrink();
  }

  Widget _section(
    String title,
    List<Widget> tiles,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(18, 8, 18, 4),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  BorderRadius.circular(16),
              boxShadow: AppShadows.card,
            ),
            child: Column(children: tiles),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String title,
    VoidCallback onTap,
  ) {
    return ListTile(
      leading: Icon(
        icon,
        color: AppColors.primary,
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 14,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 20,
        color: AppColors.textSecondary,
      ),
      onTap: onTap,
    );
  }
}