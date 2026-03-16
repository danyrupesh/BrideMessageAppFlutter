import 'package:flutter/material.dart';

/// Standard card used for Bible search results.
class BibleResultCard extends StatelessWidget {
  final String reference;
  final String book;
  final int chapter;
  final int verse;
  final Widget snippet;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const BibleResultCard({
    super.key,
    required this.reference,
    required this.book,
    required this.chapter,
    required this.verse,
    required this.snippet,
    this.onTap,
    this.onCopy,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.menu_book_outlined,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      reference,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (onCopy != null)
                    IconButton(
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: onCopy,
                    ),
                  if (onShare != null)
                    IconButton(
                      icon: const Icon(Icons.share_outlined, size: 18),
                      onPressed: onShare,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              snippet,
            ],
          ),
        ),
      ),
    );
  }
}

/// Standard card used for sermon search results and sermon list entries.
class SermonResultCard extends StatelessWidget {
  final String id;
  final String title;
  final String? date;
  final String? duration;
  final String? location;
  final String? metaRightBadge;
  final String? subtitle;
  final String? highlightQuery;
  final VoidCallback? onTap;
  final Widget? snippet;

  const SermonResultCard({
    super.key,
    required this.id,
    required this.title,
    this.date,
    this.duration,
    this.location,
    this.metaRightBadge,
    this.subtitle,
    this.highlightQuery,
    this.onTap,
    this.snippet,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleWidget = _buildHighlightedTitle(
      theme,
      title,
      highlightQuery,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    id,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: titleWidget,
                  ),
                  if (metaRightBadge != null)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        metaRightBadge!,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 6),
              Row(
                children: [
                  if (date != null && date!.isNotEmpty) ...[
                    const Icon(Icons.event, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      date!,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (duration != null && duration!.isNotEmpty) ...[
                    const Icon(Icons.schedule, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      duration!,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (location != null && location!.isNotEmpty) ...[
                    const Icon(Icons.location_on_outlined, size: 14),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        location!,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              if (snippet != null) ...[
                const SizedBox(height: 8),
                snippet!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedTitle(
    ThemeData theme,
    String title,
    String? query,
  ) {
    final cleaned = query?.trim() ?? '';
    if (cleaned.isEmpty) {
      return Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final regex = RegExp(RegExp.escape(cleaned), caseSensitive: false);
    final matches = regex.allMatches(title).toList();
    if (matches.isEmpty) {
      return Text(
        title,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var start = 0;
    for (final m in matches) {
      if (m.start > start) {
        spans.add(TextSpan(text: title.substring(start, m.start)));
      }
      spans.add(
        TextSpan(
          text: title.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: theme.colorScheme.tertiaryContainer,
            color: theme.colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = m.end;
    }
    if (start < title.length) {
      spans.add(TextSpan(text: title.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// Standard card used for Only Believe Songs list.
class SongListCard extends StatelessWidget {
  final int number;
  final String title;
  final String subtitle;
  final String? keyBadge;
  final bool isFavorite;
  final String? highlightQuery;
  final VoidCallback? onTap;
  final VoidCallback? onToggleFavorite;

  const SongListCard({
    super.key,
    required this.number,
    required this.title,
    required this.subtitle,
    this.keyBadge,
    this.isFavorite = false,
    this.highlightQuery,
    this.onTap,
    this.onToggleFavorite,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleWidget = _buildHighlightedText(
      theme,
      title,
      highlightQuery,
      theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
    );
    final subtitleWidget = _buildHighlightedText(
      theme,
      subtitle,
      highlightQuery,
      theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text(
                number.toString(),
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  titleWidget,
                  const SizedBox(height: 2),
                  subtitleWidget,
                ],
              ),
            ),
            if (keyBadge != null) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  keyBadge!,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(
                isFavorite ? Icons.favorite : Icons.favorite_border,
                color:
                    isFavorite ? theme.colorScheme.primary : Colors.grey[500],
              ),
              onPressed: onToggleFavorite,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHighlightedText(
    ThemeData theme,
    String text,
    String? query,
    TextStyle? baseStyle,
  ) {
    final cleaned = query?.trim() ?? '';
    if (cleaned.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        overflow: TextOverflow.ellipsis,
      );
    }

    final regex = RegExp(RegExp.escape(cleaned), caseSensitive: false);
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(
        text,
        style: baseStyle,
        overflow: TextOverflow.ellipsis,
      );
    }

    final spans = <TextSpan>[];
    var start = 0;
    for (final m in matches) {
      if (m.start > start) {
        spans.add(TextSpan(text: text.substring(start, m.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(m.start, m.end),
          style: TextStyle(
            backgroundColor: theme.colorScheme.tertiaryContainer,
            color: theme.colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(
        style: baseStyle,
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

