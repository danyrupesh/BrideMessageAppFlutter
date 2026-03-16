import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/database/models/sermon_models.dart';
import '../../../core/utils/pdf_fonts.dart';
import '../../../core/utils/tamil_normalizer.dart';

Future<pw.Document> buildTamilSermonPdf({
  required SermonEntity sermon,
  required List<SermonParagraphEntity> paragraphs,
}) async {
  final doc = pw.Document();
  final bodyFont = await AppPdfFonts.tamilSerifRegular();
  final boldFont = await AppPdfFonts.tamilSerifBold();

  final headerTitle = normalizeTamil('${sermon.id} - ${sermon.title}');

  final meta = <MapEntry<String, String>>[];
  void addMeta(String label, String? value) {
    if (value == null) return;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    meta.add(MapEntry(label, normalizeTamil(trimmed)));
  }

  addMeta('Location', sermon.location);
  addMeta('Duration', sermon.duration);
  addMeta('Date', sermon.date);

  final normalizedParagraphs = paragraphs.map((p) {
    final prefix =
        p.paragraphNumber != null ? '${p.paragraphNumber}\u00B6 ' : '';
    return '$prefix${normalizeTamil(p.text)}';
  }).toList(growable: false);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Center(
            child: pw.Text(
              headerTitle,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 18,
                color: const PdfColor.fromInt(0xFF5B4FCF),
              ),
              textAlign: pw.TextAlign.center,
            ),
          ),
          pw.SizedBox(height: 8),
        ];

        if (meta.isNotEmpty) {
          widgets.add(
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: meta
                  .map(
                    (entry) => pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 2),
                      child: pw.RichText(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: '${entry.key}: ',
                              style: pw.TextStyle(
                                font: boldFont,
                                fontSize: 11,
                              ),
                            ),
                            pw.TextSpan(
                              text: entry.value,
                              style: pw.TextStyle(
                                font: bodyFont,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          );
          widgets.add(pw.SizedBox(height: 10));
        }

        final paragraphStyle = pw.TextStyle(
          font: bodyFont,
          fontSize: 12,
          lineSpacing: 2,
        );

        for (final text in normalizedParagraphs) {
          widgets.add(
            pw.Paragraph(
              text: text,
              style: paragraphStyle,
            ),
          );
          widgets.add(pw.SizedBox(height: 6));
        }

        return widgets;
      },
    ),
  );

  return doc;
}
