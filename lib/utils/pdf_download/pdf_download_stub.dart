import 'dart:typed_data';

/// Non-web stub. This is never actually called on mobile/desktop — the
/// caller in history_screen.dart branches on kIsWeb before reaching this
/// function — but Dart still needs a valid implementation to compile
/// against on those platforms.
Future<void> downloadPdfWeb(Uint8List bytes, String fileName) async {
  throw UnsupportedError('downloadPdfWeb is only available on web.');
}