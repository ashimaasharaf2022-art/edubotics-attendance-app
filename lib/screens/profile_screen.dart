import 'dart:convert';

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
import '../utils/workora_app_settings.dart';
import 'login_screens.dart';

/// Profile screen used for both:
/// 1. an employee viewing their own profile
/// 2. an admin/superadmin viewing an employee profile
///
/// Rules implemented here:
/// - Admin/HR/Super Admin can edit company information.
/// - Admin/HR/Super Admin can edit Employee ID, Name, Designation, joining date,
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
  final VoidCallback? onSwitchToMyDashboard;
  final VoidCallback? onSwitchToAdminPanel;

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
    this.onSwitchToMyDashboard,
    this.onSwitchToAdminPanel,
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
  bool loggedInUserIsHr = false;

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

  /// True only when the currently logged-in user is a Super Admin.
  ///
  /// Super Admin has a completely separate dashboard/profile and therefore
  /// must never see the employee/admin panel switching actions.
  bool get _isSuperAdmin {
    return loggedInUserIsSuperAdmin;
  }

  /// Admin, HR and Super Admin can edit management-controlled work details.
  bool get _canEditCompanyDetails {
    if (widget.viewOnly) return false;
    return loggedInUserIsAdmin || loggedInUserIsSuperAdmin || loggedInUserIsHr;
  }

  /// Personal details can be edited on the employee's own profile.
  /// Management can also edit an employee's personal details.
  bool get _canEditPersonalDetails {
    if (widget.viewOnly) return false;
    return _isViewingSelf || _canEditCompanyDetails;
  }

  /// Employee name and Employee ID are management-controlled.
  bool get _canEditName {
    if (widget.viewOnly) return false;
    return _canEditCompanyDetails;
  }

  /// Profile picture is employee-owned and can only be changed by the
  /// employee viewing their own profile.
  bool get _canEditPhoto {
    if (widget.viewOnly) return false;
    return _isViewingSelf;
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

      final hr = <String>{
        'hr',
        'humanresources',
        'human_resources',
        'human-resources',
        'human resources',
      }.contains(normalizedRole);

      final superAdmin =
          widget.isSuperAdmin ||
          widget.viewerIsSuperAdmin ||
          normalizedRole == 'superadmin';

      // IMPORTANT: `hasAdminAccess` only controls whether an employee
      // can switch to the Admin Panel. It must NOT grant permission to
      // edit work/company details while the employee is still on the
      // Employee Dashboard/Profile. Work details can be edited only when
      // this ProfileScreen is opened from the actual Admin/HR/Superadmin
      // management context.
      final admin =
          widget.isAdmin ||
          widget.viewerIsAdmin ||
          superAdmin ||
          normalizedRole == 'admin';

      if (!mounted) return;

      setState(() {
        loggedInEmpId = empId;
        loggedInUserIsSuperAdmin = superAdmin;
        loggedInUserIsHr = hr;
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
        throw Exception(
          'The users/$_employeeId record is not a map.',
        );
      }

      final raw = Map<dynamic, dynamic>.from(
        snapshot.value as Map,
      );

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

    _nameController.text =
        data['name']?.toString() ?? '';

    _designationController.text =
        data['designation']?.toString() ?? '';

    _workLocationController.text =
        data['place']?.toString() ??
        data['workLocation']?.toString() ??
        '';

    _workEmailController.text =
        data['email']?.toString() ?? '';

    _phoneController.text =
        data['phone']?.toString() ?? '';

    _personalEmailController.text =
        data['personalEmail']?.toString() ?? '';

    _addressController.text =
        data['address']?.toString() ?? '';

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

    _bloodGroup =
        data['bloodGroup']?.toString() ?? 'O+';

    if (!_bloodGroups.contains(_bloodGroup)) {
      _bloodGroup = 'Unknown';
    }

    _status =
        (data['status']?.toString() ?? 'active').toLowerCase();

    _status = _status == 'inactive' ? 'inactive' : 'active';
  }

  Future<void> _pickPhoto() async {
    if (!_canEditPhoto) {
      _showMessage(
        'Only the employee can change their profile picture.',
      );
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
                  Navigator.pop(
                    sheetContext,
                    ImageSource.camera,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.pop(
                    sheetContext,
                    ImageSource.gallery,
                  );
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

    final bytes = await picked.readAsBytes();

    if (!mounted) return;

    setState(() {
      pickedPhotoBytes = bytes;
    });

    try {
      await dbRef.child('users').child(_employeeId).update({
        'photoBase64': base64Encode(bytes),
      });
      if (!mounted) return;
      setState(() {
        profile['photoBase64'] = base64Encode(bytes);
        pickedPhotoBytes = null;
      });
      _showMessage('Profile picture updated successfully.');
    } catch (e) {
      if (!mounted) return;
      _showMessage('Unable to update profile picture: $e');
    }
  }

  Future<void> _selectDateOfJoining() async {
    if (!_canEditCompanyDetails) return;

    DateTime initial = DateTime.now();

    if (_dateOfJoining.isNotEmpty) {
      try {
        initial =
            DateFormat('dd MMM yyyy').parse(_dateOfJoining);
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
      lastDate: DateTime.now().add(
        const Duration(days: 365),
      ),
    );

    if (picked == null || !mounted) return;

    setState(() {
      _dateOfJoining =
          DateFormat('dd MMM yyyy').format(picked);
    });
  }

  Future<void> _save() async {
    if (saving) return;

    if (!_canEditCompanyDetails &&
        !_canEditPersonalDetails) {
      _showMessage(
        'You do not have permission to edit this profile.',
      );
      return;
    }

    final newEmployeeId =
        _employeeIdController.text.trim();

    if (_canEditCompanyDetails) {
      if (newEmployeeId.isEmpty) {
        _showMessage('Employee ID cannot be empty.');
        return;
      }

      if (!_isValidFirebaseKey(newEmployeeId)) {
        _showMessage(
          'Employee ID contains invalid characters. '
          'Use letters, numbers, _ or -.',
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
        updates['phone'] =
            _phoneController.text.trim();

        updates['personalEmail'] =
            _personalEmailController.text.trim();

        updates['address'] =
            _addressController.text.trim();

        updates['emergencyContact'] =
            _emergencyContactController.text.trim();

        updates['bloodGroup'] = _bloodGroup;

        if (pickedPhotoBytes != null) {
          updates['photoBase64'] =
              base64Encode(pickedPhotoBytes!);
        }
      }

      // Admin-managed company information.
      if (_canEditCompanyDetails) {
        updates['employeeId'] = newEmployeeId;
        updates['name'] =
            _nameController.text.trim();

        updates['designation'] =
            _designationController.text.trim();

        updates['place'] =
            _workLocationController.text.trim();

        updates['workLocation'] =
            _workLocationController.text.trim();

        updates['email'] =
            _workEmailController.text.trim();

        updates['dateOfJoining'] =
            _dateOfJoining;

        updates['employmentType'] =
            _employmentType;

        updates['status'] = _status;

        // Keep the existing role/adminAccess values unless
        // this profile already contains them.
        if (profile.containsKey('adminAccess')) {
          updates['adminAccess'] =
              profile['adminAccess'];
        }
      }

      if (updates.isEmpty) {
        throw Exception(
          'There are no changes to save.',
        );
      }

      // If the admin changed the Employee ID, migrate the
      // complete Firebase users/<oldId> record to
      // users/<newId>.
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
          .child(
            _canEditCompanyDetails
                ? newEmployeeId
                : oldEmployeeId,
          )
          .get();

      if (finalSnapshot.exists &&
          finalSnapshot.value is Map) {
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
            _currentEmployeeId =
                _employeeIdController.text.trim();
            editing = false;
            pickedPhotoBytes = null;
            saving = false;
          });
        }
      } else {
        if (!mounted) return;

        setState(() {
          profile = <String, dynamic>{
            ...profile,
            ...updates,
          };

          _currentEmployeeId =
              _canEditCompanyDetails
                  ? newEmployeeId
                  : oldEmployeeId;

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
            adminName:
                widget.viewerAdminName ?? 'Admin',
            action: 'Updated Employee Profile',
            details:
                '${_nameController.text.trim()} ($_employeeId)',
          );
        }
      }

      if (!mounted) return;

      _showMessage(
        'Profile updated successfully.',
      );
    } catch (e) {
      if (!mounted) return;

      setState(() {
        saving = false;
      });

      _showMessage(
        'Error updating profile: $e',
      );
    }
  }

  Future<void> _changeEmployeeId({
    required String oldEmployeeId,
    required String newEmployeeId,
    required Map<String, dynamic> updates,
  }) async {
    final oldRef =
        dbRef.child('users').child(oldEmployeeId);

    final newRef =
        dbRef.child('users').child(newEmployeeId);

    final existingNew =
        await newRef.get();

    if (existingNew.exists) {
      throw Exception(
        'Employee ID $newEmployeeId already exists. '
        'Choose another ID.',
      );
    }

    final oldSnapshot =
        await oldRef.get();

    if (!oldSnapshot.exists ||
        oldSnapshot.value is! Map) {
      throw Exception(
        'Could not find the existing employee '
        'record $oldEmployeeId.',
      );
    }

    final oldData =
        Map<dynamic, dynamic>.from(
      oldSnapshot.value as Map,
    );

    final migrated =
        <String, dynamic>{};

    oldData.forEach((key, value) {
      migrated[key.toString()] = value;
    });

    migrated.addAll(updates);
    migrated['employeeId'] =
        newEmployeeId;

    // Write the new record first.
    await newRef.set(migrated);

    try {
      await oldRef.remove();
    } catch (e) {
      // Roll back the newly created record if
      // deletion of the old record failed.
      await newRef.remove();
      rethrow;
    }

    _currentEmployeeId =
        newEmployeeId;
  }

  bool _isValidFirebaseKey(String value) {
    // Realtime Database keys cannot contain
    // . # $ [ ] /
    return !RegExp(
      r'[.#$\[\]/]',
    ).hasMatch(value);
  }

  Future<void> _adminResetPassword() async {
    if (!loggedInUserIsAdmin) return;

    final passCtrl =
        TextEditingController();

    bool obscure = true;

    final confirmed =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setModalState) {
            return AlertDialog(
              title: const Text(
                'Reset Employee Password',
              ),
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
                          const Icon(
                        Icons.lock_outline,
                      ),
                      suffixIcon:
                          IconButton(
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
                      border:
                          OutlineInputBorder(
                        borderRadius:
                            BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
              actions: <Widget>[
                TextButton(
                  onPressed: () =>
                      Navigator.pop(
                    dialogContext,
                    false,
                  ),
                  child:
                      const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (passCtrl.text
                            .trim()
                            .length <
                        4) {
                      ScaffoldMessenger
                              .of(context)
                          .showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Password must be at least 4 characters.',
                          ),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      dialogContext,
                      true,
                    );
                  },
                  child:
                      const Text(
                    'Set Password',
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true ||
        passCtrl.text.trim().isEmpty) {
      passCtrl.dispose();
      return;
    }

    try {
      await dbRef
          .child('users')
          .child(_employeeId)
          .update({
        'password':
            passCtrl.text.trim(),
      });

      if (!mounted) return;

      _showMessage(
        'Password reset successfully.',
      );
    } catch (e) {
      if (!mounted) return;

      _showMessage(
        'Unable to reset password: $e',
      );
    } finally {
      passCtrl.dispose();
    }
  }

  Future<void> _logout() async {
    final confirm =
        await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title:
              const Text('Logout'),
          content:
              const Text(
            'Are you sure you want to logout?',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                dialogContext,
                false,
              ),
              child:
                  const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pop(
                dialogContext,
                true,
              ),
              child: const Text(
                'Logout',
                style: TextStyle(
                  color:
                      AppColors.danger,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirm != true) return;

    await SessionManager.clearSession();

    if (!mounted) return;

    Navigator.of(context)
        .pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) =>
            const LoginScreen(),
      ),
      (_) => false,
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName:
          AppConstants.appName,
      applicationVersion:
          AppConstants.appVersion,
      applicationLegalese:
          '© ${DateTime.now().year} '
          '${AppConstants.companyName}',
    );
  }

  void _showContactHR() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text(
            'Contact HR / Support',
          ),
          content: Column(
            mainAxisSize:
                MainAxisSize.min,
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
                  Navigator.pop(
                dialogContext,
              ),
              child:
                  const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _contactRow(
    IconData icon,
    String value,
  ) {
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
                const TextStyle(
              fontWeight:
                  FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          icon: const Icon(
            Icons.copy,
            size: 18,
          ),
          tooltip: 'Copy',
          onPressed: () {
            Clipboard.setData(
              ClipboardData(
                text: value,
              ),
            );

            _showMessage(
              'Copied to clipboard.',
            );
          },
        ),
      ],
    );
  }

  void _showMessage(
    String message,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content:
              Text(message),
        ),
      );
  }

  String get _initials {
    final name =
        profile['name']?.toString() ??
            _employeeId;

    final parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where(
          (part) =>
              part.isNotEmpty,
        )
        .toList();

    if (parts.isEmpty) return '?';

    if (parts.length == 1) {
      return parts.first
          .substring(0, 1)
          .toUpperCase();
    }

    return (
      parts[0]
          .substring(0, 1) +
      parts[1]
          .substring(0, 1)
    ).toUpperCase();
  }

  ImageProvider<Object>?
      _getAvatarImage() {
    if (pickedPhotoBytes != null) {
      return MemoryImage(
        pickedPhotoBytes!,
      );
    }

    final photoBase64 =
        profile['photoBase64']
            ?.toString();

    if (photoBase64 == null ||
        photoBase64.isEmpty) {
      return null;
    }

    try {
      return MemoryImage(
        base64Decode(
          photoBase64,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        backgroundColor: AppColors.background,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final avatarImage = _getAvatarImage();
    final name = profile['name']?.toString().trim().isNotEmpty == true
        ? profile['name'].toString().trim()
        : _employeeId;
    final designation = _designationController.text.trim().isEmpty
        ? 'Team Member'
        : _designationController.text.trim();
    final department = profile['department']?.toString().trim().isNotEmpty == true
        ? profile['department'].toString().trim()
        : 'Not specified';
    final reportingManager = profile['reportingManager']?.toString().trim().isNotEmpty == true
        ? profile['reportingManager'].toString().trim()
        : (profile['managerName']?.toString().trim().isNotEmpty == true
            ? profile['managerName'].toString().trim()
            : 'Not specified');
    final workLocation = _workLocationController.text.trim().isEmpty
        ? 'Not specified'
        : _workLocationController.text.trim();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final contentWidth = constraints.maxWidth > 520
                ? 520.0
                : constraints.maxWidth;

            return Center(
              child: SizedBox(
                width: contentWidth,
                child: RefreshIndicator(
                  onRefresh: _loadProfile,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Center(
                          child: Text(
                            'Profile',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 22),
                        _buildProfileIdentity(
                          name: name,
                          designation: designation,
                          avatarImage: avatarImage,
                        ),
                        const SizedBox(height: 28),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _profileSectionTitle('PERSONAL PROFILE'),
                            if (_canEditPersonalDetails)
                              TextButton.icon(
                                onPressed: saving ? null : _openPersonalEditScreen,
                                icon: const Icon(Icons.edit_rounded, size: 17),
                                label: const Text('Edit'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildProfileInfoCard([
                          _profileInfoRow(
                            'Phone',
                            _phoneController.text.trim().isEmpty
                                ? 'Not provided'
                                : _phoneController.text.trim(),
                            Icons.phone_outlined,
                          ),
                          _profileInfoRow(
                            'Personal email',
                            _personalEmailController.text.trim().isEmpty
                                ? 'Not provided'
                                : _personalEmailController.text.trim(),
                            Icons.mail_outline_rounded,
                          ),
                          _profileInfoRow(
                            'Address',
                            _addressController.text.trim().isEmpty
                                ? 'Not provided'
                                : _addressController.text.trim(),
                            Icons.location_on_outlined,
                          ),
                          _profileInfoRow(
                            'Emergency contact',
                            _emergencyContactController.text.trim().isEmpty
                                ? 'Not provided'
                                : _emergencyContactController.text.trim(),
                            Icons.phone_in_talk_outlined,
                            isLast: true,
                          ),
                        ]),

                        const SizedBox(height: 26),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            _profileSectionTitle('WORK PROFILE'),
                            if (_canEditCompanyDetails)
                              TextButton.icon(
                                onPressed: saving ? null : _openWorkEditScreen,
                                icon: const Icon(Icons.edit_rounded, size: 17),
                                label: const Text('Edit'),
                                style: TextButton.styleFrom(
                                  foregroundColor: AppColors.primary,
                                  padding: const EdgeInsets.symmetric(horizontal: 4),
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildProfileInfoCard([
                          _profileInfoRow(
                            'Employee ID',
                            _employeeId,
                            Icons.badge_outlined,
                          ),
                          _profileInfoRow(
                            'Department',
                            department,
                            Icons.account_tree_outlined,
                          ),
                          _profileInfoRow(
                            'Designation',
                            designation,
                            Icons.business_center_outlined,
                          ),
                          _profileInfoRow(
                            'Reporting manager',
                            reportingManager,
                            Icons.groups_outlined,
                          ),
                          _profileInfoRow(
                            'Date of joining',
                            _formatJoiningDate(_dateOfJoining),
                            Icons.calendar_month_outlined,
                          ),
                          _profileInfoRow(
                            'Work location',
                            workLocation,
                            Icons.location_on_outlined,
                            isLast: true,
                          ),
                        ]),
                        const SizedBox(height: 14),
                        _buildAssignedAssetsSection(),
                        const SizedBox(height: 8),
                        const Center(
                          child: Text(
                            'Managed by HR — contact support to update',
                            style: TextStyle(
                              fontSize: 9,
                              color: AppColors.mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                        _profileSectionTitle('SUPPORT & PREFERENCES'),
                        const SizedBox(height: 8),
                        _buildSettingsCard(),
                        const SizedBox(height: 14),
                        _buildLogoutButton(),
                        const SizedBox(height: 12),
                        Center(
                          child: Text(
                            'Workora v1.0 · Build 2026.09.14',
                            style: const TextStyle(
                              fontSize: 9,
                              color: AppColors.mutedText,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildProfileTopBar() {
    return Row(
      children: [
        Image.asset(
          'assets/images/workora_logo.png',
          width: 25,
          height: 25,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Icon(Icons.eco_rounded, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 6),
        Image.asset(
          'assets/images/workora_text.png',
          width: 68,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text(
            'workora',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: AppColors.primary),
          ),
        ),
        const Spacer(),
        const Text(
          'HRMS',
          style: TextStyle(
            fontSize: 8,
            letterSpacing: 1.1,
            color: AppColors.mutedText,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(width: 8),
        InkWell(
          onTap: () {},
          borderRadius: BorderRadius.circular(22),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.divider),
            ),
            child: const Icon(Icons.dark_mode_outlined, size: 17, color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileIdentity({
    required String name,
    required String designation,
    required ImageProvider<Object>? avatarImage,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: _canEditPhoto ? _pickPhoto : null,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFFFFB88B),
                  border: Border.all(color: Colors.white, width: 4),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  backgroundColor: Colors.transparent,
                  backgroundImage: avatarImage,
                  child: avatarImage == null
                      ? Text(
                          _initials,
                          style: const TextStyle(
                            color: Color(0xFF7C3F20),
                            fontSize: 38,
                            fontWeight: FontWeight.w800,
                          ),
                        )
                      : null,
                ),
              ),
              if (_canEditPhoto)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.camera_alt_rounded,
                      color: Colors.white,
                      size: 17,
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          name,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          designation,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: AppColors.divider),
          ),
          child: Text(
            'Employee ID: $_employeeId',
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.mutedText,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Widget _profileSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 10,
          letterSpacing: .8,
          color: AppColors.mutedText,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildProfileInfoCard(List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(children: rows),
    );
  }

  Widget _profileInfoRow(
    String label,
    String value,
    IconData icon, {
    bool isLast = false,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: isLast
            ? null
            : const Border(
                bottom: BorderSide(
                  color: AppColors.divider,
                  width: .7,
                ),
              ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.mutedText,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatJoiningDate(String raw) {
    if (raw.trim().isEmpty) return 'Not specified';
    try {
      final parsed = DateTime.parse(raw);
      return DateFormat('d MMM yyyy').format(parsed);
    } catch (_) {
      return raw;
    }
  }

  List<Map<String, dynamic>> _getAssignedAssets() {
    final raw = profile['assets'];
    if (raw is! Map) return <Map<String, dynamic>>[];

    final assets = <Map<String, dynamic>>[];
    raw.forEach((key, value) {
      if (value is Map) {
        final asset = <String, dynamic>{};
        value.forEach((assetKey, assetValue) {
          asset[assetKey.toString()] = assetValue;
        });
        asset['_key'] = key.toString();
        assets.add(asset);
      }
    });
    return assets;
  }

  String _assetValue(Map<String, dynamic> asset, String key,
      [String fallback = 'Not specified']) {
    final value = asset[key];
    if (value == null || value.toString().trim().isEmpty) return fallback;
    return value.toString().trim();
  }

  IconData _assetIcon(String type) {
    switch (type.toLowerCase()) {
      case 'laptop':
      case 'computer':
        return Icons.laptop_mac_rounded;
      case 'desktop':
        return Icons.desktop_windows_rounded;
      case 'mobile':
      case 'phone':
        return Icons.phone_android_rounded;
      case 'tablet':
        return Icons.tablet_android_rounded;
      case 'monitor':
        return Icons.monitor_rounded;
      case 'keyboard':
        return Icons.keyboard_rounded;
      case 'mouse':
        return Icons.mouse_rounded;
      case 'headset':
        return Icons.headset_mic_rounded;
      case 'id card':
      case 'id card / badge':
        return Icons.badge_rounded;
      default:
        return Icons.inventory_2_outlined;
    }
  }

  Widget _buildAssignedAssetsSection() {
    final assets = _getAssignedAssets();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _profileSectionTitle('ASSIGNED ASSETS'),
            if (_canEditCompanyDetails)
              TextButton.icon(
                onPressed: saving ? null : () => _showAssetEditor(),
                icon: const Icon(Icons.add_rounded, size: 17),
                label: const Text('Add'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (assets.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(17),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: .08),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Icon(
                    Icons.inventory_2_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'No company assets assigned.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.mutedText,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            children: [
              for (int i = 0; i < assets.length; i++) ...[
                _buildAssetCard(assets[i]),
                if (i != assets.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildAssetCard(Map<String, dynamic> asset) {
    final type = _assetValue(asset, 'type', 'Asset');
    final name = _assetValue(asset, 'name', 'Unnamed asset');
    final assetId = _assetValue(asset, 'assetId');
    final serial = _assetValue(asset, 'serialNumber');
    final assignedDate = _assetValue(asset, 'assignedDate');
    final status = _assetValue(asset, 'status', 'Assigned');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _assetIcon(type),
              color: AppColors.primary,
              size: 21,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        status,
                        style: const TextStyle(
                          fontSize: 8,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  type,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 5,
                  children: [
                    if (assetId != 'Not specified')
                      _assetMeta('Asset ID', assetId),
                    if (serial != 'Not specified')
                      _assetMeta('Serial No.', serial),
                    if (assignedDate != 'Not specified')
                      _assetMeta(
                        'Assigned',
                        _formatJoiningDate(assignedDate),
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (_canEditCompanyDetails)
            PopupMenuButton<String>(
              icon: const Icon(
                Icons.more_vert_rounded,
                size: 19,
                color: AppColors.mutedText,
              ),
              padding: EdgeInsets.zero,
              onSelected: (value) {
                if (value == 'edit') {
                  _showAssetEditor(asset: asset);
                } else if (value == 'delete') {
                  _removeAsset(asset);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text('Edit asset'),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('Remove asset'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _assetMeta(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(
          fontSize: 9,
          color: AppColors.mutedText,
        ),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          TextSpan(
            text: value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssetEditor({Map<String, dynamic>? asset}) async {
    if (!_canEditCompanyDetails) return;

    final typeController = TextEditingController(
      text: _assetValue(asset ?? <String, dynamic>{}, 'type', 'Laptop'),
    );
    final nameController = TextEditingController(
      text: _assetValue(asset ?? <String, dynamic>{}, 'name', ''),
    );
    final assetIdController = TextEditingController(
      text: _assetValue(asset ?? <String, dynamic>{}, 'assetId', ''),
    );
    final serialController = TextEditingController(
      text: _assetValue(asset ?? <String, dynamic>{}, 'serialNumber', ''),
    );
    final dateController = TextEditingController(
      text: _assetValue(
        asset ?? <String, dynamic>{},
        'assignedDate',
        DateFormat('yyyy-MM-dd').format(DateTime.now()),
      ),
    );
    final notesController = TextEditingController(
      text: _assetValue(asset ?? <String, dynamic>{}, 'notes', ''),
    );
    String status = _assetValue(
      asset ?? <String, dynamic>{},
      'status',
      'Assigned',
    );
    bool savingAsset = false;

    try {
      final result = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (_, setDialogState) {
              return AlertDialog(
                title: Text(
                  asset == null ? 'Add Asset' : 'Edit Asset',
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _assetDialogField(
                        typeController,
                        'Asset type',
                        Icons.category_outlined,
                      ),
                      _assetDialogField(
                        nameController,
                        'Asset name / model',
                        Icons.inventory_2_outlined,
                      ),
                      _assetDialogField(
                        assetIdController,
                        'Asset ID',
                        Icons.qr_code_2_rounded,
                      ),
                      _assetDialogField(
                        serialController,
                        'Serial number',
                        Icons.numbers_rounded,
                      ),
                      _assetDialogField(
                        dateController,
                        'Assigned date (YYYY-MM-DD)',
                        Icons.calendar_today_outlined,
                      ),
                      DropdownButtonFormField<String>(
                        value: const ['Assigned', 'Returned', 'Repair', 'Lost']
                                .contains(status)
                            ? status
                            : 'Assigned',
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          prefixIcon: Icon(Icons.info_outline_rounded),
                        ),
                        items: const [
                          'Assigned',
                          'Returned',
                          'Repair',
                          'Lost',
                        ].map((value) {
                          return DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          );
                        }).toList(),
                        onChanged: savingAsset
                            ? null
                            : (value) {
                                if (value != null) {
                                  setDialogState(() => status = value);
                                }
                              },
                      ),
                      const SizedBox(height: 12),
                      _assetDialogField(
                        notesController,
                        'Notes (optional)',
                        Icons.notes_rounded,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: savingAsset
                        ? null
                        : () => Navigator.of(dialogContext).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: savingAsset
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            if (name.isEmpty) {
                              _showDialogMessage(
                                dialogContext,
                                'Asset name / model is required.',
                              );
                              return;
                            }

                            setDialogState(() => savingAsset = true);

                            try {
                              final assetsRef = dbRef
                                  .child('users')
                                  .child(_employeeId)
                                  .child('assets');
                              final key = asset?['_key']?.toString() ??
                                  assetsRef.push().key;

                              if (key == null || key.isEmpty) {
                                throw Exception('Could not create asset ID.');
                              }

                              await assetsRef.child(key).set({
                                'type': typeController.text.trim().isEmpty
                                    ? 'Asset'
                                    : typeController.text.trim(),
                                'name': name,
                                'assetId': assetIdController.text.trim(),
                                'serialNumber': serialController.text.trim(),
                                'assignedDate': dateController.text.trim(),
                                'status': status,
                                'notes': notesController.text.trim(),
                                'updatedAt': ServerValue.timestamp,
                              });

                              if (!mounted) return;
                              Navigator.of(dialogContext).pop(true);
                            } catch (e) {
                              setDialogState(() => savingAsset = false);
                              _showDialogMessage(
                                dialogContext,
                                'Could not save asset: $e',
                              );
                            }
                          },
                    child: Text(asset == null ? 'Add Asset' : 'Save Changes'),
                  ),
                ],
              );
            },
          );
        },
      );

      if (result == true && mounted) {
        await _loadProfile();
        _showMessage(
          asset == null
              ? 'Asset added successfully.'
              : 'Asset updated successfully.',
        );
      }
    } finally {
      typeController.dispose();
      nameController.dispose();
      assetIdController.dispose();
      serialController.dispose();
      dateController.dispose();
      notesController.dispose();
    }
  }

  Widget _assetDialogField(
    TextEditingController controller,
    String label,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }

  void _showDialogMessage(BuildContext dialogContext, String message) {
    ScaffoldMessenger.of(dialogContext).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _removeAsset(Map<String, dynamic> asset) async {
    if (!_canEditCompanyDetails) return;

    final key = asset['_key']?.toString();
    if (key == null || key.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Remove asset?'),
          content: Text(
            'Remove ${_assetValue(asset, 'name', 'this asset')} from this employee?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    try {
      await dbRef
          .child('users')
          .child(_employeeId)
          .child('assets')
          .child(key)
          .remove();

      await _loadProfile();
      if (mounted) {
        _showMessage('Asset removed successfully.');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Could not remove asset: $e');
      }
    }
  }

  Future<void> _openPersonalEditScreen() async {
    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => _PersonalDetailsEditScreen(
          phone: _phoneController.text,
          personalEmail: _personalEmailController.text,
          address: _addressController.text,
          emergencyContact: _emergencyContactController.text,
          bloodGroup: _bloodGroup,
        ),
      ),
    );

    if (result == null || !mounted) return;
    await _savePersonalDetails(result);
  }

  Future<void> _openWorkEditScreen() async {
    if (!_canEditCompanyDetails) return;

    final result = await Navigator.of(context).push<Map<String, String>>(
      MaterialPageRoute(
        builder: (_) => _WorkDetailsEditScreen(
          employeeId: _employeeIdController.text,
          name: _nameController.text,
          designation: _designationController.text,
          workLocation: _workLocationController.text,
          officialEmail: _workEmailController.text,
          dateOfJoining: _dateOfJoining,
          employmentType: _employmentType,
        ),
      ),
    );

    if (result == null || !mounted) return;
    await _saveWorkDetails(result);
  }

  Future<void> _savePersonalDetails(Map<String, String> values) async {
    if (saving) return;

    setState(() => saving = true);
    try {
      await dbRef.child('users').child(_employeeId).update({
        'phone': values['phone'] ?? '',
        'personalEmail': values['personalEmail'] ?? '',
        'address': values['address'] ?? '',
        'emergencyContact': values['emergencyContact'] ?? '',
        'bloodGroup': values['bloodGroup'] ?? _bloodGroup,
      });

      await _loadProfile();
      if (!mounted) return;
      setState(() => saving = false);
      _showMessage('Personal details updated successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      _showMessage('Error updating personal details: $e');
    }
  }

  Future<void> _saveWorkDetails(Map<String, String> values) async {
    if (saving || !_canEditCompanyDetails) return;

    final newEmployeeId = (values['employeeId'] ?? '').trim();
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

    setState(() => saving = true);
    try {
      final oldEmployeeId = _employeeId;
      final updates = <String, dynamic>{
        'employeeId': newEmployeeId,
        'name': (values['name'] ?? '').trim(),
        'designation': (values['designation'] ?? '').trim(),
        'place': (values['workLocation'] ?? '').trim(),
        'workLocation': (values['workLocation'] ?? '').trim(),
        'email': (values['officialEmail'] ?? '').trim(),
        'dateOfJoining': values['dateOfJoining'] ?? '',
        'employmentType': values['employmentType'] ?? _employmentType,
      };

      if (profile.containsKey('status')) {
        updates['status'] = profile['status'];
      }
      if (profile.containsKey('adminAccess')) {
        updates['adminAccess'] = profile['adminAccess'];
      }

      if (oldEmployeeId != newEmployeeId) {
        await _changeEmployeeId(
          oldEmployeeId: oldEmployeeId,
          newEmployeeId: newEmployeeId,
          updates: updates,
        );
      } else {
        await dbRef.child('users').child(oldEmployeeId).update(updates);
      }

      await _loadProfile();

      final adminId = widget.viewerAdminId ?? loggedInEmpId;
      if (adminId != null && adminId.isNotEmpty) {
        await ActivityLogger.log(
          adminId: adminId,
          adminName: widget.viewerAdminName ?? 'Admin',
          action: 'Updated Employee Work Profile',
          details: '${_nameController.text.trim()} ($_employeeId)',
        );
      }

      if (!mounted) return;
      setState(() => saving = false);
      _showMessage('Work details updated successfully.');
    } catch (e) {
      if (!mounted) return;
      setState(() => saving = false);
      _showMessage('Error updating work details: $e');
    }
  }

  Widget _buildEditPanel() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.greenBorder),
      ),
      child: Column(
        children: [
          if (_canEditPersonalDetails) ...[
            _compactEditField('Phone', _phoneController),
            _compactEditField('Personal email', _personalEmailController),
            _compactEditField('Address', _addressController),
            _compactEditField('Emergency contact', _emergencyContactController),
          ],
          if (_canEditCompanyDetails) ...[
            _compactEditField('Employee ID', _employeeIdController),
            _compactEditField('Name', _nameController),
            _compactEditField('Designation', _designationController),
            _compactEditField('Work location', _workLocationController),
            _compactEditField('Official email', _workEmailController),
          ],
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: FilledButton(
              onPressed: saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compactEditField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: TextField(
        controller: controller,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(fontSize: 10),
          filled: true,
          fillColor: AppColors.background,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: AppColors.divider)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: AppColors.divider)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(11), borderSide: BorderSide(color: AppColors.green)),
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        children: [
          _settingsRow(
            icon: Icons.headset_mic_outlined,
            iconBg: AppColors.veryLightGreen,
            iconColor: AppColors.primary,
            title: 'Contact HR / Support',
            subtitle: 'Call, email or chat',
            onTap: _showContactHRSheet,
          ),
          _settingsRow(
            icon: Icons.notifications_none_rounded,
            iconBg: AppColors.warningLight,
            iconColor: AppColors.warning,
            title: 'Notification settings',
            subtitle: 'Push, email & alerts',
            onTap: _showNotificationSettingsSheet,
          ),
          _settingsRow(
            icon: Icons.language_rounded,
            iconBg: AppColors.veryLightGreen,
            iconColor: AppColors.green,
            title: 'Language',
            subtitle: selectedLanguage == 'English (India)' ? 'English' : selectedLanguage,
            onTap: _showLanguageSheet,
          ),
          _settingsRow(
            icon: Icons.info_outline_rounded,
            iconBg: AppColors.infoLight,
            iconColor: AppColors.info,
            title: 'About app',
            subtitle: 'Version, terms & policies',
            onTap: _showAboutSheet,
            isLast: true,
          ),
        ],
      ),
    );
  }

  Widget _settingsRow({
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isLast = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.vertical(
        top: title == 'Contact HR / Support' ? const Radius.circular(17) : Radius.zero,
        bottom: isLast ? const Radius.circular(17) : Radius.zero,
      ),
      child: Container(
        constraints: const BoxConstraints(minHeight: 59),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: isLast
            ? null
            : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: .7))),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, size: 17, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 9, color: AppColors.mutedText)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.mutedText),
          ],
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      height: 42,
      child: TextButton.icon(
        onPressed: _showLogoutSheet,
        style: TextButton.styleFrom(
          backgroundColor: AppColors.dangerLight,
          foregroundColor: AppColors.danger,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
        icon: const Icon(Icons.logout_rounded, size: 16),
        label: const Text('Log out', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
      ),
    );
  }

  Widget _buildAdminAccessRow() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.mutedText.withValues(alpha: .55), style: BorderStyle.solid),
      ),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              'This employee has admin access',
              style: TextStyle(fontSize: 9, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
            ),
          ),
          OutlinedButton(
            onPressed: widget.onSwitchToAdminPanel,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.green),
              minimumSize: const Size(58, 28),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w800),
            ),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
  }

  Future<void> _showContactHRSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (_) => _ProfileBottomSheet(
        title: 'Contact HR / Support',
        subtitle: 'Mon–Fri, 9 AM – 6 PM IST',
        child: Column(
          children: [
            _contactAction('Call HR desk', AppConstants.hrPhone, Icons.headset_mic_outlined, () async {
              final uri = Uri(scheme: 'tel', path: AppConstants.hrPhone);
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            }),
            const SizedBox(height: 8),
            _contactAction('Email HR', AppConstants.hrEmail, Icons.mail_outline_rounded, () async {
              final uri = Uri(scheme: 'mailto', path: AppConstants.hrEmail);
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            }),
            const SizedBox(height: 8),
            _contactAction('Chat with support', 'Typically replies in minutes', Icons.chat_bubble_outline_rounded, () {
              Navigator.pop(context);
              _showMessage('Support chat will be available here.');
            }),
          ],
        ),
      ),
    );
  }

  Widget _contactAction(String title, String subtitle, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.divider),
        ),
        child: Row(
          children: [
            Container(
              width: 31,
              height: 31,
              decoration: BoxDecoration(color: AppColors.veryLightGreen, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: AppColors.primary, size: 16),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(fontSize: 9, color: AppColors.mutedText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showNotificationSettingsSheet() async {
    final prefs = await SharedPreferences.getInstance();
    bool push = prefs.getBool('notify_push') ?? true;
    bool email = prefs.getBool('notify_email') ?? true;
    bool attendance = prefs.getBool('notify_attendance') ?? true;
    bool leave = prefs.getBool('notify_leave_ticket') ?? true;
    bool announcements = prefs.getBool('notify_announcements') ?? false;

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          Future<void> setValue(String key, bool value) async {
            await prefs.setBool(key, value);
          }

          return _ProfileBottomSheet(
            title: 'Notification settings',
            subtitle: "Choose what you'd like to be notified about.",
            child: Column(
              children: [
                _notificationToggle('Push notifications', 'On this device', push, (v) async { setSheetState(() => push = v); await setValue('notify_push', v); }),
                _notificationToggle('Email notifications', 'Daily summaries & approvals', email, (v) async { setSheetState(() => email = v); await setValue('notify_email', v); }),
                _notificationToggle('Attendance reminders', 'If you forget to check in/out', attendance, (v) async { setSheetState(() => attendance = v); await setValue('notify_attendance', v); }),
                _notificationToggle('Leave & ticket updates', 'Status changes on your requests', leave, (v) async { setSheetState(() => leave = v); await setValue('notify_leave_ticket', v); }),
                _notificationToggle('Announcements', 'Company-wide updates', announcements, (v) async { setSheetState(() => announcements = v); await setValue('notify_announcements', v); }, isLast: true),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _notificationToggle(String title, String subtitle, bool value, ValueChanged<bool> onChanged, {bool isLast = false}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 55),
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: isLast ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: .7))),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(fontSize: 9, color: AppColors.mutedText)),
              ],
            ),
          ),
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: AppColors.green,
            activeThumbColor: Colors.white,
          ),
        ],
      ),
    );
  }

  Future<void> _showLanguageSheet() async {
    final prefs = await SharedPreferences.getInstance();
    String language = prefs.getString('app_language') ?? 'English (India)';

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => _ProfileBottomSheet(
          title: 'Language',
          subtitle: 'Applies across the app.',
          child: Column(
            children: [
              _languageChoice('English', 'English', 'English (India)', language, (v) async { setSheetState(() => language = v); await WorkoraAppSettings.setLanguage(v); if (mounted) setState(() => selectedLanguage = v); }),
              _languageChoice('Malayalam', 'മലയാളം', 'Malayalam', language, (v) async { setSheetState(() => language = v); await WorkoraAppSettings.setLanguage(v); if (mounted) setState(() => selectedLanguage = v); }),
              _languageChoice('Hindi', 'हिन्दी', 'Hindi', language, (v) async { setSheetState(() => language = v); await WorkoraAppSettings.setLanguage(v); if (mounted) setState(() => selectedLanguage = v); }),
              _languageChoice('Tamil', 'தமிழ்', 'Tamil', language, (v) async { setSheetState(() => language = v); await WorkoraAppSettings.setLanguage(v); if (mounted) setState(() => selectedLanguage = v); }, isLast: true),
            ],
          ),
        ),
      ),
    );
  }

  Widget _languageChoice(String title, String native, String value, String selected, ValueChanged<String> onChanged, {bool isLast = false}) {
    final active = value == selected;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        constraints: const BoxConstraints(minHeight: 57),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: isLast ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: .7))),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(native, style: const TextStyle(fontSize: 9, color: AppColors.mutedText)),
                ],
              ),
            ),
            Container(
              width: 17,
              height: 17,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: active ? AppColors.green : AppColors.divider, width: 1.2),
              ),
              child: active
                  ? Center(child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppColors.green, shape: BoxShape.circle)))
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAboutSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (_) => _ProfileBottomSheet(
        title: 'About Workora',
        subtitle: 'HRMS by Edubotics, a division of Hindustan Group.',
        child: Column(
          children: [
            _aboutRow('App version', AppConstants.appVersion, null),
            _aboutRow('Build', '2026.09.14', null),
            _aboutRow('Terms of service', 'View', () => _showMessage('Terms of service will be available here.')),
            _aboutRow('Privacy policy', 'View', () => _showMessage('Privacy policy will be available here.')),
            _aboutRow('Send feedback', 'Open', () async {
              final uri = Uri(scheme: 'mailto', path: AppConstants.hrEmail, queryParameters: {'subject': 'Workora feedback'});
              if (await canLaunchUrl(uri)) await launchUrl(uri);
            }, isLast: true),
          ],
        ),
      ),
    );
  }

  Widget _aboutRow(String label, String value, VoidCallback? onTap, {bool isLast = false}) {
    final child = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: isLast ? null : const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.divider, width: .7))),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 10, color: AppColors.textPrimary, fontWeight: FontWeight.w700)),
        ],
      ),
    );
    return onTap == null ? child : InkWell(onTap: onTap, child: child);
  }

  Future<void> _showLogoutSheet() async {
    final shouldLogout = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .45),
      builder: (_) => _ProfileBottomSheet(
        title: 'Log out of Workora?',
        subtitle: "You'll need to sign in again to check in, view payslips, or request leave.",
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.divider),
                  backgroundColor: AppColors.background,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                child: const Text('Cancel', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 42),
                  backgroundColor: AppColors.danger,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                ),
                child: const Text('Log out', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );

    if (shouldLogout == true) {
      await _performLogout();
    }
  }

  Future<void> _performLogout() async {
    await SessionManager.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Widget _buildHeroHeader(
    ImageProvider<Object>?
        avatarImage,
    bool isSuper,
    bool isAdmin,
    bool isActive,
  ) {
    final name =
        profile['name']?.toString() ??
            _employeeId;

    final designation =
        _designationController
                .text
                .trim()
                .isNotEmpty
            ? _designationController
                .text
                .trim()
            : 'Team Member';

    return Container(
      width: double.infinity,
      padding:
          const EdgeInsets.fromLTRB(
        20,
        20,
        20,
        24,
      ),
      decoration: BoxDecoration(
        gradient:
            AppGradients.brand,
        borderRadius:
            const BorderRadius.vertical(
          bottom:
              Radius.circular(28),
        ),
        boxShadow:
            AppShadows.hero,
      ),
      child: Column(
        children: <Widget>[
          GestureDetector(
            onTap:
                editing &&
                        _canEditPhoto
                    ? _pickPhoto
                    : null,
            child: Stack(
              children: <Widget>[
                CircleAvatar(
                  radius: 46,
                  backgroundColor:
                      Colors.white24,
                  backgroundImage:
                      avatarImage,
                  child:
                      avatarImage ==
                              null
                          ? Text(
                              _initials,
                              style:
                                  const TextStyle(
                                fontSize:
                                    30,
                                fontWeight:
                                    FontWeight.w800,
                                color:
                                    Colors.white,
                              ),
                            )
                          : null,
                ),
                if (editing &&
                    _canEditPhoto)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding:
                          const EdgeInsets.all(
                        6,
                      ),
                      decoration:
                          const BoxDecoration(
                        color:
                            Colors.white,
                        shape:
                            BoxShape.circle,
                      ),
                      child:
                          const Icon(
                        Icons.camera_alt,
                        size: 18,
                        color:
                            AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(
            height: 14,
          ),

          // Only an admin/superadmin
          // can change the employee name.
          if (editing &&
              _canEditName)
            Padding(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 35,
              ),
              child: TextField(
                controller:
                    _nameController,
                textAlign:
                    TextAlign.center,
                cursorColor:
                    Colors.white,
                style:
                    const TextStyle(
                  color:
                      Colors.white,
                  fontSize: 20,
                  fontWeight:
                      FontWeight.w800,
                ),
                decoration:
                    const InputDecoration(
                  hintText:
                      'Full Name',
                  hintStyle:
                      TextStyle(
                    color:
                        Colors.white70,
                    fontSize: 18,
                    fontWeight:
                        FontWeight.w600,
                  ),
                  border:
                      InputBorder.none,
                  enabledBorder:
                      InputBorder.none,
                  focusedBorder:
                      InputBorder.none,
                  filled: false,
                  contentPadding:
                      EdgeInsets.zero,
                ),
              ),
            )
          else
            Text(
              name,
              style:
                  const TextStyle(
                color:
                    Colors.white,
                fontSize: 22,
                fontWeight:
                    FontWeight.w800,
              ),
              textAlign:
                  TextAlign.center,
            ),

          const SizedBox(
            height: 4,
          ),

          Text(
            designation,
            style:
                const TextStyle(
              color:
                  Colors.white70,
              fontSize: 13,
              fontWeight:
                  FontWeight.w500,
            ),
            textAlign:
                TextAlign.center,
          ),

          const SizedBox(
            height: 12,
          ),

          Wrap(
            alignment:
                WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children:
                <Widget>[
              _badge(
                'ID: $_employeeId',
                Colors.white.withValues(
                  alpha: 0.20,
                ),
              ),
              if (isSuper)
                _badge(
                  'Super Admin',
                  Colors.amber.withValues(
                    alpha: 0.30,
                  ),
                )
              else if (isAdmin)
                _badge(
                  'Admin',
                  Colors.blue.withValues(
                    alpha: 0.30,
                  ),
                )
              else
                _badge(
                  'Employee',
                  Colors.white.withValues(
                    alpha: 0.20,
                  ),
                ),
              _badge(
                isActive
                    ? 'Active'
                    : 'Inactive',
                isActive
                    ? Colors.green.withValues(
                        alpha: 0.30,
                      )
                    : Colors.red.withValues(
                        alpha: 0.30,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _badge(
    String text,
    Color bg,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration:
          BoxDecoration(
        color: bg,
        borderRadius:
            BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style:
            const TextStyle(
          color:
              Colors.white,
          fontSize: 11,
          fontWeight:
              FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildCompanyInfoCard() {
    final canEdit =
        editing &&
        _canEditCompanyDetails;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration:
            BoxDecoration(
          color:
              AppColors.surface,
          borderRadius:
              BorderRadius.circular(18),
          boxShadow:
              AppShadows.card,
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
                      Icons
                          .business_center_rounded,
                      color:
                          AppColors.primary,
                      size: 20,
                    ),
                    SizedBox(
                      width: 8,
                    ),
                    Text(
                      'Company Information',
                      style:
                          TextStyle(
                        fontSize:
                            16,
                        fontWeight:
                            FontWeight.w800,
                        color:
                            AppColors
                                .textPrimary,
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
                    decoration:
                        BoxDecoration(
                      color:
                          AppColors.background,
                      borderRadius:
                          BorderRadius.circular(
                        10,
                      ),
                    ),
                    child:
                        const Row(
                      mainAxisSize:
                          MainAxisSize.min,
                      children: <Widget>[
                        Icon(
                          Icons
                              .lock_outline,
                          size: 12,
                          color:
                              AppColors
                                  .textSecondary,
                        ),
                        SizedBox(
                          width: 4,
                        ),
                        Text(
                          'Company Managed',
                          style:
                              TextStyle(
                            fontSize:
                                10,
                            color:
                                AppColors
                                    .textSecondary,
                            fontWeight:
                                FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const Divider(
              height: 24,
            ),

            if (canEdit)
              _editableTextItem(
                icon:
                    Icons.badge_outlined,
                label:
                    'Employee ID',
                controller:
                    _employeeIdController,
                hint:
                    'e.g. EMP001',
              )
            else
              _infoItem(
                icon:
                    Icons.badge_outlined,
                label:
                    'Employee ID',
                value:
                    _employeeId,
                isEditable:
                    false,
              ),

            _infoItem(
              icon:
                  Icons.work_outline,
              label:
                  'Designation',
              value: _designationController
                      .text
                      .trim()
                      .isEmpty
                  ? 'Not Assigned'
                  : _designationController
                      .text
                      .trim(),
              isEditable:
                  canEdit,
              controller:
                  _designationController,
              hint:
                  'e.g. Software Engineer, Manager',
            ),

            if (canEdit)
              _buildDatePickerRow()
            else
              _infoItem(
                icon: Icons
                    .calendar_today_outlined,
                label:
                    'Date of Joining',
                value:
                    _dateOfJoining.isEmpty
                        ? 'Not Specified'
                        : _dateOfJoining,
                isEditable:
                    false,
              ),

            if (canEdit)
              _buildEmploymentTypeRow()
            else
              _infoItem(
                icon:
                    Icons.access_time_outlined,
                label:
                    'Employment Type',
                value:
                    _employmentType,
                isEditable:
                    false,
              ),

            _infoItem(
              icon:
                  Icons.location_on_outlined,
              label:
                  'Work Location / Place',
              value:
                  _workLocationController
                          .text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _workLocationController
                          .text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _workLocationController,
              hint:
                  'e.g. Edappally, Kochi',
            ),

            _infoItem(
              icon:
                  Icons.alternate_email,
              label:
                  'Official Work Email',
              value:
                  _workEmailController
                          .text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _workEmailController
                          .text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _workEmailController,
              hint:
                  'name@company.com',
            ),

            if (canEdit)
              Padding(
                padding:
                    const EdgeInsets.only(
                  top: 4,
                ),
                child:
                    SwitchListTile(
                  contentPadding:
                      EdgeInsets.zero,
                  title:
                      const Text(
                    'Status Active',
                    style:
                        TextStyle(
                      fontSize:
                          14,
                      fontWeight:
                          FontWeight.bold,
                    ),
                  ),
                  subtitle:
                      Text(
                    _status ==
                            'active'
                        ? 'User can sign in and log attendance'
                        : 'Account disabled',
                    style:
                        const TextStyle(
                      fontSize:
                          11,
                    ),
                  ),
                  value:
                      _status ==
                          'active',
                  onChanged:
                      (value) {
                    setState(() {
                      _status =
                          value
                              ? 'active'
                              : 'inactive';
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
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding:
                const EdgeInsets.all(8),
            decoration:
                BoxDecoration(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child:
                const Icon(
              Icons
                  .calendar_today_outlined,
              color:
                  AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Date of Joining',
                  style:
                      TextStyle(
                    color:
                        AppColors
                            .textSecondary,
                    fontSize:
                        11,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  _dateOfJoining.isEmpty
                      ? 'Select Date'
                      : _dateOfJoining,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                    fontSize:
                        14,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton(
            onPressed:
                _selectDateOfJoining,
            child:
                const Text(
              'Pick Date',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmploymentTypeRow() {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding:
                const EdgeInsets.all(8),
            decoration:
                BoxDecoration(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child:
                const Icon(
              Icons
                  .access_time_outlined,
              color:
                  AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          const Expanded(
            child: Text(
              'Employment Type',
              style:
                  TextStyle(
                color:
                    AppColors
                        .textSecondary,
                fontSize:
                    13,
              ),
            ),
          ),
          DropdownButton<String>(
            value:
                _employmentType,
            underline:
                const SizedBox.shrink(),
            items:
                _employmentTypes
                    .map(
              (type) =>
                  DropdownMenuItem<
                      String>(
                value:
                    type,
                child:
                    Text(
                  type,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            )
                    .toList(),
            onChanged:
                (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _employmentType =
                    value;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalInfoCard() {
    final canEdit =
        editing &&
        _canEditPersonalDetails;

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 18,
      ),
      child: Container(
        padding:
            const EdgeInsets.all(18),
        decoration:
            BoxDecoration(
          color:
              AppColors.surface,
          borderRadius:
              BorderRadius.circular(18),
          boxShadow:
              AppShadows.card,
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(
                  Icons
                      .person_pin_circle_outlined,
                  color:
                      AppColors.primary,
                  size: 20,
                ),
                const SizedBox(
                  width: 8,
                ),
                const Expanded(
                  child: Text(
                    'Personal & Contact Details',
                    style:
                        TextStyle(
                      fontSize:
                          16,
                      fontWeight:
                          FontWeight.w800,
                      color:
                          AppColors
                              .textPrimary,
                    ),
                  ),
                ),
                if (!canEdit)
                  const Icon(
                    Icons.lock_outline,
                    size: 16,
                    color:
                        AppColors
                            .textSecondary,
                  ),
              ],
            ),
            const Divider(
              height: 24,
            ),

            _infoItem(
              icon:
                  Icons.phone_outlined,
              label:
                  'Phone / Contact Number',
              value:
                  _phoneController.text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _phoneController.text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _phoneController,
              hint:
                  '+91 98765 43210',
              actionButton:
                  !canEdit &&
                          _phoneController
                              .text
                              .trim()
                              .isNotEmpty
                      ? IconButton(
                          icon:
                              const Icon(
                            Icons.call,
                            size: 18,
                            color:
                                AppColors
                                    .success,
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
              icon:
                  Icons.email_outlined,
              label:
                  'Personal Email',
              value:
                  _personalEmailController
                          .text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _personalEmailController
                          .text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _personalEmailController,
              hint:
                  'personal@gmail.com',
            ),

            _infoItem(
              icon:
                  Icons.home_outlined,
              label:
                  'Residential Place / Address',
              value:
                  _addressController
                          .text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _addressController
                          .text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _addressController,
              hint:
                  'City, State',
            ),

            _infoItem(
              icon:
                  Icons
                      .contact_emergency_outlined,
              label:
                  'Emergency Contact',
              value:
                  _emergencyContactController
                          .text
                          .trim()
                          .isEmpty
                      ? 'Not Provided'
                      : _emergencyContactController
                          .text
                          .trim(),
              isEditable:
                  canEdit,
              controller:
                  _emergencyContactController,
              hint:
                  'Name & Phone Number',
            ),

            if (canEdit)
              _buildBloodGroupRow()
            else
              _infoItem(
                icon:
                    Icons.favorite_outline,
                label:
                    'Blood Group',
                value:
                    _bloodGroup,
                isEditable:
                    false,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBloodGroupRow() {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding:
                const EdgeInsets.all(8),
            decoration:
                BoxDecoration(
              color:
                  AppColors.danger
                      .withValues(
                alpha: 0.10,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child:
                const Icon(
              Icons.favorite_outline,
              color:
                  AppColors.danger,
              size: 18,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          const Expanded(
            child: Text(
              'Blood Group',
              style:
                  TextStyle(
                color:
                    AppColors
                        .textSecondary,
                fontSize:
                    13,
              ),
            ),
          ),
          DropdownButton<String>(
            value:
                _bloodGroup,
            underline:
                const SizedBox.shrink(),
            items:
                _bloodGroups.map(
              (blood) =>
                  DropdownMenuItem<
                      String>(
                value:
                    blood,
                child:
                    Text(
                  blood,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.bold,
                  ),
                ),
              ),
            ).toList(),
            onChanged:
                (value) {
              if (value == null) {
                return;
              }

              setState(() {
                _bloodGroup =
                    value;
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
    required TextEditingController
        controller,
    String? hint,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: TextField(
        controller:
            controller,
        keyboardType:
            keyboardType,
        textCapitalization:
            TextCapitalization.sentences,
        decoration:
            InputDecoration(
          labelText:
              label,
          hintText:
              hint,
          prefixIcon:
              Icon(
            icon,
            size: 20,
          ),
          border:
              OutlineInputBorder(
            borderRadius:
                BorderRadius.circular(
              12,
            ),
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
    TextEditingController?
        controller,
    String? hint,
    Widget? actionButton,
  }) {
    if (isEditable &&
        controller != null) {
      return _editableTextItem(
        icon: icon,
        label: label,
        controller: controller,
        hint: hint,
      );
    }

    return Padding(
      padding:
          const EdgeInsets.only(
        bottom: 14,
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding:
                const EdgeInsets.all(8),
            decoration:
                BoxDecoration(
              color:
                  AppColors.primary
                      .withValues(
                alpha: 0.08,
              ),
              borderRadius:
                  BorderRadius.circular(
                10,
              ),
            ),
            child: Icon(
              icon,
              color:
                  AppColors.primary,
              size: 18,
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  style:
                      const TextStyle(
                    color:
                        AppColors
                            .textSecondary,
                    fontSize:
                        11,
                  ),
                ),
                const SizedBox(
                  height: 2,
                ),
                Text(
                  value,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w700,
                    fontSize:
                        14,
                    color:
                        AppColors
                            .textPrimary,
                  ),
                ),
              ],
            ),
          ),
          ?actionButton,
        ],
      ),
    );
  }

  // ============================================================
  // ACCOUNT ACTIONS
  // ============================================================
  //
  // Employee with adminAccess == true:
  //     Switch to Admin Panel
  //
  // Admin:
  //     Switch to My Employee Dashboard
  //
  // Super Admin:
  //     No switch action
  //
  // This keeps the Super Admin completely separate from the
  // normal employee/admin panel flow.
  Widget _buildActionSections() {
    final List<Widget> tiles =
        <Widget>[];

    // Employee who has been granted adminAccess
    // can enter the Admin Panel.
    if (!_isSuperAdmin &&
        widget.onSwitchToAdminPanel !=
            null &&
        widget.hasAdminAccess) {
      tiles.add(
        _tile(
          Icons
              .admin_panel_settings_outlined,
          'Switch to Admin Panel',
          widget
              .onSwitchToAdminPanel!,
        ),
      );
    }

    // Admin can return to their own
    // Employee Dashboard.
    if (!_isSuperAdmin &&
        widget.onSwitchToMyDashboard !=
            null) {
      tiles.add(
        _tile(
          Icons.person_outline,
          'Switch to My Employee Dashboard',
          widget
              .onSwitchToMyDashboard!,
        ),
      );
    }

    // Super Admin does not get either
    // switching option.
    if (tiles.isEmpty) {
      return const SizedBox.shrink();
    }

    return _section(
      'Account Actions',
      tiles,
    );
  }

  Widget _section(
    String title,
    List<Widget> tiles,
  ) {
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(
        18,
        8,
        18,
        4,
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title.toUpperCase(),
            style:
                const TextStyle(
              color:
                  AppColors
                      .textSecondary,
              fontSize:
                  11,
              fontWeight:
                  FontWeight.bold,
            ),
          ),
          const SizedBox(
            height: 8,
          ),
          Container(
            decoration:
                BoxDecoration(
              color:
                  AppColors.surface,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
              boxShadow:
                  AppShadows.card,
            ),
            child:
                Column(
              children:
                  tiles,
            ),
          ),
          const SizedBox(
            height: 12,
          ),
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
        color:
            AppColors.primary,
      ),
      title: Text(
        title,
        style:
            const TextStyle(
          fontWeight:
              FontWeight.w600,
          fontSize:
              14,
        ),
      ),
      trailing:
          const Icon(
        Icons.chevron_right,
        size: 20,
        color:
            AppColors
                .textSecondary,
      ),
      onTap: onTap,
    );
  }
}
class _PersonalDetailsEditScreen extends StatefulWidget {
  final String phone;
  final String personalEmail;
  final String address;
  final String emergencyContact;
  final String bloodGroup;

  const _PersonalDetailsEditScreen({
    required this.phone,
    required this.personalEmail,
    required this.address,
    required this.emergencyContact,
    required this.bloodGroup,
  });

  @override
  State<_PersonalDetailsEditScreen> createState() =>
      _PersonalDetailsEditScreenState();
}

class _PersonalDetailsEditScreenState
    extends State<_PersonalDetailsEditScreen> {
  late final TextEditingController phoneController;
  late final TextEditingController personalEmailController;
  late final TextEditingController addressController;
  late final TextEditingController emergencyContactController;
  late String bloodGroup;

  final List<String> bloodGroups = const [
    'A+', 'A-', 'B+', 'B-', 'O+', 'O-', 'AB+', 'AB-', 'Unknown',
  ];

  @override
  void initState() {
    super.initState();
    phoneController = TextEditingController(text: widget.phone);
    personalEmailController = TextEditingController(text: widget.personalEmail);
    addressController = TextEditingController(text: widget.address);
    emergencyContactController =
        TextEditingController(text: widget.emergencyContact);
    bloodGroup = bloodGroups.contains(widget.bloodGroup)
        ? widget.bloodGroup
        : 'Unknown';
  }

  @override
  void dispose() {
    phoneController.dispose();
    personalEmailController.dispose();
    addressController.dispose();
    emergencyContactController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Personal Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _editField('Phone', phoneController, Icons.phone_outlined),
          _editField('Personal email', personalEmailController, Icons.mail_outline_rounded),
          _editField('Address', addressController, Icons.location_on_outlined, maxLines: 3),
          _editField('Emergency contact', emergencyContactController, Icons.phone_in_talk_outlined),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: bloodGroup,
              decoration: const InputDecoration(
                labelText: 'Blood group',
                prefixIcon: Icon(Icons.favorite_outline),
                border: InputBorder.none,
              ),
              items: bloodGroups
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => bloodGroup = value);
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context, <String, String>{
                  'phone': phoneController.text.trim(),
                  'personalEmail': personalEmailController.text.trim(),
                  'address': addressController.text.trim(),
                  'emergencyContact': emergencyContactController.text.trim(),
                  'bloodGroup': bloodGroup,
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Save changes',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField(
    String label,
    TextEditingController controller,
    IconData icon, {
    int maxLines = 1,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        ),
      ),
    );
  }
}

class _WorkDetailsEditScreen extends StatefulWidget {
  final String employeeId;
  final String name;
  final String designation;
  final String workLocation;
  final String officialEmail;
  final String dateOfJoining;
  final String employmentType;

  const _WorkDetailsEditScreen({
    required this.employeeId,
    required this.name,
    required this.designation,
    required this.workLocation,
    required this.officialEmail,
    required this.dateOfJoining,
    required this.employmentType,
  });

  @override
  State<_WorkDetailsEditScreen> createState() => _WorkDetailsEditScreenState();
}

class _WorkDetailsEditScreenState extends State<_WorkDetailsEditScreen> {
  late final TextEditingController employeeIdController;
  late final TextEditingController nameController;
  late final TextEditingController designationController;
  late final TextEditingController workLocationController;
  late final TextEditingController officialEmailController;
  late String dateOfJoining;
  late String employmentType;

  final employmentTypes = const [
    'Full-Time', 'Part-Time', 'Contract', 'Intern', 'Probation',
  ];

  @override
  void initState() {
    super.initState();
    employeeIdController = TextEditingController(text: widget.employeeId);
    nameController = TextEditingController(text: widget.name);
    designationController = TextEditingController(text: widget.designation);
    workLocationController = TextEditingController(text: widget.workLocation);
    officialEmailController = TextEditingController(text: widget.officialEmail);
    dateOfJoining = widget.dateOfJoining;
    employmentType = employmentTypes.contains(widget.employmentType)
        ? widget.employmentType
        : employmentTypes.first;
  }

  @override
  void dispose() {
    employeeIdController.dispose();
    nameController.dispose();
    designationController.dispose();
    workLocationController.dispose();
    officialEmailController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    DateTime initial = DateTime.now();
    if (dateOfJoining.trim().isNotEmpty) {
      try {
        initial = DateFormat('dd MMM yyyy').parse(dateOfJoining);
      } catch (_) {
        try {
          initial = DateTime.parse(dateOfJoining);
        } catch (_) {}
      }
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => dateOfJoining = DateFormat('dd MMM yyyy').format(picked));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        title: const Text(
          'Work Details',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _editField('Employee ID', employeeIdController, Icons.badge_outlined),
          _editField('Name', nameController, Icons.person_outline),
          _editField('Designation', designationController, Icons.business_center_outlined),
          _editField('Work location', workLocationController, Icons.location_on_outlined),
          _editField('Official email', officialEmailController, Icons.mail_outline_rounded),
          InkWell(
            onTap: _pickDate,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 17),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_outlined, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Date of joining', style: TextStyle(fontSize: 11, color: AppColors.mutedText)),
                        const SizedBox(height: 4),
                        Text(
                          dateOfJoining.isEmpty ? 'Not specified' : dateOfJoining,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.mutedText),
                ],
              ),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.divider),
            ),
            child: DropdownButtonFormField<String>(
              initialValue: employmentType,
              decoration: const InputDecoration(
                labelText: 'Employment type',
                prefixIcon: Icon(Icons.work_outline),
                border: InputBorder.none,
              ),
              items: employmentTypes
                  .map((value) => DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) {
                if (value != null) setState(() => employmentType = value);
              },
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 48,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context, <String, String>{
                  'employeeId': employeeIdController.text.trim(),
                  'name': nameController.text.trim(),
                  'designation': designationController.text.trim(),
                  'workLocation': workLocationController.text.trim(),
                  'officialEmail': officialEmailController.text.trim(),
                  'dateOfJoining': dateOfJoining,
                  'employmentType': employmentType,
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Save changes',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _editField(
    String label,
    TextEditingController controller,
    IconData icon,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.divider),
      ),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
        ),
      ),
    );
  }
}

/// Reusable Workora bottom sheet used by the employee Profile screen.
/// It intentionally stays lightweight so every profile action opens with the
/// same rounded, dimmed-background interaction as the design reference.
class _ProfileBottomSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _ProfileBottomSheet({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 30,
                height: 4,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: AppColors.divider,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 10,
                          height: 1.35,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () => Navigator.of(context).pop(),
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.divider),
                    ),
                    child: const Icon(
                      Icons.close_rounded,
                      size: 16,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}
