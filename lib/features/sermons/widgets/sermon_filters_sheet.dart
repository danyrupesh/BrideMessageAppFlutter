import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/widgets/responsive_bottom_sheet.dart';
import '../providers/sermon_provider.dart';

class SermonFiltersSheet extends ConsumerStatefulWidget {
  const SermonFiltersSheet({super.key});

  static void show(BuildContext context, WidgetRef ref) {
    showResponsiveBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => const SermonFiltersSheet(),
    );
  }

  @override
  ConsumerState<SermonFiltersSheet> createState() => _SermonFiltersSheetState();
}

class _SermonFiltersSheetState extends ConsumerState<SermonFiltersSheet> {
  int? _selectedYear;
  RangeValues? _yearRange;
  String _sortBy = 'year_asc';
  int? _yearFromOverride;
  int? _yearToOverride;

  @override
  void initState() {
    super.initState();
    final state = ref.read(sermonListProvider);
    _selectedYear = state.selectedYear;
    _sortBy = state.sortBy;
    _yearFromOverride = state.yearFrom;
    _yearToOverride = state.yearTo;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final yearsAsync = ref.watch(availableYearsProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Search Filters',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          yearsAsync.when(
            data: (years) {
              if (years.isEmpty) {
                return const SizedBox.shrink();
              }
              final minYear = years.first;
              final maxYear = years.last;
              _yearRange ??= RangeValues(
                (_yearFromOverride ?? minYear).toDouble(),
                (_yearToOverride ?? maxYear).toDouble(),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Year',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<int?>(
                    value: _selectedYear,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Select a year',
                    ),
                    items: [
                      const DropdownMenuItem<int?>(
                        value: null,
                        child: Text('All Years'),
                      ),
                      ...years.map(
                        (y) => DropdownMenuItem<int?>(
                          value: y,
                          child: Text(y.toString()),
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedYear = val;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Year Range',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  RangeSlider(
                    min: minYear.toDouble(),
                    max: maxYear.toDouble(),
                    values: _yearRange!,
                    divisions: (maxYear - minYear).clamp(1, 50),
                    labels: RangeLabels(
                      _yearRange!.start.round().toString(),
                      _yearRange!.end.round().toString(),
                    ),
                    onChanged: (values) {
                      setState(() {
                        _yearRange = values;
                      });
                    },
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sort By',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          RadioListTile<String>(
            title: const Text('Year Ascending'),
            value: 'year_asc',
            groupValue: _sortBy,
            onChanged: (val) {
              setState(() => _sortBy = val ?? 'year_asc');
            },
          ),
          RadioListTile<String>(
            title: const Text('Year Descending'),
            value: 'year_desc',
            groupValue: _sortBy,
            onChanged: (val) {
              setState(() => _sortBy = val ?? 'year_asc');
            },
          ),
          RadioListTile<String>(
            title: const Text('Name Ascending'),
            value: 'name_asc',
            groupValue: _sortBy,
            onChanged: (val) {
              setState(() => _sortBy = val ?? 'year_asc');
            },
          ),
          RadioListTile<String>(
            title: const Text('Name Descending'),
            value: 'name_desc',
            groupValue: _sortBy,
            onChanged: (val) {
              setState(() => _sortBy = val ?? 'year_asc');
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    final state = ref.read(sermonListProvider);
                    setState(() {
                      _selectedYear = null;
                      _sortBy = 'year_asc';
                      _yearRange = null;
                    });
                    ref.read(sermonListProvider.notifier).filterSermons(
                          year: null,
                          query: state.searchQuery,
                          sortBy: 'year_asc',
                        );
                    Navigator.pop(context);
                  },
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    final state = ref.read(sermonListProvider);
                    final rangeStart = _yearRange?.start.round();
                    final rangeEnd = _yearRange?.end.round();
                    ref.read(sermonListProvider.notifier).filterSermons(
                          year: _selectedYear,
                          query: state.searchQuery,
                          sortBy: _sortBy,
                          yearFrom: _selectedYear == null ? rangeStart : null,
                          yearTo: _selectedYear == null ? rangeEnd : null,
                        );
                    Navigator.pop(context);
                  },
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

