import 'package:flutter/material.dart';

class ReadingPane extends StatefulWidget {
  final Widget child;
  final bool isSearchActive;
  final TextEditingController? searchController;
  final FocusNode? searchFocusNode;
  final String matchCounterText;
  final VoidCallback? onPrevMatch;
  final VoidCallback? onNextMatch;
  final VoidCallback? onCloseSearch;
  final ValueChanged<String>? onSearchChanged;

  const ReadingPane({
    super.key,
    required this.child,
    this.isSearchActive = false,
    this.searchController,
    this.searchFocusNode,
    this.matchCounterText = '0/0',
    this.onPrevMatch,
    this.onNextMatch,
    this.onCloseSearch,
    this.onSearchChanged,
  });

  @override
  State<ReadingPane> createState() => _ReadingPaneState();
}

class _ReadingPaneState extends State<ReadingPane> {
  late final ScrollController _paneScrollController;

  @override
  void initState() {
    super.initState();
    _paneScrollController = ScrollController();
  }

  @override
  void dispose() {
    _paneScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.isSearchActive)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.searchController,
                    focusNode: widget.searchFocusNode,
                    decoration: const InputDecoration(
                      isDense: true,
                      hintText: 'Search in pane...',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: widget.onSearchChanged,
                  ),
                ),
                const SizedBox(width: 8),
                Text(widget.matchCounterText),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onPrevMatch,
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onNextMatch,
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onCloseSearch,
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
        Expanded(child: widget.child),
      ],
    );
  }
}
