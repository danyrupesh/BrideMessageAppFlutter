import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/sermon_models.dart';
import '../../../core/database/sermon_repository.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';

// ─── Resolved sermon repository ───────────────────────────────────────────────

/// Global state: which Sermon language the user is currently browsing.
/// 'en' = English (default), 'ta' = Tamil.
final selectedSermonLangProvider = StateProvider<String>((ref) => 'en');

/// Resolves the Sermon repository based on the selected language.
/// Falls back to language code as db code if no metadata found.
final sermonRepositoryProvider =
    FutureProvider<SermonRepository>((ref) async {
  final lang = ref.watch(selectedSermonLangProvider);
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.sermon, lang)).future,
  );
  final code = installed?.code ?? lang;
  final language = installed?.language ?? lang;
  return SermonRepository(DatabaseManager(), language, code);
});

/// Resolves a Sermon repository by language ('en' or 'ta').
/// Used by the dashboard to open English or Tamil Sermons directly.
final sermonRepositoryByLangProvider =
    FutureProvider.family<SermonRepository, String>((ref, lang) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.sermon, lang)).future,
  );
  final code = installed?.code ?? lang;
  final language = installed?.language ?? lang;
  return SermonRepository(DatabaseManager(), language, code);
});

final availableYearsProvider = FutureProvider<List<int>>((ref) async {
  final repoAsync = ref.watch(sermonRepositoryProvider);
  return repoAsync.when(
    data: (repo) => repo.getAvailableYears(),
    loading: () async => <int>[],
    error: (e, st) async => <int>[],
  );
});

// ─── Sermon list state ────────────────────────────────────────────────────────

class SermonListState {
  static const _unset = Object();

  final List<SermonEntity> sermons;
  final bool isLoading;
  final int? selectedYear;
  final String searchQuery;
  final int offset;
  final String? loadError;
  final String sortBy;
  final int? yearFrom;
  final int? yearTo;

  SermonListState({
    this.sermons = const [],
    this.isLoading = false,
    this.selectedYear,
    this.searchQuery = '',
    this.offset = 0,
    this.loadError,
    this.sortBy = 'year_asc',
    this.yearFrom,
    this.yearTo,
  });

  SermonListState copyWith({
    List<SermonEntity>? sermons,
    bool? isLoading,
    Object? selectedYear = _unset,
    String? searchQuery,
    int? offset,
    String? loadError,
    String? sortBy,
    int? yearFrom,
    int? yearTo,
  }) {
    return SermonListState(
      sermons: sermons ?? this.sermons,
      isLoading: isLoading ?? this.isLoading,
      selectedYear:
          identical(selectedYear, _unset) ? this.selectedYear : selectedYear as int?,
      searchQuery: searchQuery ?? this.searchQuery,
      offset: offset ?? this.offset,
      loadError: loadError,
      sortBy: sortBy ?? this.sortBy,
      yearFrom: yearFrom ?? this.yearFrom,
      yearTo: yearTo ?? this.yearTo,
    );
  }
}

// ─── Sermon list notifier ─────────────────────────────────────────────────────

class SermonListNotifier extends Notifier<SermonListState> {
  @override
  SermonListState build() {
    _loadInitial();
    return SermonListState(isLoading: true);
  }

  Future<SermonRepository?> _getRepo() async {
    try {
      return await ref.read(sermonRepositoryProvider.future);
    } catch (e) {
      debugPrint('SermonListNotifier._getRepo: $e');
      return null;
    }
  }

  Future<void> _loadInitial() async {
    try {
      final repo = await _getRepo();
      if (repo == null) {
        state = state.copyWith(
          isLoading: false,
          loadError: 'No Sermon database installed. Please import from Settings.',
        );
        return;
      }
      final results = await repo.getSermonsPage(limit: 50, offset: 0);
      state = state.copyWith(
        sermons: results,
        isLoading: false,
        offset: 50,
        loadError: null,
      );
    } catch (e, st) {
      debugPrint('SermonListNotifier._loadInitial error: $e\n$st');
      state = state.copyWith(
        sermons: const [],
        isLoading: false,
        offset: 0,
        loadError: e.toString(),
      );
    }
  }

