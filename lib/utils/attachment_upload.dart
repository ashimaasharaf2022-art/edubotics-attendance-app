import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';

class UploadedAttachment {
  final String name;
  final String url;
  final bool isImage;
  final Uint8List? previewBytes;

  const UploadedAttachment({
    required this.name,
    required this.url,
    this.isImage = false,
    this.previewBytes,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'url': url,
        'isImage': isImage,
      };

  factory UploadedAttachment.fromMap(Map<dynamic, dynamic> map) {
    final name = map['name']?.toString() ?? 'Attachment';
    final url = map['url']?.toString() ?? '';
    return UploadedAttachment(
      name: name,
      url: url,
      isImage: map['isImage'] == true || AttachmentUpload.isImageName(name),
    );
  }
}

/// Browser-safe upload helper for announcement images and documents.
/// `FilePicker` uses the native browser file chooser on web, while `putData`
/// works on both web and mobile without using `dart:io`.
class AttachmentUpload {
  static const int _maxAttachmentBytes = 10 * 1024 * 1024;

  static bool isImageName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }

  static Future<UploadedAttachment?> pickAndUploadImage(String folder) async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
      withData: true,
    );
    return _uploadSelection(selection, folder, forceImage: true);
  }

  static Future<UploadedAttachment?> pickAndUploadDocument(String folder) async {
    final selection = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
    );
    return _uploadSelection(selection, folder);
  }

  static Future<UploadedAttachment?> _uploadSelection(
    FilePickerResult? selection,
    String folder, {
    bool forceImage = false,
  }) async {
    if (selection == null || selection.files.isEmpty) return null;

    final picked = selection.files.single;
    final bytes = picked.bytes;
    if (bytes == null) {
      throw StateError('The selected file could not be read. Please choose it again.');
    }
    if (bytes.length > _maxAttachmentBytes) {
      throw StateError('Attachments must be smaller than 10 MB.');
    }

    final fileName = picked.name;
    final safeName = fileName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final isImage = forceImage || isImageName(fileName);
    final path = '$folder/${DateTime.now().millisecondsSinceEpoch}_$safeName';
    final ref = FirebaseStorage.instance.ref(path);
    await ref.putData(bytes, SettableMetadata(contentType: _contentTypeFor(fileName, isImage)));
    final downloadUrl = await ref.getDownloadURL();

    return UploadedAttachment(
      name: fileName,
      url: downloadUrl,
      isImage: isImage,
      previewBytes: isImage ? bytes : null,
    );
  }

  static String _contentTypeFor(String fileName, bool isImage) {
    final extension = fileName.split('.').last.toLowerCase();
    if (isImage) {
      return switch (extension) {
        'png' => 'image/png',
        'gif' => 'image/gif',
        'webp' => 'image/webp',
        _ => 'image/jpeg',
      };
    }
    return switch (extension) {
      'pdf' => 'application/pdf',
      'doc' => 'application/msword',
      'docx' => 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls' => 'application/vnd.ms-excel',
      'xlsx' => 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt' => 'application/vnd.ms-powerpoint',
      'pptx' => 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'txt' => 'text/plain',
      _ => 'application/octet-stream',
    };
  }

  static Future<UploadedAttachment?> pickAndUpload(String folder) =>
      pickAndUploadDocument(folder);
}
