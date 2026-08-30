import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class UploadedAttachment {
  final String name;
  final String url;
  final bool isImage;
  final String? localPath;

  const UploadedAttachment({
    required this.name,
    required this.url,
    this.isImage = false,
    this.localPath,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'isImage': isImage,
      };

  factory UploadedAttachment.fromMap(Map<dynamic, dynamic> map) {
    final name = map['name']?.toString() ?? 'Attachment';
    final url = map['url']?.toString() ?? '';
    final isImg = map['isImage'] == true || AttachmentUpload.isImageName(name) || url.startsWith('data:image/');
    return UploadedAttachment(name: name, url: url, isImage: isImg);
  }
}

/// Robust attachment helper for Images & Documents.
/// Uploads to Firebase Storage with automatic fallback to base64 encoding if Storage is restricted.
class AttachmentUpload {
  static bool isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  /// Picks an image from Camera or Gallery and uploads or base64 encodes it.
  static Future<UploadedAttachment?> pickAndUploadImage({
    required String folder,
    ImageSource source = ImageSource.gallery,
  }) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      maxWidth: 1200,
      maxHeight: 1200,
      imageQuality: 75,
    );
    if (picked == null) return null;

    final file = File(picked.path);
    final fileName = picked.name.isNotEmpty ? picked.name : 'image_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();
      return UploadedAttachment(
        name: fileName,
        url: downloadUrl,
        isImage: true,
        localPath: picked.path,
      );
    } catch (_) {
      // Fallback to base64 data URI if storage upload fails
      final bytes = await file.readAsBytes();
      final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      return UploadedAttachment(
        name: fileName,
        url: base64String,
        isImage: true,
        localPath: picked.path,
      );
    }
  }

  /// Picks a document (PDF, Excel, Docx, etc.) and uploads to Firebase Storage.
  static Future<UploadedAttachment?> pickAndUploadDocument(String folder) async {
    final selection = await FilePicker.platform.pickFiles(allowMultiple: false);
    if (selection == null || selection.files.isEmpty || selection.files.single.path == null) return null;

    final file = File(selection.files.single.path!);
    final fileName = selection.files.single.name;
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final isImg = isImageName(fileName);

    try {
      final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
      final ref = FirebaseStorage.instance.ref(path);
      await ref.putFile(file);
      final downloadUrl = await ref.getDownloadURL();
      return UploadedAttachment(
        name: fileName,
        url: downloadUrl,
        isImage: isImg,
        localPath: selection.files.single.path,
      );
    } catch (e) {
      if (isImg) {
        final bytes = await file.readAsBytes();
        final base64String = 'data:image/jpeg;base64,${base64Encode(bytes)}';
        return UploadedAttachment(
          name: fileName,
          url: base64String,
          isImage: true,
          localPath: selection.files.single.path,
        );
      }
      rethrow;
    }
  }

  /// General pick and upload for documents or files.
  static Future<UploadedAttachment?> pickAndUpload(String folder) async {
    return pickAndUploadDocument(folder);
  }
}
