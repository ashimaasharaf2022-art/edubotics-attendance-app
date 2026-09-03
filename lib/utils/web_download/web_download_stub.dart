import 'dart:typed_data';

/// Non-web stub. Never actually called on mobile/desktop — callers branch
/// on kIsWeb first — but Dart needs a valid implementation to compile
/// against on those platforms.
Future<void> downloadBytesWeb(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  throw UnsupportedError('downloadBytesWeb is only available on web.');
}