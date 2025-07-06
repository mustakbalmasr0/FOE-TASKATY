import 'dart:io' show Platform;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;
import 'package:universal_html/html.dart' as html;
import 'package:flutter/services.dart' show rootBundle;
import 'package:google_fonts/google_fonts.dart';

class PdfReportGenerator {
  Future<void> generateAndOpenPdf(List<Map<String, dynamic>> tasks) async {
    try {
      // Load Cairo font for Arabic support
      pw.Font ttf;
      if (kIsWeb) {
        // Use GoogleFonts Cairo for web
        ttf = await PdfGoogleFonts.cairoRegular();
      } else {
        final fontData =
            await rootBundle.load('assets/fonts/cairo/Cairo-Regular.ttf');
        ttf = pw.Font.ttf(fontData);
      }

      // Create PDF document
      final pdf = pw.Document();

      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          theme: pw.ThemeData.withFont(
            base: ttf,
            bold: ttf,
            italic: ttf,
            boldItalic: ttf,
          ),
          build: (pw.Context context) {
            return [
              pw.Container(
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                    colors: [PdfColors.blue100, PdfColors.white],
                    begin: pw.Alignment.topCenter,
                    end: pw.Alignment.bottomCenter,
                  ),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                padding: const pw.EdgeInsets.all(16),
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      'تقرير المهام',
                      style: pw.TextStyle(
                        fontSize: 28,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                        font: ttf,
                      ),
                    ),
                    pw.Text(
                      _formatDate(DateTime.now()),
                      style: pw.TextStyle(
                        fontSize: 14,
                        color: PdfColors.grey700,
                        font: ttf,
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 20),
              _buildTasksTable(tasks, ttf),
            ];
          },
        ),
      );

      // Generate PDF bytes
      final Uint8List pdfBytes = await pdf.save();

      if (kIsWeb) {
        // For web platform - download directly
        await _downloadPdfWeb(pdfBytes);
      } else {
        // For mobile platforms - save to device
        await _savePdfMobile(pdfBytes);
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      throw Exception('فشل في إنشاء ملف PDF: $e');
    }
  }

  Future<void> _downloadPdfWeb(Uint8List pdfBytes) async {
    try {
      // Create blob and download for web
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download',
            'تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf')
        ..click();

      html.Url.revokeObjectUrl(url);

      debugPrint('PDF downloaded successfully for web');
    } catch (e) {
      debugPrint('Error downloading PDF on web: $e');
      // Fallback: try to open in new tab
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
    }
  }

  Future<void> _savePdfMobile(Uint8List pdfBytes) async {
    try {
      // Get the device's directory
      final directory = await getApplicationDocumentsDirectory();
      final file = io.File(
          '${directory.path}/تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf');

      // Write PDF to file
      await file.writeAsBytes(pdfBytes);

      // Open the PDF using printing package
      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'تقرير_المهام.pdf',
      );

      debugPrint('PDF saved successfully at: ${file.path}');
    } catch (e) {
      debugPrint('Error saving PDF on mobile: $e');
      // Fallback: just try to share/preview
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    }
  }

  pw.Widget _buildTasksTable(List<Map<String, dynamic>> tasks, pw.Font ttf) {
    return pw.Table(
      border: pw.TableBorder.all(width: 1, color: PdfColors.blue200),
      columnWidths: {
        0: const pw.FlexColumnWidth(3), // العنوان
        1: const pw.FlexColumnWidth(4), // الوصف (new)
        2: const pw.FlexColumnWidth(2), // الحالة
        3: const pw.FlexColumnWidth(2), // المنشئ
        4: const pw.FlexColumnWidth(2), // المعين إليه
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue50),
          children: [
            _buildTableCell('العنوان', isHeader: true, ttf: ttf),
            _buildTableCell('الوصف', isHeader: true, ttf: ttf), // new column
            _buildTableCell('الحالة', isHeader: true, ttf: ttf),
            _buildTableCell('المنشئ', isHeader: true, ttf: ttf),
            _buildTableCell('المعين إليه', isHeader: true, ttf: ttf),
          ],
        ),
        // Data rows
        ...tasks.map((task) {
          final assignments = task['task_assignments'] as List<dynamic>?;
          final assignment =
              assignments?.isNotEmpty == true ? assignments!.first : null;
          final status = assignment?['status'] ?? 'new';
          final creatorName = task['creator_profile']?['name'] ?? 'غير محدد';
          final assigneeName =
              assignment?['assignee_profile']?['name'] ?? 'غير محدد';
          final description = task['description'] ?? 'بدون وصف';

          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: tasks.indexOf(task) % 2 == 0
                  ? PdfColors.white
                  : PdfColors.blue50,
            ),
            children: [
              _buildTableCell(task['title'] ?? 'بدون عنوان', ttf: ttf),
              _buildTableCell(description, ttf: ttf), // new cell
              _buildTableCell(_getStatusText(status), ttf: ttf),
              _buildTableCell(creatorName, ttf: ttf),
              _buildTableCell(assigneeName, ttf: ttf),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTableCell(String text,
      {bool isHeader = false, required pw.Font ttf}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: ttf,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 13 : 11,
          color: isHeader ? PdfColors.blue900 : PdfColors.black,
        ),
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'completed':
        return 'مكتملة';
      case 'in_progress':
        return 'قيد التنفيذ';
      default:
        return 'جديدة';
    }
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
