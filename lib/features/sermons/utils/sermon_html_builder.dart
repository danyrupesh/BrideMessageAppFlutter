import 'dart:convert';

import '../../../core/database/models/sermon_models.dart';
import '../../../core/utils/tamil_normalizer.dart';

String buildSermonHtml(
  SermonEntity sermon,
  List<SermonParagraphEntity> paragraphs,
) {
  final buffer = StringBuffer();

  String? normalize(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return normalizeTamil(trimmed);
  }

  String escape(String value) => htmlEscape.convert(value);

  final headerText = escape(
    normalize('${sermon.id} - ${sermon.title}') ??
        '${sermon.id} - ${sermon.title}',
  );

  buffer.writeln('<div style=\"font-family: NotoSerifTamil; color: #111;\">');
  buffer.writeln(
    '<h1 style=\"margin: 0 0 12px; font-size: 20px;\">$headerText</h1>',
  );

  void writeMeta(String label, String? raw) {
    final value = normalize(raw);
    if (value == null) return;
    buffer.writeln(
      '<p style=\"margin: 0 0 6px; font-size: 13px;\">'
      '<strong>$label:</strong> ${escape(value)}'
      '</p>',
    );
  }

  writeMeta('Location', sermon.location);
  writeMeta('Duration', sermon.duration);
  writeMeta('Date', sermon.date);

  for (final p in paragraphs) {
    final text = normalize(p.text) ?? '';
    buffer.writeln(
      '<p style=\"margin: 0 0 8px; font-size: 14px;\">${escape(text)}</p>',
    );
  }

  buffer.writeln('</div>');
  return buffer.toString();
}
