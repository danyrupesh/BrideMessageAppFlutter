import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/sermon_models.dart';
import '../../../core/database/sermon_repository.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../search/providers/search_provider.dart';

// ─── Resolved sermon repository ───────────────────────────────────────────────

/// Global state: which Sermon language the user is currently browsing.
/// 'en' = English (default), 'ta' = Tamil.
class _SermonLangNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  void setLang(String lang) => state = lang;
}

final selectedSermonLangProvider =
    NotifierProvider<_SermonLangNotifier, String>(_SermonLangNotifier.new);

final sermonDatabaseExistsProvider = FutureProvider.family<bool, String>((
  ref,
  lang,
) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.sermon, lang)).future,
  );
  final code = installed?.code ?? lang;
  final dbPath = await DatabaseManager().getDatabasePath('sermons_$code.db');
  return File(dbPath).exists();
});

/// Resolves the Sermon repository based on the selected language.
/// Falls back to language code as db code if no metadata found.
final sermonRepositoryProvider = FutureProvider<SermonRepository>((ref) async {
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

final sermonCountByLangProvider = FutureProvider.family<int, String>((
  ref,
  lang,
) async {
  final repo = await ref.watch(sermonRepositoryByLangProvider(lang).future);
  return repo.getSermonCount();
});

/// Prefer persisted metadata count captured right after import.
/// Falls back to a live DB count when metadata is unavailable.
final sermonStoredCountByLangProvider = FutureProvider.family<int, String>((
  ref,
  lang,
) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.sermon, lang)).future,
  );
  final cached = installed?.recordCount;
  if (cached != null && cached > 0) return cached;
  final repo = await ref.watch(sermonRepositoryByLangProvider(lang).future);
  return repo.getSermonCount();
});

