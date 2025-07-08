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
      pw.Font ttfBold;
      
      if (kIsWeb) {
        ttf = await PdfGoogleFonts.cairoRegular();
        ttfBold = await PdfGoogleFonts.cairoBold();
      } else {
        final fontData = await rootBundle.load('assets/fonts/cairo/Cairo-Regular.ttf');
        final fontDataBold = await rootBundle.load('assets/fonts/cairo/Cairo-Bold.ttf');
        ttf = pw.Font.ttf(fontData);
        ttfBold = pw.Font.ttf(fontDataBold);
      }

      // Load SVG background image
      final String svgString = await rootBundle.loadString('assets/pdf_logo.svg');

      // Create PDF document
      final pdf = pw.Document();

      // Add content to PDF
      pdf.addPage(
        pw.MultiPage(
          header: (pw.Context context) => _buildHeader(ttf, ttfBold),
          footer: (pw.Context context) => _buildFooter(ttf, context),
          pageTheme: pw.PageTheme(
            pageFormat: PdfPageFormat.a4,
            textDirection: pw.TextDirection.rtl,
            theme: pw.ThemeData.withFont(
              base: ttf,
              bold: ttfBold,
              italic: ttf,
              boldItalic: ttfBold,
            ),
            buildBackground: (pw.Context context) {
              return pw.FullPage(
                ignoreMargins: true,
                child: pw.Center(
                  child: pw.Container(
                    width: 200, // Smaller width
                    height: 200, // Smaller height
                    child: pw.Opacity(
                      opacity: 0.25, // Reduced opacity for blur effect
                      child: pw.Container(
                        decoration: pw.BoxDecoration(
                          borderRadius: pw.BorderRadius.circular(20),
                          boxShadow: [
                            pw.BoxShadow(
                              color: PdfColors.grey300,
                              blurRadius: 15,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: pw.SvgImage(
                          svg: svgString,
                          fit: pw.BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          build: (pw.Context context) {
            return [
              pw.SizedBox(height: 20),
              _buildStatisticsSection(tasks, ttf, ttfBold),
              pw.SizedBox(height: 30),
              _buildTasksTable(tasks, ttf, ttfBold),
            ];
          },
        ),
      );

      // Generate PDF bytes
      final Uint8List pdfBytes = await pdf.save();

      if (kIsWeb) {
        await _downloadPdfWeb(pdfBytes);
      } else {
        await _savePdfMobile(pdfBytes);
      }
    } catch (e) {
      debugPrint('Error generating PDF: $e');
      throw Exception('فشل في إنشاء ملف PDF: $e');
    }
  }

  pw.Widget _buildHeader(pw.Font ttf, pw.Font ttfBold) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'أجندة العمل اليومية ',
                style: pw.TextStyle(
                  fontSize: 24,
                  fontWeight: pw.FontWeight.bold,
                  color: const PdfColor.fromInt(0xFF1e293b),
                  font: ttfBold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'تقرير شامل لجميع المهام والأنشطة',
                style: pw.TextStyle(
                  fontSize: 12,
                  color: const PdfColor.fromInt(0xFF64748b),
                  font: ttf,
                ),
              ),
            ],
          ),
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: pw.BoxDecoration(
              gradient: pw.LinearGradient(
                colors: [
                  const PdfColor.fromInt(0xFF3b82f6),
                  const PdfColor.fromInt(0xFF1d4ed8),
                ],
                begin: pw.Alignment.topLeft,
                end: pw.Alignment.bottomRight,
              ),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(
              _formatDateWithDayName(DateTime.now()),
              style: pw.TextStyle(
                fontSize: 14,
                color: PdfColors.white,
                font: ttfBold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildFooter(pw.Font ttf, pw.Context context) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(top: 20),
      padding: const pw.EdgeInsets.symmetric(vertical: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          top: pw.BorderSide(
            color: PdfColor.fromInt(0xFFe2e8f0),
            width: 1,
          ),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          
          pw.Text(
            'صفحة ${context.pageNumber} من ${context.pagesCount}',
            style: pw.TextStyle(
              fontSize: 10,
              color: const PdfColor.fromInt(0xFF64748b),
              font: ttf,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatisticsSection(List<Map<String, dynamic>> tasks, pw.Font ttf, pw.Font ttfBold) {
    final totalTasks = tasks.length;
    final completedTasks = tasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      final assignment = assignments?.isNotEmpty == true ? assignments!.first : null;
      return assignment?['status'] == 'completed';
    }).length;
    final inProgressTasks = tasks.where((task) {
      final assignments = task['task_assignments'] as List<dynamic>?;
      final assignment = assignments?.isNotEmpty == true ? assignments!.first : null;
      return assignment?['status'] == 'in_progress';
    }).length;
    final newTasks = totalTasks - completedTasks - inProgressTasks;

    return pw.Container(
      padding: const pw.EdgeInsets.all(20),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [
            const PdfColor.fromInt(0xFFf8fafc),
            const PdfColor.fromInt(0xFFe2e8f0),
          ],
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
        ),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(
          color: const PdfColor.fromInt(0xFFe2e8f0),
          width: 1,
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'إحصائيات المهام',
            style: pw.TextStyle(
              fontSize: 18,
              fontWeight: pw.FontWeight.bold,
              color: const PdfColor.fromInt(0xFF1e293b),
              font: ttfBold,
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatCard('المجموع', totalTasks.toString(), const PdfColor.fromInt(0xFF3b82f6), ttf, ttfBold),
              _buildStatCard('مكتملة', completedTasks.toString(), const PdfColor.fromInt(0xFF10b981), ttf, ttfBold),
              _buildStatCard('قيد التنفيذ', inProgressTasks.toString(), const PdfColor.fromInt(0xFFf59e0b), ttf, ttfBold),
              _buildStatCard('جديدة', newTasks.toString(), const PdfColor.fromInt(0xFF8b5cf6), ttf, ttfBold),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _buildStatCard(String title, String value, PdfColor color, pw.Font ttf, pw.Font ttfBold) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(16),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(8),
        border: pw.Border.all(color: color, width: 2),
        boxShadow: [
          pw.BoxShadow(
            color: PdfColor(color.red, color.green, color.blue, 0.1),
            offset: const PdfPoint(0, 2),
            blurRadius: 4,
          ),
        ],
      ),
      child: pw.Column(
        children: [
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 24,
              fontWeight: pw.FontWeight.bold,
              color: color,
              font: ttfBold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 12,
              color: const PdfColor.fromInt(0xFF64748b),
              font: ttf,
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _buildTasksTable(List<Map<String, dynamic>> tasks, pw.Font ttf, pw.Font ttfBold) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'تفاصيل المهام',
          style: pw.TextStyle(
            fontSize: 18,
            fontWeight: pw.FontWeight.bold,
            color: const PdfColor.fromInt(0xFF1e293b),
            font: ttfBold,
          ),
        ),
        pw.SizedBox(height: 16),
        pw.Container(
          decoration: pw.BoxDecoration(
            borderRadius: pw.BorderRadius.circular(12),
            border: pw.Border.all(
              color: const PdfColor.fromInt(0xFFe2e8f0),
              width: 1,
            ),
          ),
          child: pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: const PdfColor.fromInt(0xFFe2e8f0),
                width: 1,
              ),
              verticalInside: pw.BorderSide(
                color: const PdfColor.fromInt(0xFFe2e8f0),
                width: 1,
              ),
            ),
            columnWidths: {
              0: const pw.FlexColumnWidth(3),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
            },
            children: [
              // Header row
              pw.TableRow(
                decoration: pw.BoxDecoration(
                  gradient: pw.LinearGradient(
                    colors: [
                      const PdfColor.fromInt(0xFF3b82f6),
                      const PdfColor.fromInt(0xFF1d4ed8),
                    ],
                    begin: pw.Alignment.topLeft,
                    end: pw.Alignment.bottomRight,
                  ),
                ),
                children: [
                  //_buildTableCell('العنوان', isHeader: true, ttf: ttf, ttfBold: ttfBold),
                  _buildTableCell('المهام', isHeader: true, ttf: ttf, ttfBold: ttfBold),
                  _buildTableCell('الحالة', isHeader: true, ttf: ttf, ttfBold: ttfBold),
                  _buildTableCell('المنشئ', isHeader: true, ttf: ttf, ttfBold: ttfBold),
                  _buildTableCell('المختص', isHeader: true, ttf: ttf, ttfBold: ttfBold),
                ],
              ),
              // Data rows
              ...tasks.asMap().entries.map((entry) {
                final index = entry.key;
                final task = entry.value;
                final assignments = task['task_assignments'] as List<dynamic>?;
                final assignment = assignments?.isNotEmpty == true ? assignments!.first : null;
                final status = assignment?['status'] ?? 'new';
                final creatorName = task['creator_profile']?['name'] ?? 'غير محدد';
                final assigneeName = assignment?['assignee_profile']?['name'] ?? 'غير محدد';
                final description = task['description'] ?? 'بدون وصف';

                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                    color: index % 2 == 0
                        ? PdfColors.white
                        : const PdfColor.fromInt(0xFFf8fafc),
                  ),
                  children: [
                    _buildTableCell(task['title'] ?? 'بدون عنوان', ttf: ttf, ttfBold: ttfBold),
                    _buildTableCell(description, ttf: ttf, ttfBold: ttfBold),
                    _buildStatusCell(status, ttf, ttfBold),
                    _buildTableCell(creatorName, ttf: ttf, ttfBold: ttfBold),
                    _buildTableCell(assigneeName, ttf: ttf, ttfBold: ttfBold),
                  ],
                );
              }).toList(),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _buildTableCell(String text, {bool isHeader = false, required pw.Font ttf, required pw.Font ttfBold}) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          font: isHeader ? ttfBold : ttf,
          fontWeight: isHeader ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: isHeader ? 14 : 12,
          color: isHeader ? PdfColors.white : const PdfColor.fromInt(0xFF334155),
        ),
        textAlign: pw.TextAlign.center,
        maxLines: 3,
        overflow: pw.TextOverflow.clip,
      ),
    );
  }

  pw.Widget _buildStatusCell(String status, pw.Font ttf, pw.Font ttfBold) {
    final statusInfo = _getStatusInfo(status);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      child: pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: pw.BoxDecoration(
          color: statusInfo['color'],
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(
          statusInfo['text'],
          style: pw.TextStyle(
            font: ttfBold,
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
            color: PdfColors.white,
          ),
          textAlign: pw.TextAlign.center,
        ),
      ),
    );
  }

  Map<String, dynamic> _getStatusInfo(String status) {
    switch (status) {
      case 'completed':
        return {
          'text': 'تم التنفيذ',
          'color': const PdfColor.fromInt(0xFF10b981),
        };
      case 'in_progress':
        return {
          'text': 'قيد التنفيذ',
          'color': const PdfColor.fromInt(0xFFf59e0b),
        };
      default:
        return {
          'text': 'جديدة',
          'color': const PdfColor.fromInt(0xFF8b5cf6),
        };
    }
  }

  String _formatDate(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _formatDateWithDayName(DateTime date) {
    final months = [
      'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
      'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
    ];
    
    final dayNames = [
      'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 
      'الجمعة', 'السبت', 'الأحد'
    ];
    
    final dayName = dayNames[date.weekday - 1];
    return '$dayName، ${date.day} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _downloadPdfWeb(Uint8List pdfBytes) async {
    try {
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);

      final anchor = html.AnchorElement(href: url)
        ..setAttribute('download', 'تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf')
        ..click();

      html.Url.revokeObjectUrl(url);
      debugPrint('PDF downloaded successfully for web');
    } catch (e) {
      debugPrint('Error downloading PDF on web: $e');
      final blob = html.Blob([pdfBytes], 'application/pdf');
      final url = html.Url.createObjectUrlFromBlob(blob);
      html.window.open(url, '_blank');
    }
  }

  Future<void> _savePdfMobile(Uint8List pdfBytes) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = io.File('${directory.path}/تقرير_المهام_${DateTime.now().millisecondsSinceEpoch}.pdf');

      await file.writeAsBytes(pdfBytes);

      await Printing.sharePdf(
        bytes: pdfBytes,
        filename: 'تقرير_المهام.pdf',
      );

      debugPrint('PDF saved successfully at: ${file.path}');
    } catch (e) {
      debugPrint('Error saving PDF on mobile: $e');
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
      );
    }
  }
}