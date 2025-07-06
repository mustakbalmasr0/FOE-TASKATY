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

class PdfReportGenerator {
  Future<void> generateAndOpenPdf(List<Map<String, dynamic>> tasks) async {
    try {
      // Create PDF document
      final pdf = pw.Document();
      
      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          textDirection: pw.TextDirection.rtl,
          build: (pw.Context context) {
            return [
              pw.Header(
                level: 0,
                child: pw.Text(
                  'تقرير المهام',
                  style: pw.TextStyle(
                    fontSize: 24,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(height: 20),
              _buildTasksTable(tasks),
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
        ..setAttribute('download', 'تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf')
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
      final file = io.File('${directory.path}/تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf');
      
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

  pw.Widget _buildTasksTable(List<Map<String, dynamic>> tasks) {
    return pw.Table(
      border: pw.TableBorder.all(width: 1, color: PdfColors.grey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(3),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        // Header row
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            _buildTableCell('العنوان', isHeader: true),
            _buildTableCell('الحالة', isHeader: true),
            _buildTableCell('المنشئ', isHeader: true),
            _buildTableCell('المعين إليه', isHeader: true),
          ],
        ),
        // Data rows
        ...tasks.map((task) {
          final assignments = task['task_assignments'] as List<dynamic>?;
          final assignment = assignments?.isNotEmpty == true ? assignments!.first : null;
          final status = assignment?['status'] ?? 'new';
          final creatorName = task['creator_profile']?['name'] ?? 'غير محدد';
          final assigneeName = assignment?['assignee_profile']?['name'] ?? 'غير محدد';

          return pw.TableRow(
            children: [
              _buildTableCell(task['title'] ?? 'بدون عنوان'),
              _buildTableCell(_getStatusText(status)),
              _buildTableCell(creatorName),
              _buildTableCell(assigneeName),
            ],
          );
        }).toList(),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 12 : 10,
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
}