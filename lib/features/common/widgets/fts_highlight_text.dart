import 'package:flutter/material.dart';

/// Reusable widget to render FTS5 `<b>...</b>` snippets with themed background colors.
class FtsHighlightText extends StatelessWidget {
  final String rawSnippet;

  const FtsHighlightText({
    super.key,
    required this.rawSnippet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spans = <TextSpan>[];

    final parts = rawSnippet.split('<b>');
    for (int i = 0; i < parts.length; i++) {
      if (i == 0) {
        spans.add(
          TextSpan(
            text: parts[i],
            style: TextStyle(color: theme.colorScheme.onSurface),
          ),
        );
        continue;
      }

      final innerParts = parts[i].split('</b>');
      if (innerParts.isNotEmpty) {
        spans.add(
          TextSpan(
            text: innerParts[0],
            style: TextStyle(
              backgroundColor: Colors.yellow.shade300,
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        );

        if (innerParts.length > 1) {
          spans.add(
            TextSpan(
              text: innerParts[1],
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          );
        }
      }
    }

    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.bodyMedium,
        children: spans,
      ),
    );
  }
}

/// Highlights a plain-text [query] inside [text] (e.g. COD answer body).
class PlainQueryHighlightText {
  const PlainQueryHighlightText._();

  static List<InlineSpan> buildHighlightSpans(
    String text,
    String? query, {
    required TextStyle baseStyle,
    Color highlightBackground = const Color(0xFFFFF59D),
  }) {
    final hq = query?.trim();
    if (hq == null || hq.isEmpty) {
      return [TextSpan(text: text, style: baseStyle)];
    }
    try {
      final pattern = RegExp(RegExp.escape(hq), caseSensitive: false);
      final spans = <InlineSpan>[];
      var start = 0;
      for (final m in pattern.allMatches(text)) {
        if (m.start > start) {
          spans.add(
            TextSpan(
              text: text.substring(start, m.start),
              style: baseStyle,
            ),
          );
        }
        final matched = m.group(0) ?? '';
        spans.add(
          TextSpan(
            text: matched,
            style: baseStyle.copyWith(
              backgroundColor: highlightBackground,
              fontWeight: FontWeight.w600,
            ),
          ),
        );
        start = m.end;
      }
      if (start < text.length) {
        spans.add(TextSpan(text: text.substring(start), style: baseStyle));
      }
      return spans.isEmpty ? [TextSpan(text: text, style: baseStyle)] : spans;
    } catch (_) {
      return [TextSpan(text: text, style: baseStyle)];
    }
  }
}

