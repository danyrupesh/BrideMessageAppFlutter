import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../reader/models/reader_tab.dart';
import '../../sermons/providers/sermon_flow_provider.dart';
import '../../sermons/providers/sermon_provider.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../common/widgets/cards.dart';
import '../../common/widgets/fts_highlight_text.dart';
import '../../onboarding/onboarding_screen.dart';

class SermonResultsTab extends ConsumerWidget {
  const SermonResultsTab({super.key});

  bool _isMissingSermonDbError(String? error) {
    if (error == null) return false;
    final lower = error.toLowerCase();
    return lower.contains('sermon database is not installed') ||
        (lower.contains('database file not found') &&
            lower.contains('sermons_') &&
            lower.contains('.db'));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final yearsAsync = ref.watch(sermonYearsForLangProvider(state.languageCode));
    final sermonDbExists = ref.watch(
      sermonDatabaseExistsProvider(state.languageCode),
    );

    if (sermonDbExists.maybeWhen(
      data: (exists) => !exists,
      orElse: () => false,
    )) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.folder_off_outlined, size: 46),
              const SizedBox(height: 10),
              Text(
                'Sermon database is not installed',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Import Tamil/English sermons database to search sermons.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          const OnboardingScreen(showImportDirectly: true),
                    ),
                  );
                },
                icon: const Icon(Icons.cloud_download_outlined),
                label: const Text('Import Database'),
              ),
            ],
          ),
        ),
      );
    }

    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.error != null) {
      if (_isMissingSermonDbError(state.error)) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.folder_off_outlined, size: 46),
                const SizedBox(height: 10),
                Text(
                  'Sermon database is not installed',
                  style: Theme.of(context).textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                const Text(
                  'Import Tamil/English sermons database to search sermons.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const OnboardingScreen(showImportDirectly: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Import Database'),
                ),
              ],
            ),
          ),
        );
      }
      return Center(
        child: Text(
          'Error: ${state.error}',
          style: const TextStyle(color: Colors.red),
        ),
      );
    }
    if (state.query.isEmpty || state.query.length <= 2) {
      return const Center(child: Text('Type at least 3 characters to search'));
    }
    final results = state.sermonResults;
    final years = yearsAsync.asData?.value ?? const <int>[];
    if (results.isEmpty) {
      return Center(child: Text('No sermons found for "${state.query}"'));
    }

    final hasMore = state.sermonResults.length < state.sermonTotalCount;
    final showFooter = hasMore || state.isLoadingMore;

    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Year range',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      value: state.sermonYearFrom,
                      decoration: const InputDecoration(
                        labelText: 'Year from',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Any'),
                        ),
                        ...years.map(
                          (year) => DropdownMenuItem<int?>(
                            value: year,
                            child: Text(year.toString()),
                          ),
                        ),
                      ],
                      onChanged: years.isEmpty ? null : notifier.updateSermonYearFrom,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int?>(
                      isExpanded: true,
                      value: state.sermonYearTo,
                      decoration: const InputDecoration(
                        labelText: 'Year to',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('Any'),
                        ),
                        ...years.map(
                          (year) => DropdownMenuItem<int?>(
                            value: year,
                            child: Text(year.toString()),
                          ),
                        ),
                      ],
                      onChanged: years.isEmpty ? null : notifier.updateSermonYearTo,
                    ),
                  ),
                ],
              ),
              if (state.sermonYearFrom != null || state.sermonYearTo != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: notifier.clearSermonYearRange,
                    child: const Text('Clear range'),
                  ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        ...results.asMap().entries.map((entry) {
          final index = entry.key;
          final SermonSearchResult r = entry.value;
          return Column(
            children: [
              SermonResultCard(
                id: r.sermonId,
                title: r.title,
                date: r.date ?? '',
                duration: null,
                location: r.location,
                metaRightBadge: r.year?.toString(),
                subtitle: r.paragraphNumber != null ? '¶${r.paragraphNumber}' : null,
                snippet: FtsHighlightText(rawSnippet: r.snippet),
                onTap: () {
                  ref
                      .read(sermonFlowProvider.notifier)
                      .openSermonForLanguage(
                        state.languageCode,
                        ReaderTab(
                          type: ReaderContentType.sermon,
                          title: r.title,
                          sermonId: r.sermonId,
                          initialSearchQuery: state.query,
                          initialFocusParagraph: r.paragraphNumber,
                          openedFromSearch: true,
                        ),
                      );
                  context.push('/sermon-reader');
                },
              ),
              if (index != results.length - 1) const Divider(height: 1),
            ],
          );
        }),
        if (showFooter)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            child: Center(
              child: state.isLoadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonal(
                      onPressed: notifier.loadMoreCurrentTab,
                      child: const Text('Load more'),
                    ),
            ),
          ),
      ],
    );
  }
}
