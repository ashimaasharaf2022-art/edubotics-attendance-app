import 'dart:typed_data';
import 'dart:html' as html;

/// Triggers a browser download of [bytes] as [fileName].
///
/// Used for any exported file (PDF, Excel, etc.) since web has no
/// "save to Downloads folder" API the way Android does. We create an
/// in-memory Blob, wrap it in an object URL, and simulate a click on
/// an invisible <a download> link — the standard way to trigger a file
/// download from a Flutter web app.
Future<void> downloadBytesWeb(
  Uint8List bytes,
  String fileName, {
  String mimeType = 'application/octet-stream',
}) async {
  final blob = html.Blob([bytes], mimeType);
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}