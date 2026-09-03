import 'dart:typed_data';
import 'dart:html' as html;

/// Triggers a browser download of [bytes] as a PDF named [fileName].
///
/// Web has no "save to Downloads folder" API the way Android does —
/// instead we create an in-memory Blob, wrap it in an object URL, and
/// simulate a click on an invisible <a download> link. This is the
/// standard way to trigger a file download from a Flutter web app.
Future<void> downloadPdfWeb(Uint8List bytes, String fileName) async {
  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final anchor = html.AnchorElement(href: url)
    ..setAttribute('download', fileName)
    ..click();

  html.Url.revokeObjectUrl(url);
}