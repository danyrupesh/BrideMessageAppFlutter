import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/pdf_fonts.dart';
import '../models/note_model.dart';

bool _containsTamil(String text) {
  final tamilRegex = RegExp(r'[\u0B80-\u0BFF]');
  return tamilRegex.hasMatch(text);
}

Future<pw.Document> buildNotePdf(NoteModel note) async {
  final text = '${note.title}\n${note.body}';
  final hasTamil = _containsTamil(text);

  final bodyFont = hasTamil
      ? await AppPdfFonts.tamilSerifRegular()
      : pw.Font.helvetica();
  final boldFont = hasTamil
      ? await AppPdfFonts.tamilSerifBold()
      : pw.Font.helveticaBold();

  final doc = pw.Document();

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      build: (context) {
        final widgets = <pw.Widget>[
          pw.Text(
            note.title.trim().isEmpty ? 'Untitled Note' : note.title.trim(),
            style: pw.TextStyle(font: boldFont, fontSize: 20),
          ),
          pw.SizedBox(height: 10),
          pw.Text(
            'Updated: ${note.updatedAt.toLocal()}',
            style: pw.TextStyle(font: bodyFont, fontSize: 10),
          ),
        ];

        if (note.category.trim().isNotEmpty) {
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(
            pw.Text(
              'Category: ${note.category.trim()}',
              style: pw.TextStyle(font: bodyFont, fontSize: 10),
            ),
          );
        }

        if (note.linkedSources.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(
            pw.Text(
              'Sources: ${note.linkedSources.map((value) => value.summary).join(' | ')}',
              style: pw.TextStyle(font: bodyFont, fontSize: 10),
            ),
          );
        }

        if (note.tags.isNotEmpty) {
          widgets.add(pw.SizedBox(height: 4));
          widgets.add(
            pw.Text(
              'Tags: ${note.tags.join(', ')}',
              style: pw.TextStyle(font: bodyFont, fontSize: 10),
            ),
          );
        }

        widgets.add(pw.SizedBox(height: 18));
        widgets.add(
          pw.Paragraph(
            text: note.body,
            style: pw.TextStyle(font: bodyFont, fontSize: 12, lineSpacing: 2),
          ),
        );

        return widgets;
      },
    ),
  );

  return doc;
}