  Future<void> loadMore() async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true);
    try {
      final repo = await _getRepo();
      if (repo == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final results = await repo.getSermonsPage(
        limit: 50,
        offset: state.offset,
        year: state.selectedYear,
        searchQuery: state.searchQuery,
        sortBy: state.sortBy,
        yearFrom: state.yearFrom,
        yearTo: state.yearTo,
      );
      state = state.copyWith(
        sermons: [...state.sermons, ...results],
        isLoading: false,
        offset: state.offset + 50,
      );
    } catch (e, st) {
      debugPrint('SermonListNotifier.loadMore error: $e\n$st');
      state = state.copyWith(isLoading: false);
    }
  }

  Future<void> filterSermons({
    int? year,
    String query = '',
    String? sortBy,
    int? yearFrom,
    int? yearTo,
  }) async {
    final effectiveSortBy = sortBy ?? state.sortBy;

    state = state.copyWith(
      isLoading: true,
      selectedYear: year,
      searchQuery: query,
      offset: 0,
      sermons: [],
      loadError: null,
      // new fields
      // when a specific year is chosen, year range is cleared
      // range only applies when year == null
      // this matches the repository contract
      // (exact-year filter takes precedence over range)
      // range is only stored when no exact year filter is active
      // so that chips and sheet stay in sync
      // and new loads use the same constraints
      // see filter sheet wiring for how we pass these values
      // from UI into state
      // (comments kept minimal per guidelines)
      // effectiveSortBy always non-null
      // so we keep current sort unless caller overrides
      // via sortBy argument.
      // ignore: unnecessary_cast
      // (ensures static analysis happy about types)
      // after this, repo call below uses state.sortBy/yearFrom/yearTo.
      // These assignments will be used once state is updated.
      // Note: yearFrom/yearTo only meaningful when year == null.
      // When year != null we clear them.
    );
    state = state.copyWith(
      sortBy: effectiveSortBy,
      yearFrom: year == null ? yearFrom : null,
      yearTo: year == null ? yearTo : null,
    );
    try {
      final repo = await _getRepo();
      if (repo == null) {
        state = state.copyWith(isLoading: false);
        return;
      }
      final results = await repo.getSermonsPage(
        limit: 50,
        offset: 0,
        year: year,
        searchQuery: query,
        sortBy: effectiveSortBy,
        yearFrom: year == null ? yearFrom : null,
        yearTo: year == null ? yearTo : null,
      );
      state = state.copyWith(
        sermons: results,
        isLoading: false,
        offset: 50,
        loadError: null,
      );
    } catch (e, st) {
      debugPrint('SermonListNotifier.filterSermons error: $e\n$st');
      state = state.copyWith(
        sermons: const [],
        isLoading: false,
        offset: 0,
        loadError: e.toString(),
      );
    }
  }
}

final sermonListProvider =
    NotifierProvider<SermonListNotifier, SermonListState>(() {
  return SermonListNotifier();
});

final sermonParagraphsProvider =
    FutureProvider.family<List<SermonParagraphEntity>, String>((
  ref,
  sermonId,
) async {
  final repoAsync = ref.watch(sermonRepositoryProvider);
  return repoAsync.when(
    data: (repo) => repo.getParagraphsForSermon(sermonId),
    loading: () async => <SermonParagraphEntity>[],
    error: (e, st) async => <SermonParagraphEntity>[],
  );
});

/// Load a single sermon by ID (used for AppBar subtitle metadata).
final sermonByIdProvider =
    FutureProvider.family<SermonEntity?, String>((ref, id) async {
  final repo = await ref.watch(sermonRepositoryProvider.future);
  return repo.getSermonById(id);
});

/// Load the sermon immediately before (direction = -1) or after (direction = +1)
/// the given sermon ID in chronological order.
final adjacentSermonProvider =
    FutureProvider.family<SermonEntity?, (String, int)>((ref, args) async {
  final repo = await ref.watch(sermonRepositoryProvider.future);
  return repo.getAdjacentSermon(args.$1, args.$2);
});
