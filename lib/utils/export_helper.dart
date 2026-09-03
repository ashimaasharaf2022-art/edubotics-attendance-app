import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:excel/excel.dart' as ex;

import '../utils/attendance_calculator.dart';
import 'web_download/web_download.dart';

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
  static const MethodChannel _downloadChannel =
      MethodChannel('workora/downloads');

  static List<String> _rowToStrings(ExportRow r, bool isDaily) {
    if (isDaily) {
      final inTime = r.lastPunchIn ?? "--";
      final outTime = r.lastPunchOut ?? "--";
      final statusText = r.lastStatus ?? "Not Checked In";

      return [
        r.name,
        r.employeeId,
        inTime,
        outTime,
        statusText,
        AttendanceCalculator.formatHours(r.totalHours),
      ];
    }

    return [
      r.name,
      r.employeeId,
      r.fullDays.toString(),
      r.halfDays.toString(),
      r.absentDays.toString(),
      AttendanceCalculator.formatHours(r.totalHours),
    ];
  }

  static Future<String> _saveToDownloads({
    required String method,
    required String fileName,
    required List<int> bytes,
  }) async {
    if (kIsWeb) {
      final mimeType = method == "savePdfToDownloads"
          ? "application/pdf"
          : "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

      await downloadBytesWeb(
        Uint8List.fromList(bytes),
        fileName,
        mimeType: mimeType,
      );

      return "Downloaded $fileName";
    }

    final result = await _downloadChannel.invokeMethod<String>(
      method,
      {
        "fileName": fileName,
        "bytes": Uint8List.fromList(bytes),
      },
    );

    return result ?? "Saved to Downloads/Workora/$fileName";
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

    final tableData =
        rows.map((r) => _rowToStrings(r, isDaily)).toList();

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Text(
                title,
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.Text(
              periodLabel,
              style: const pw.TextStyle(
                fontSize: 12,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.TableHelper.fromTextArray(
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
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 6,
              ),
              border: pw.TableBorder.all(
                color: PdfColor.fromInt(0xFFD9E1EE),
                width: 0.5,
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              "Generated on ${DateTime.now().toString().split(".").first}",
              style: const pw.TextStyle(
                fontSize: 9,
                color: PdfColors.grey500,
              ),
            ),
          ];
        },
      ),
    );

    final bytes = await doc.save();

    final fileName =
        "attendance_report_${DateTime.now().millisecondsSinceEpoch}.pdf";

    await _saveToDownloads(
      method: "savePdfToDownloads",
      fileName: fileName,
      bytes: bytes,
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
        : [
            "Employee",
            "ID",
            "Full Days",
            "Half Days",
            "Absent Days",
            "Total Hours",
          ];

    sheet.appendRow(
      headers.map((h) => ex.TextCellValue(h)).toList(),
    );

    for (final row in rows) {
      final values = _rowToStrings(row, isDaily);
      sheet.appendRow(
        values.map((value) => ex.TextCellValue(value)).toList(),
      );
    }

    final bytes = workbook.encode();
    if (bytes == null) {
      throw Exception("Could not generate Excel file.");
    }

    final fileName =
        "attendance_report_${DateTime.now().millisecondsSinceEpoch}.xlsx";

    await _saveToDownloads(
      method: "saveExcelToDownloads",
      fileName: fileName,
      bytes: bytes,
    );
  }
}