final sermonStoredCountByLangAndCategoryProvider =
    FutureProvider.family<int, ({String lang, String category})>((
      ref,
      params,
    ) async {
      final repo = await ref.watch(
        sermonRepositoryByLangProvider(params.lang).future,
      );
      return repo.getSermonCountByCategory(params.category);
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
  final String? titlePrefix;
  final String? categoryFilter;
  final int offset;
  final String? loadError;
  final String sortBy;
  final int? yearFrom;
  final int? yearTo;
  final List<String>? allowedIds;
  final MatchMode matchMode;
  final List<SermonSearchResult> searchResults;
  final SearchType searchType;

  SermonListState({
    this.sermons = const [],
    this.isLoading = false,
    this.selectedYear,
    this.searchQuery = '',
    this.titlePrefix,
    this.categoryFilter,
    this.offset = 0,
    this.loadError,
    this.sortBy = 'year_asc',
    this.yearFrom,
    this.yearTo,
    this.allowedIds,
    this.matchMode = MatchMode.exactMatch,
    this.searchResults = const [],
    this.searchType = SearchType.prefix,
  });

  SermonListState copyWith({
    List<SermonEntity>? sermons,
    bool? isLoading,
    Object? selectedYear = _unset,
    String? searchQuery,
    Object? titlePrefix = _unset,
    Object? categoryFilter = _unset,
    int? offset,
    String? loadError,
    String? sortBy,
    int? yearFrom,
    int? yearTo,
    Object? allowedIds = _unset,
    MatchMode? matchMode,
    List<SermonSearchResult>? searchResults,
    SearchType? searchType,
  }) {
    return SermonListState(
      sermons: sermons ?? this.sermons,
      isLoading: isLoading ?? this.isLoading,
      selectedYear: identical(selectedYear, _unset)
          ? this.selectedYear
          : selectedYear as int?,
      searchQuery: searchQuery ?? this.searchQuery,
      titlePrefix: identical(titlePrefix, _unset)
          ? this.titlePrefix
          : titlePrefix as String?,
        categoryFilter: identical(categoryFilter, _unset)
          ? this.categoryFilter
          : categoryFilter as String?,
      offset: offset ?? this.offset,
      loadError: loadError,
      sortBy: sortBy ?? this.sortBy,
      yearFrom: yearFrom ?? this.yearFrom,
      yearTo: yearTo ?? this.yearTo,
      allowedIds: identical(allowedIds, _unset)
          ? this.allowedIds
          : allowedIds as List<String>?,
      matchMode: matchMode ?? this.matchMode,
      searchResults: searchResults ?? this.searchResults,
      searchType: searchType ?? this.searchType,
    );
  }
}

// ─── Sermon list notifier ─────────────────────────────────────────────────────

class SermonListNotifier extends Notifier<SermonListState> {
  @override
  SermonListState build() {
    ref.watch(selectedSermonLangProvider);
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
          loadError:
              'No Sermon database installed. Please import from Settings.',
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
      final useTitlePrefix =
          state.titlePrefix != null && state.titlePrefix!.trim().isNotEmpty;
      final titlePrefix = useTitlePrefix ? state.titlePrefix!.trim() : null;
      final query = state.searchQuery.trim();

      if (state.searchType == SearchType.all) {
        final yearFrom = state.selectedYear ?? state.yearFrom;
        final yearTo = state.selectedYear ?? state.yearTo;
        final results = await repo.searchSermons(
          query: query,
          limit: 50,
          offset: state.offset,
          exactMatch: state.searchType == SearchType.exact,
          anyWord: state.searchType == SearchType.any,
          prefixOnly: state.searchType == SearchType.prefix,
          accurateMatch: state.matchMode == MatchMode.accurate,
          yearFrom: yearFrom,
          yearTo: yearTo,
        );
        state = state.copyWith(
          searchResults: [...state.searchResults, ...results],
          isLoading: false,
          offset: state.offset + 50,
        );
        return;
      }

      final results = await _getSermonsPageWithPrefixFallback(
        repo: repo,
        limit: 50,
        offset: state.offset,
        year: state.selectedYear,
        query: useTitlePrefix ? query : state.searchQuery,
        titlePrefix: titlePrefix,
        categoryFilter: state.categoryFilter,
        sortBy: state.sortBy,
        yearFrom: state.yearFrom,
        yearTo: state.yearTo,
        allowedIds: state.allowedIds,
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
    String? titlePrefix,
    String? categoryFilter,
    String? sortBy,
    int? yearFrom,
    int? yearTo,
    List<String>? allowedIds,
    SearchType? searchType,
    MatchMode? matchMode,
  }) async {
    final effectiveSortBy = sortBy ?? state.sortBy;
    final effectiveSearchType = searchType ?? state.searchType;
    final effectiveMatchMode = matchMode ?? state.matchMode;
    final normalizedPrefix = titlePrefix != null
        ? titlePrefix.trim()
        : state.titlePrefix;
    final normalizedCategory = categoryFilter != null
      ? categoryFilter.trim().toLowerCase()
      : state.categoryFilter;
    final effectivePrefix =
        (normalizedPrefix == null || normalizedPrefix.isEmpty)
        ? null
        : normalizedPrefix;

    state = state.copyWith(
      isLoading: true,
      selectedYear: year,
      searchQuery: query,
      titlePrefix: effectivePrefix,
        categoryFilter: (normalizedCategory == null || normalizedCategory.isEmpty)
          ? null
          : normalizedCategory,
      offset: 0,
      sermons: [],
      searchResults: [],
      searchType: effectiveSearchType,
      matchMode: effectiveMatchMode,
      loadError: null,
      allowedIds: allowedIds,
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
      final useTitlePrefix =
          effectivePrefix != null && effectivePrefix.isNotEmpty;
      final normalizedQuery = query.trim();

      if ((searchType ?? state.searchType) == SearchType.all) {
        // Content search can be heavy; we only search if query is significant.
        if (normalizedQuery.length < 2) {
          state = state.copyWith(isLoading: false, searchResults: []);
          return;
        }

        final yearFrom = year ?? state.yearFrom;
        final yearTo = year ?? state.yearTo;
        final results = await repo.searchSermons(
          query: normalizedQuery,
          limit: 50,
          offset: 0,
          exactMatch: effectiveSearchType == SearchType.exact,
          anyWord: effectiveSearchType == SearchType.any,
          prefixOnly: effectiveSearchType == SearchType.prefix,
          accurateMatch: effectiveMatchMode == MatchMode.accurate,
          yearFrom: yearFrom,
          yearTo: yearTo,
        );
        state = state.copyWith(
          searchResults: results,
          isLoading: false,
          offset: 50,
          loadError: null,
        );
        return;
      }

      final results = await _getSermonsPageWithPrefixFallback(
        repo: repo,
        limit: 50,
        offset: 0,
        year: year,
        query: useTitlePrefix ? normalizedQuery : query,
        titlePrefix: effectivePrefix,
        categoryFilter: (normalizedCategory == null || normalizedCategory.isEmpty)
          ? null
          : normalizedCategory,
        sortBy: effectiveSortBy,
        yearFrom: year == null ? yearFrom : null,
        yearTo: year == null ? yearTo : null,
        allowedIds: allowedIds,
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

  void setSearchType(SearchType type) {
    if (state.searchType == type) return;
    state = state.copyWith(
      searchType: type,
      sermons: [],
      searchResults: [],
      offset: 0,
    );
    if (state.searchQuery.length > 2 || type == SearchType.prefix) {
      filterSermons(query: state.searchQuery);
    }
  }

  void updateMatchMode(MatchMode mode) {
    if (state.matchMode == mode) return;
    state = state.copyWith(
      matchMode: mode,
      sermons: [],
      searchResults: [],
      offset: 0,
    );
    if (state.searchQuery.length > 2) {
      filterSermons(query: state.searchQuery);
    }
  }

  /// Reset the list back to its default (unfiltered) state for
  /// the current language, used when leaving special views like COD.
  Future<void> resetToInitial() async {
    state = SermonListState(isLoading: true);
    await _loadInitial();
  }

  Future<List<SermonEntity>> _getSermonsPageWithPrefixFallback({
    required SermonRepository repo,
    required int limit,
    required int offset,
    required int? year,
    required String query,
    required String? titlePrefix,
    required String? categoryFilter,
    required String sortBy,
    required int? yearFrom,
    required int? yearTo,
    List<String>? allowedIds,
  }) async {
    final useTitlePrefix = titlePrefix != null && titlePrefix.trim().isNotEmpty;
    final normalizedPrefix = useTitlePrefix ? titlePrefix!.trim() : null;
    final results = await repo.getSermonsPage(
      limit: limit,
      offset: offset,
      year: year,
      searchQuery: query,
      titlePrefix: normalizedPrefix,
      category: categoryFilter,
      sortBy: sortBy,
      yearFrom: yearFrom,
      yearTo: yearTo,
      allowedIds: allowedIds,
    );
    if (results.isNotEmpty || !useTitlePrefix) return results;

    final lang = ref.read(selectedSermonLangProvider);
    if (lang != 'ta') return results;

    return repo.getSermonsPage(
      limit: limit,
      offset: offset,
      year: year,
      searchQuery: query,
      titleContains: normalizedPrefix,
      category: categoryFilter,
      sortBy: sortBy,
      yearFrom: yearFrom,
      yearTo: yearTo,
      allowedIds: allowedIds,
    );
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
final sermonByIdProvider = FutureProvider.family<SermonEntity?, String>((
  ref,
  id,
) async {
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
