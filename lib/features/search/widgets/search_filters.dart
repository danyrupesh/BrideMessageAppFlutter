import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/search_provider.dart';
import '../../common/widgets/chips.dart';

/// Dialog widget that exposes all search filter controls.
/// Shown via [showSearchFiltersSheet] as a centered popup dialog.
class SearchFiltersSheet extends ConsumerWidget {
  const SearchFiltersSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final isSongs = state.activeTab == SearchTab.songs;
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      // Constrain max width — dialog fits content, doesn't span the full screen
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: IntrinsicWidth(
        stepWidth: 56,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Search Mode ─────────────────────────────────────────────────
            Text('Search Mode', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                PillToggleChip(
                  label: 'Smart (all words)',
                  selected: state.searchType == SearchType.all,
                  onTap: () => notifier.updateSearchType(SearchType.all),
                ),
                PillToggleChip(
                  label: 'Exact phrase',
                  selected: state.searchType == SearchType.exact,
                  onTap: () => notifier.updateSearchType(SearchType.exact),
                ),
                PillToggleChip(
                  label: 'Any word',
                  selected: state.searchType == SearchType.any,
                  onTap: () => notifier.updateSearchType(SearchType.any),
                ),
                PillToggleChip(
                  label: 'Prefix (auto)',
                  selected: state.searchType == SearchType.prefix,
                  onTap: () => notifier.updateSearchType(SearchType.prefix),
                ),
              ],
            ),

            // ── Accuracy ────────────────────────────────────────────────────
            const SizedBox(height: 20),
            Text('Accuracy', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                PillToggleChip(
                  label: 'Standard',
                  selected: state.matchMode == MatchMode.exactMatch,
                  onTap: () => notifier.updateMatchMode(MatchMode.exactMatch),
                ),
                PillToggleChip(
                  label: 'Accurate',
                  selected: state.matchMode == MatchMode.accurate,
                  onTap: () => notifier.updateMatchMode(MatchMode.accurate),
                ),
              ],
            ),

            // ── Songs: Lyrics toggle ─────────────────────────────────────
            if (isSongs) ...[
              const SizedBox(height: 20),
              Text('Options', style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              PillToggleChip(
                label: 'Search Lyrics',
                icon: Icons.library_music,
                selected: state.searchLyrics,
                onTap: notifier.toggleSearchLyrics,
              ),
            ],

            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Done'),
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }
}

/// Convenience function to show the filters as a centered popup dialog.
void showSearchFiltersSheet(BuildContext context) {
  showDialog(
    context: context,
    builder: (_) => const SearchFiltersSheet(),
  );
}
