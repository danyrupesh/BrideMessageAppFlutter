import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../providers/search_provider.dart';
import '../../common/widgets/chips.dart';

class SearchFilters extends ConsumerWidget {
  const SearchFilters({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Row(
            children: [
              PillToggleChip(
                label: 'Smart (all words)',
                selected: state.searchType == SearchType.all,
                onTap: () => notifier.updateSearchType(SearchType.all),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Exact phrase',
                selected: state.searchType == SearchType.exact,
                onTap: () => notifier.updateSearchType(SearchType.exact),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Any word',
                selected: state.searchType == SearchType.any,
                onTap: () => notifier.updateSearchType(SearchType.any),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Prefix (auto)',
                selected: state.searchType == SearchType.prefix,
                onTap: () => notifier.updateSearchType(SearchType.prefix),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Row(
            children: [
              PillToggleChip(
                label: 'Standard rank',
                selected: state.matchMode == MatchMode.exactMatch,
                onTap: () => notifier.updateMatchMode(MatchMode.exactMatch),
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'Accurate rank',
                selected: state.matchMode == MatchMode.accurate,
                onTap: () => notifier.updateMatchMode(MatchMode.accurate),
              ),
              IconButton(
                icon: const Icon(Icons.info_outline, size: 18),
                tooltip:
                    'Ranking only: changes result order, not which verses appear.',
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Standard/Accurate rank only change result order, not which verses appear.',
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Ranking only: changes result order, not which verses appear.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).textTheme.bodySmall?.color
                        ?.withOpacity(0.7),
                  ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Row(
            children: [
              PillToggleChip(
                label: 'EN',
                icon: Icons.book_outlined,
                selected: state.languageCode == 'en',
                onTap: () {
                  if (state.languageCode != 'en') {
                    notifier.toggleLanguage();
                  }
                },
              ),
              const SizedBox(width: 8),
              PillToggleChip(
                label: 'TA',
                icon: Icons.book_outlined,
                selected: state.languageCode == 'ta',
                onTap: () {
                  if (state.languageCode != 'ta') {
                    notifier.toggleLanguage();
                  }
                },
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.help_outline),
                onPressed: () => context.push('/search-help'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
