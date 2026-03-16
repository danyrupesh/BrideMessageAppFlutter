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

