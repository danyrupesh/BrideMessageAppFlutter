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
  final String? leadingIdOverride;
  final String title;
  final String date;
  final String? duration;
  final String? location;
  final String? metaRightBadge;
  final String? subtitle;
  final Widget? snippet;
  final String? highlightQuery;
  final double fontSize;
  final VoidCallback? onTap;
  final VoidCallback? onCopy;
  final VoidCallback? onShare;

  const SermonResultCard({
    super.key,
    required this.id,
    this.leadingIdOverride,
    required this.title,
    required this.date,
    this.duration,
    this.location,
    this.metaRightBadge,
    this.subtitle,
    this.snippet,
    this.highlightQuery,
    this.fontSize = 14.0,
    this.onTap,
    this.onCopy,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontSize: fontSize + 2,
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontSize: fontSize - 1,
    );
    final subtitleStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.w600,
      fontSize: fontSize - 0.5,
    );
    final snippetStyle = theme.textTheme.bodyMedium?.copyWith(
      fontSize: fontSize,
      height: 1.35,
    );

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildHighlightedTitle(
                          context,
                          title,
                          highlightQuery,
                          titleStyle,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(date, style: metaStyle),
                            if (duration != null) ...[
                              const Text(' • '),
                              Text(duration!, style: metaStyle),
                            ],
                          ],
                        ),
                        if (location != null && location!.isNotEmpty)
                          Text(location!, style: metaStyle),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (metaRightBadge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            metaRightBadge!,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSecondaryContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                    ],
                  ),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle!, style: subtitleStyle),
              ],
              if (snippet != null) ...[
                const SizedBox(height: 12),
                DefaultTextStyle.merge(
                  style: snippetStyle ?? const TextStyle(fontSize: 14),
                  child: snippet!,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedTitle(
    BuildContext context,
    String text,
    String? query,
    TextStyle? titleStyle,
  ) {
    final theme = Theme.of(context);
    final baseStyle =
        titleStyle ??
        theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600);
    return _HighlightText(
      text: text,
      query: query,
      baseStyle: baseStyle,
      highlightColor: theme.colorScheme.primaryContainer,
      onHighlightColor: theme.colorScheme.onPrimaryContainer,
    );
  }
}

class _HighlightText extends StatelessWidget {
  final String text;
  final String? query;
  final TextStyle? baseStyle;
  final Color highlightColor;
  final Color onHighlightColor;

  const _HighlightText({
    required this.text,
    this.query,
    this.baseStyle,
    required this.highlightColor,
    required this.onHighlightColor,
  });

  @override
  Widget build(BuildContext context) {
    final cleaned = query?.trim() ?? '';
    if (cleaned.isEmpty) {
      return Text(text, style: baseStyle);
    }

    final regex = RegExp(RegExp.escape(cleaned), caseSensitive: false);
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle);
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
            backgroundColor: highlightColor,
            color: onHighlightColor,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
      start = m.end;
    }
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
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
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                color: isFavorite
                    ? theme.colorScheme.primary
                    : Colors.grey[500],
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
      return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);
    }

    final regex = RegExp(RegExp.escape(cleaned), caseSensitive: false);
    final matches = regex.allMatches(text).toList();
    if (matches.isEmpty) {
      return Text(text, style: baseStyle, overflow: TextOverflow.ellipsis);
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
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}
