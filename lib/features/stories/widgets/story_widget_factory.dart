import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_widget_from_html/flutter_widget_from_html.dart';

/// Resolves every `app-image://<key>` src in [html] by calling [loader],
/// then returns a new HTML string with those srcs replaced by
/// `data:image/webp;base64,…` so that HtmlWidget can render them natively.
///
/// Keys that are not found in the DB (loader returns null) are replaced with
/// an empty transparent 1×1 pixel GIF so the layout is not broken.
Future<String> resolveAppImageSrcs(
  String html,
  Future<Uint8List?> Function(String key) loader,
) async {
  // Fast path – no custom images
  if (!html.contains('app-image://')) return html;

  // Collect unique keys
  // Matches both src="app-image://KEY" and src='app-image://KEY'
  // (Python seeder always writes double quotes, but be defensive)
  final keyRe = RegExp("src=[\"']app-image://([a-f0-9]+)[\"']", caseSensitive: false);
  final keys = keyRe.allMatches(html).map((m) => m.group(1)!).toSet();

  if (keys.isEmpty) return html;

  // Fetch all BLOBs in parallel
  final futures = {for (final k in keys) k: loader(k)};
  final resolved = <String, String>{};
  for (final entry in futures.entries) {
    final bytes = await entry.value;
    if (bytes != null && bytes.isNotEmpty) {
      resolved[entry.key] = 'data:image/webp;base64,${base64Encode(bytes)}';
    } else {
      // 1×1 transparent GIF fallback
      resolved[entry.key] =
          'data:image/gif;base64,R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7';
    }
  }

  // Replace in HTML
  return html.replaceAllMapped(keyRe, (m) {
    final quote = html[m.start + 4]; // ' or "
    final uri = resolved[m.group(1)!]!;
    return 'src=$quote$uri$quote';
  });
}

/// Renders story HTML inside a styled card.
/// Images embedded as `app-image://KEY` are served from the DB BLOB table
/// by [imageLoader] and inlined as base64 data URIs before rendering.
class StoryHtmlView extends StatefulWidget {
  const StoryHtmlView({
    super.key,
    required this.html,
    required this.imageLoader,
    required this.fontSize,
    required this.lineHeight,
    this.fontFamily,
  });

  final String html;
  final Future<Uint8List?> Function(String key) imageLoader;
  final double fontSize;
  final double lineHeight;
  final String? fontFamily;

  @override
  State<StoryHtmlView> createState() => _StoryHtmlViewState();
}

class _StoryHtmlViewState extends State<StoryHtmlView> {
  late Future<String> _resolved;

  @override
  void initState() {
    super.initState();
    _resolved = resolveAppImageSrcs(widget.html, widget.imageLoader);
  }

  @override
  void didUpdateWidget(StoryHtmlView old) {
    super.didUpdateWidget(old);
    // Re-resolve only when the HTML itself changes (e.g. different story)
    if (old.html != widget.html) {
      _resolved = resolveAppImageSrcs(widget.html, widget.imageLoader);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return FutureBuilder<String>(
      future: _resolved,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 48),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final htmlText = snap.data ?? widget.html;
        return HtmlWidget(
          htmlText,
          textStyle: TextStyle(
            fontSize: widget.fontSize.clamp(12.0, 56.0),
            height: widget.lineHeight,
            fontFamily: widget.fontFamily,
            color: cs.onSurface,
          ),
          customStylesBuilder: (element) {
            switch (element.localName) {
              case 'img':
                return {
                  'max-width': '100%',
                  'display': 'block',
                  'margin': '12px auto',
                };
              case 'h1':
              case 'h2':
              case 'h3':
                return {
                  'color': _toHex(cs.primary),
                  'font-weight': 'bold',
                  'margin-top': '16px',
                };
              case 'blockquote':
                return {
                  'border-left': '4px solid ${_toHex(cs.primary)}',
                  'padding-left': '12px',
                  'color': _toHex(cs.onSurfaceVariant),
                  'font-style': 'italic',
                };
              case 'a':
                return {'color': _toHex(cs.primary)};
              default:
                return null;
            }
          },
        );
      },
    );
  }
}

String _toHex(Color c) {
  final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
  final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
  final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
  return '#$r$g$b';
}
