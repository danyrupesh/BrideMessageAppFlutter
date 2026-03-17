import 'dart:io';

void main() {
  final file = File(r'E:\Freelance\BrideMessageApp\AppFlutter\lib\features\sermons\sermon_reader_screen.dart');
  var content = file.readAsStringSync();
  final initialContent = content;

  void replace(String from, String to, String label, {bool isRegExp = false, int expectedCount = 1}) {
    int count = 0;
    if (isRegExp) {
      final regExp = RegExp(from);
      count = regExp.allMatches(content).length;
      content = content.replaceAll(regExp, to);
    } else {
      var idx = 0;
      while (true) {
        idx = content.indexOf(from, idx);
        if (idx == -1) break;
        count++;
        idx += from.length;
      }
      content = content.replaceAll(from, to);
    }
    print('[\$label] Expected replacements: \$expectedCount. Found: \$count');
    if (count == 0) {
      print('WARNING: Replacement failed for \$label');
    }
  }

  // 1. Remove state variables
  replace(
    '  final Set<int> _selectedParagraphIndices = {};\n  int? _lastParagraphTappedIndex;\n',
    '',
    'Remove state variables',
  );

  // 2. Remove clearings
  replace(
    '      _selectedParagraphIndices.clear();\n      _lastParagraphTappedIndex = null;\n',
    '',
    'Remove root clearings',
    expectedCount: 4, 
  );
  replace(
    '            _selectedParagraphIndices.clear();\n            _lastParagraphTappedIndex = null;\n',
    '',
    'Remove 3-indent clearings',
    expectedCount: 1,
  );
  replace(
    '              _selectedParagraphIndices.clear();\n              _lastParagraphTappedIndex = null;\n',
    '',
    'Remove 4-indent clearings',
    expectedCount: 2,
  );

  // 3. toggleParagraphSelection and others
  replace(
    r'  void _toggleParagraphSelection\(int index\) \{[\s\S]*?bool get _isDesktopPlatform',
    '  bool get _isDesktopPlatform',
    'Remove _toggleParagraphSelection',
    isRegExp: true,
  );

  // 4. _hasAnySelection
  replace(
    '    return textSelected ||\n        _selectedParagraphIndices.isNotEmpty ||\n        _selectedVerseNumbers.isNotEmpty;\n',
    '    return textSelected ||\n        _selectedVerseNumbers.isNotEmpty;\n',
    'Update _hasAnySelection',
  );

  // 5. _hasSelectionPopover
  replace(
    '    return textSelected || _selectedParagraphIndices.isNotEmpty;\n',
    '    return textSelected;\n',
    'Update _hasSelectionPopover',
  );

  // 6. _clearSelectionPopover
  replace(
    '      _activeSelectionText = null;\n      _selectedParagraphIndices.clear();\n      _lastParagraphTappedIndex = null;\n',
    '      _activeSelectionText = null;\n',
    'Update _clearSelectionPopover',
  );

  // 7. _copyCurrentSelection
  replace(
    '    if (_selectedParagraphIndices.isNotEmpty) {\n      _copySelectedParagraphs();\n      return;\n    }\n',
    '',
    'Update _copyCurrentSelection',
  );

  // 8. _shareCurrentSelection
  replace(
    '    if (_selectedParagraphIndices.isNotEmpty) {\n      _shareSelectedParagraphs();\n      return;\n    }\n',
    '',
    'Update _shareCurrentSelection',
  );

  // 9. _copySelectedParagraphs, _shareSelectedParagraphs, _buildSelectedParagraphsPayload
  replace(
    r'  void _copySelectedParagraphs\(\) \{[\s\S]*?// ── PDF generation \(Sermon\) ──────────────────────────────────────────────',
    '// ── PDF generation (Sermon) ──────────────────────────────────────────────',
    'Remove paragraph copy/share logic',
    isRegExp: true,
  );

  // 10. Default AppBar
  replace(
    '    final hasParagraphSelection = _selectedParagraphIndices.isNotEmpty;\n',
    '',
    'Remove hasParagraphSelection from app bar',
  );
  
  replace(
    '''        ] else if (!isOnBibleTab && hasParagraphSelection) ...[
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copySelectedParagraphs,
          ),
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: _shareSelectedParagraphs,
          ),
          IconButton(
            icon: const Icon(Icons.clear),
            onPressed: () => setState(() {
              _selectedParagraphIndices.clear();
              _lastParagraphTappedIndex = null;
            }),
          ),
        ] else ...[''',
    '''        ] else ...[''',
    'Remove paragraph specific app bar buttons',
  );

  // 11. Rename _buildSermonParagraphList to _buildSermonBody and update the method signature in the usage
  replace(
    '          final sermonList = _buildSermonParagraphList(\n',
    '          final sermonList = _buildSermonBody(\n',
    'Rename buildSermonParagraphList usage',
  );

  // 12. Replace the actual _buildSermonParagraphList implementation
  final newBuildBody = """
  Widget _buildSermonBody(
    List<SermonParagraphEntity> paragraphs,
    TypographySettings typography,
    ColorScheme cs,
  ) {
    final baseStyle = Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontSize: typography.fontSize,
              height: typography.lineHeight,
              fontFamily: typography.resolvedFontFamily,
            ) ??
            const TextStyle();
    final highlightStyle = baseStyle;
    final currentMatchStyle = TextStyle(
      backgroundColor: Colors.yellow.shade300,
      color: Colors.black,
      fontWeight: FontWeight.bold,
    );
    final currentItemIndex = _matchVerseIndices.isNotEmpty
        ? _matchVerseIndices[_currentMatchIndex]
        : null;

    final children = <InlineSpan>[];
    for (var i = 0; i < paragraphs.length; i++) {
        final paragraph = paragraphs[i];
        final key = i < _verseKeys.length ? _verseKeys[i] : GlobalKey();
        final currentOccurrence = _currentOccurrenceForItem(i);

        children.add(WidgetSpan(child: SizedBox(key: key)));

        if (paragraph.paragraphNumber != null) {
            children.add(
                TextSpan(
                    text: '\${paragraph.paragraphNumber}\\u00B6 ',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: typography.fontSize * 0.8,
                        color: Colors.grey,
                    ),
                ),
            );
        }

        children.addAll(_buildHighlightedSpans(
            paragraph.text,
            baseStyle,
            highlightStyle,
            currentMatchStyle,
            currentOccurrenceIndex: currentOccurrence,
        ));

        if (i < paragraphs.length - 1) {
            children.add(TextSpan(text: '\\n\\n', style: baseStyle));
        }
    }

    final combinedSpan = TextSpan(children: children, style: baseStyle);

    final plainText = paragraphs.map((p) {
        final prefix = p.paragraphNumber != null ? '\${p.paragraphNumber}\\u00B6 ' : '';
        return '\\uFFFC\$prefix\${p.text}';
    }).join('\\n\\n');

    return Stack(
      children: [
        SelectionArea(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: SelectableText.rich(
              combinedSpan,
              onSelectionChanged: (selection, cause) {
                if (selection.start == selection.end) {
                  if (_activeSelectionText != null) {
                    setState(() => _activeSelectionText = null);
                  }
                  return;
                }
                final start = selection.start.clamp(0, plainText.length);
                final end = selection.end.clamp(0, plainText.length);
                if (start >= end) return;
                final selected = plainText.substring(start, end)
                    .replaceAll('\\uFFFC', '')
                    .trim();
                if (selected.isEmpty) return;
                setState(() {
                  _activeSelectionText = selected;
                });
              },
            ),
          ),
        ),
        Positioned.fill(
          child: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 6,
              child: _buildMatchMarkers(
                paragraphs.length,
                _matchVerseIndices,
                currentItemIndex,
                enabled: _isSearching && !_searchAllSermons,
              ),
            ),
          ),
        ),
        if (_hasSelectionPopover)
          Positioned(
            left: 16,
            right: 16,
            bottom: 12,
            child: SafeArea(
              top: false,
              child: _buildSelectionPopover(cs),
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionPopover(ColorScheme cs) {
    final theme = Theme.of(context);
    const label = 'Text selected';
    return Material(""";

  replace(
    r'  Widget _buildSermonParagraphList\([\s\S]*?return Material\(',
    newBuildBody,
    'Replace _buildSermonParagraphList with _buildSermonBody and update _buildSelectionPopover signature',
    isRegExp: true,
  );
  
  // also need to clean up an extra selection count from _buildSelectionPopover since we replaced its signature block
  replace(
    '  Widget _buildSelectionPopover(ColorScheme cs) {\n    final theme = Theme.of(context);\n    final selectionCount = _selectedParagraphIndices.length;\n    final label = selectionCount > 0\n        ? \'\$selectionCount paragraph\${selectionCount == 1 ? \'\' : \'s\'} selected\'\n        : \'Text selected\';\n    return Material(',
    newBuildBody.split('  Widget _buildSelectionPopover(ColorScheme cs) {').last,
    'Oops _buildSermonParagraphList might not have snagged it correctly due to my previous regex, if so regex will be count=1, otherwise this one is 0.',
    expectedCount: 0 // likely 0 if regex above worked
  );


  if (content != initialContent) {
    file.writeAsStringSync(content);
    print("Successfully transformed sermon_reader_screen.dart");
  } else {
    print("WARNING: No changes made to file.");
  }
}
