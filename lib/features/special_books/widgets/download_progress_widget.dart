import 'package:flutter/material.dart';

import '../providers/special_book_download_provider.dart';

class DownloadProgressWidget extends StatelessWidget {
  const DownloadProgressWidget({super.key, required this.state});

  final BookDownloadState state;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (state.hasError) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: cs.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.error!,
                style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    if (state.isComplete) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: cs.onPrimaryContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                state.statusMessage,
                style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  value: state.progress > 0 ? state.progress : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  state.statusMessage.isEmpty
                      ? 'Working...'
                      : state.statusMessage,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Text(
                '${(state.progress * 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.outline,
                  fontVariations: const [FontVariation('wght', 600)],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: state.progress > 0 ? state.progress : null,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ),
    );
  }
}
