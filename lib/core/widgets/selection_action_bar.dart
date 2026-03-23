import 'package:flutter/material.dart';

class SelectionActionBar extends StatelessWidget {
  final bool isVisible;
  final String? selectedText;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onAddToNote;
  final VoidCallback onDismiss;

  const SelectionActionBar({
    super.key,
    required this.isVisible,
    required this.selectedText,
    required this.onCopy,
    required this.onShare,
    this.onAddToNote,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final text = (selectedText ?? '').trim();

    return SafeArea(
      top: false,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          offset: isVisible ? Offset.zero : const Offset(0, 1),
          child: isVisible
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: Material(
                    elevation: 10,
                    borderRadius: BorderRadius.circular(18),
                    color: cs.inverseSurface,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              text,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: cs.onInverseSurface,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          FilledButton.tonal(
                            onPressed: onCopy,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            child: const Text('Copy'),
                          ),
                          const SizedBox(width: 8),
                          if (onAddToNote != null) ...[
                            FilledButton.icon(
                              onPressed: onAddToNote,
                              icon: const Icon(Icons.note_add_outlined, size: 16),
                              label: const Text('Add to Note'),
                              style: FilledButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          FilledButton(
                            onPressed: onShare,
                            style: FilledButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 14),
                            ),
                            child: const Text('Share'),
                          ),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(
                              Icons.close,
                              color: cs.onInverseSurface.withOpacity(0.9),
                            ),
                            onPressed: onDismiss,
                            visualDensity: VisualDensity.compact,
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ),
    );
  }
}

