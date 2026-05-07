import 'package:flutter/material.dart';

import '../../../core/database/models/special_book_models.dart';

class BookCoverCard extends StatelessWidget {
  const BookCoverCard({
    super.key,
    required this.book,
    required this.isDownloaded,
    required this.onTap,
    this.highlightQuery = '',
  });

  final SpecialBook book;
  final bool isDownloaded;
  final VoidCallback onTap;
  final String highlightQuery;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (book.coverUrl != null)
                    Image.network(
                      book.coverUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _PlaceholderCover(color: cs.primaryContainer),
                    )
                  else
                    _PlaceholderCover(color: cs.primaryContainer),
                  if (isDownloaded)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cs.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.check, size: 12, color: cs.onPrimary),
                      ),
                    )
                  else
                    Positioned(
                      top: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withAlpha(200),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.download_outlined,
                          size: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Title area
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHighlightText(
                    context,
                    book.title,
                    highlightQuery,
                    const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (book.author != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      book.author!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 3),
                  Text(
                    '${book.totalChapters} ch.',
                    style: TextStyle(fontSize: 10, color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _buildHighlightText(
  BuildContext context,
  String text,
  String query,
  TextStyle? style, {
  int? maxLines,
  TextOverflow? overflow,
}) {
  if (query.isEmpty) {
    return Text(text, style: style, maxLines: maxLines, overflow: overflow);
  }
  final cs = Theme.of(context).colorScheme;
  final hlStyle = TextStyle(
    backgroundColor: cs.primaryContainer,
    color: cs.onPrimaryContainer,
    fontWeight: FontWeight.bold,
  );
  final lText = text.toLowerCase();
  final lQuery = query.toLowerCase();
  final spans = <TextSpan>[];
  int start = 0;
  int idx;
  while ((idx = lText.indexOf(lQuery, start)) != -1) {
    if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
    spans.add(
      TextSpan(text: text.substring(idx, idx + lQuery.length), style: hlStyle),
    );
    start = idx + lQuery.length;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return Text.rich(
    TextSpan(children: spans, style: style),
    maxLines: maxLines,
    overflow: overflow,
  );
}

class _PlaceholderCover extends StatelessWidget {
  const _PlaceholderCover({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: color,
      child: Center(
        child: Icon(
          Icons.auto_stories,
          size: 48,
          color: Theme.of(
            context,
          ).colorScheme.onPrimaryContainer.withAlpha(120),
        ),
      ),
    );
  }
}
