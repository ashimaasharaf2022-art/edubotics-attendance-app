import 'dart:io';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as ex;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../utils/attendance_calculator.dart';

class ExportRow {
  final String employeeId;
  final String name;
  final int fullDays;
  final int halfDays;
  final int absentDays;
  final double totalHours;
  final String? lastStatus;
  final String? lastPunchIn;
  final String? lastPunchOut;

  ExportRow({
    required this.employeeId,
    required this.name,
    required this.fullDays,
    required this.halfDays,
    required this.absentDays,
    required this.totalHours,
    this.lastStatus,
    this.lastPunchIn,
    this.lastPunchOut,
  });
}

class ExportHelper {
  static Future<File> _writeToDownloads(String filename, List<int> bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(dir.path + "/" + filename);
    await file.writeAsBytes(bytes);
    return file;
  }

  static List<String> _rowToStrings(ExportRow r, bool isDaily) {
    if (isDaily) {
      final inTime = r.lastPunchIn == null ? "--" : r.lastPunchIn!;
      final outTime = r.lastPunchOut == null ? "--" : r.lastPunchOut!;
      final statusText = r.lastStatus == null ? "Not Checked In" : r.lastStatus!;
      return [
        r.name,
        r.employeeId,
        inTime,
        outTime,
        statusText,
        AttendanceCalculator.formatHours(r.totalHours),
      ];
    } else {
      return [
        r.name,
        r.employeeId,
        r.fullDays.toString(),
        r.halfDays.toString(),
        r.absentDays.toString(),
        AttendanceCalculator.formatHours(r.totalHours),
      ];
    }
  }

  static Future<void> exportPdf({
    required String title,
    required String periodLabel,
    required List<ExportRow> rows,
    required bool isDaily,
  }) async {
    final doc = pw.Document();

    final headers = isDaily
        ? ["Employee", "ID", "In", "Out", "Status", "Hours"]
        : ["Employee", "ID", "Full", "Half", "Absent", "Hours"];

    final tableData = rows.map((r) => _rowToStrings(r, isDaily)).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                title,
                style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.Text(
              periodLabel,
              style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 16),
            pw.Table.fromTextArray(
              headers: headers,
              data: tableData,
              headerStyle: pw.TextStyle(
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.white,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFF2563EB),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Generated on " + DateTime.now().toString().split(".").first,
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();
    final filename = "attendance_report_" +
        DateTime.now().millisecondsSinceEpoch.toString() +
        ".pdf";
    final file = await _writeToDownloads(filename, bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: title,
      text: "Attendance report: " + periodLabel,
    );
  }

  static Future<void> exportExcel({
    required String title,
    required String periodLabel,
    required List<ExportRow> rows,
    required bool isDaily,
  }) async {
    final workbook = ex.Excel.createExcel();
    final sheet = workbook[workbook.getDefaultSheet()!];

    sheet.appendRow([ex.TextCellValue(title)]);
    sheet.appendRow([ex.TextCellValue(periodLabel)]);
    sheet.appendRow(<ex.CellValue?>[]);

    final headers = isDaily
        ? ["Employee", "ID", "In", "Out", "Status", "Hours"]
        : ["Employee", "ID", "Full Days", "Half Days", "Absent Days", "Total Hours"];

    sheet.appendRow(headers.map((h) => ex.TextCellValue(h)).toList());

    for (final r in rows) {
      final rowStrings = _rowToStrings(r, isDaily);
      sheet.appendRow(rowStrings.map((s) => ex.TextCellValue(s)).toList());
    }

    final bytes = workbook.encode();
    if (bytes == null) return;

    final filename = "attendance_report_" +
        DateTime.now().millisecondsSinceEpoch.toString() +
        ".xlsx";
    final file = await _writeToDownloads(filename, bytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      subject: title,
      text: "Attendance report: " + periodLabel,
    );
  }
}
