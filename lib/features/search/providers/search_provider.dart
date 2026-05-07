import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/bible_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../../core/database/sermon_repository.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../../core/database/models/cod_models.dart'
    show CodAnswerSearchHit, CodSearchMatchMode;
import '../../cod/providers/cod_provider.dart';
import '../../../core/database/hymn_repository.dart';
import '../../../core/database/models/hymn_models.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import 'search_history_provider.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum SearchTab { bible, sermon, cod, songs, all }

enum SearchType { all, exact, any, prefix }

enum MatchMode { exactMatch, accurate }

enum BibleScope { both, oldTest, newTest }

enum SortOrder { bookOrder, relevance }

// ─── State ────────────────────────────────────────────────────────────────────

class SearchState {
  static const _unset = Object();

  final String query;
  final bool isLoading;
  final bool isLoadingMore;
  final List<BibleSearchResult> bibleResults;
  final List<SermonSearchResult> sermonResults;
  final List<SermonSearchResult> codResults;
  final List<Hymn> songResults;
  final int bibleTotalCount;
  final int sermonTotalCount;
  final int codTotalCount;
  final int songTotalCount;
  final String? error;
  final SearchTab activeTab;
  final SearchType searchType;
  final MatchMode matchMode;
  final BibleScope bibleScope;
  final SortOrder sortOrder;
  final String languageCode;
  final bool searchLyrics;
  final int? bibleBookIndex;
  final int? bibleChapterFrom;
  final int? bibleChapterTo;
  final int? sermonYearFrom;
  final int? sermonYearTo;

  SearchState({
    this.query = '',
    this.isLoading = false,
    this.isLoadingMore = false,
    this.bibleResults = const [],
    this.sermonResults = const [],
    this.codResults = const [],
    this.songResults = const [],
    this.bibleTotalCount = 0,
    this.sermonTotalCount = 0,
    this.codTotalCount = 0,
    this.songTotalCount = 0,
    this.error,
    this.activeTab = SearchTab.bible,
    this.searchType = SearchType.all,
    this.matchMode = MatchMode.exactMatch,
    this.bibleScope = BibleScope.both,
    this.sortOrder = SortOrder.bookOrder,
    this.languageCode = 'en',
    this.searchLyrics = false,
    this.bibleBookIndex,
    this.bibleChapterFrom,
    this.bibleChapterTo,
    this.sermonYearFrom,
    this.sermonYearTo,
  });

  SearchState copyWith({
    String? query,
    bool? isLoading,
    bool? isLoadingMore,
    List<BibleSearchResult>? bibleResults,
    List<SermonSearchResult>? sermonResults,
    List<SermonSearchResult>? codResults,
    List<Hymn>? songResults,
    int? bibleTotalCount,
    int? sermonTotalCount,
    int? codTotalCount,
    int? songTotalCount,
    String? error,
    SearchTab? activeTab,
    SearchType? searchType,
    MatchMode? matchMode,
    BibleScope? bibleScope,
    SortOrder? sortOrder,
    String? languageCode,
    bool? searchLyrics,
    Object? bibleBookIndex = _unset,
    Object? bibleChapterFrom = _unset,
    Object? bibleChapterTo = _unset,
    Object? sermonYearFrom = _unset,
    Object? sermonYearTo = _unset,
  }) {
    return SearchState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      bibleResults: bibleResults ?? this.bibleResults,
      sermonResults: sermonResults ?? this.sermonResults,
      codResults: codResults ?? this.codResults,
      songResults: songResults ?? this.songResults,
      bibleTotalCount: bibleTotalCount ?? this.bibleTotalCount,
      sermonTotalCount: sermonTotalCount ?? this.sermonTotalCount,
      codTotalCount: codTotalCount ?? this.codTotalCount,
      songTotalCount: songTotalCount ?? this.songTotalCount,
      error: error,
      activeTab: activeTab ?? this.activeTab,
      searchType: searchType ?? this.searchType,
      matchMode: matchMode ?? this.matchMode,
      bibleScope: bibleScope ?? this.bibleScope,
      sortOrder: sortOrder ?? this.sortOrder,
      languageCode: languageCode ?? this.languageCode,
      searchLyrics: searchLyrics ?? this.searchLyrics,
      bibleBookIndex: identical(bibleBookIndex, _unset)
          ? this.bibleBookIndex
          : bibleBookIndex as int?,
      bibleChapterFrom: identical(bibleChapterFrom, _unset)
          ? this.bibleChapterFrom
          : bibleChapterFrom as int?,
      bibleChapterTo: identical(bibleChapterTo, _unset)
          ? this.bibleChapterTo
          : bibleChapterTo as int?,
      sermonYearFrom: identical(sermonYearFrom, _unset)
          ? this.sermonYearFrom
          : sermonYearFrom as int?,
      sermonYearTo: identical(sermonYearTo, _unset)
          ? this.sermonYearTo
          : sermonYearTo as int?,
    );
  }
}

// ─── Resolved repository providers ───────────────────────────────────────────

/// Bible repository resolved from installed-database metadata for a given language.
final bibleRepoForLangProvider =
    FutureProvider.family<BibleRepository?, String>((ref, language) async {
      InstalledDatabase? installed;
      try {
        installed = await ref.watch(
          defaultInstalledDbProvider((DbType.bible, language)).future,
        );
      } catch (_) {
        installed = null;
      }
      // Fallback keeps Common Search working when metadata is not yet synced.
      final code = installed?.code ?? (language == 'ta' ? 'bsi' : 'kjv');
      final langCode = installed?.language ?? language;
      return BibleRepository(DatabaseManager(), langCode, code);
    });

/// Sermon repository resolved from installed-database metadata for a given language.
final sermonRepoForLangProvider =
    FutureProvider.family<SermonRepository?, String>((ref, language) async {
      InstalledDatabase? installed;
      try {
        installed = await ref.watch(
          defaultInstalledDbProvider((DbType.sermon, language)).future,
        );
      } catch (_) {
        installed = null;
      }
      final code = installed?.code ?? language;
      final langCode = installed?.language ?? language;
      return SermonRepository(DatabaseManager(), langCode, code);
    });

final bibleBooksForLangProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      language,
    ) async {
      final repo = await ref.watch(bibleRepoForLangProvider(language).future);
      if (repo == null) return const [];
      return repo.getDistinctBooks();
    });

final sermonYearsForLangProvider = FutureProvider.family<List<int>, String>((
  ref,
  language,
) async {
  final repo = await ref.watch(sermonRepoForLangProvider(language).future);
  if (repo == null) return const [];
  return repo.getAvailableYears();
});

// ─── Search notifier ──────────────────────────────────────────────────────────

class SearchNotifier extends Notifier<SearchState> {
  static const int _pageSize = 50;
  static final RegExp _queryTokenSanitizer = RegExp(
    r'[^\p{L}\p{M}\p{N}_]',
    unicode: true,
  );

  @override
  SearchState build() => SearchState();

  void updateTab(SearchTab tab) {
    if (state.activeTab == tab) return;
    state = state.copyWith(activeTab: tab);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateSearchType(SearchType type) {
    if (state.searchType == type) return;
    state = state.copyWith(searchType: type);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateMatchMode(MatchMode mode) {
    if (state.matchMode == mode) return;
    state = state.copyWith(matchMode: mode);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateBibleScope(BibleScope scope) {
    if (state.bibleScope == scope) return;
    state = state.copyWith(bibleScope: scope);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateSortOrder(SortOrder order) {
    if (state.sortOrder == order) return;
    state = state.copyWith(sortOrder: order);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateBibleBookIndex(int? bookIndex) {
    if (state.bibleBookIndex == bookIndex) return;
    state = state.copyWith(
      bibleBookIndex: bookIndex,
      bibleChapterFrom: null,
      bibleChapterTo: null,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateBibleChapterFrom(int? chapterFrom) {
    final normalized = _normalizeRange(chapterFrom, state.bibleChapterTo);
    if (state.bibleChapterFrom == normalized.$1 &&
        state.bibleChapterTo == normalized.$2) {
      return;
    }
    state = state.copyWith(
      bibleChapterFrom: normalized.$1,
      bibleChapterTo: normalized.$2,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateBibleChapterTo(int? chapterTo) {
    final normalized = _normalizeRange(state.bibleChapterFrom, chapterTo);
    if (state.bibleChapterFrom == normalized.$1 &&
        state.bibleChapterTo == normalized.$2) {
      return;
    }
    state = state.copyWith(
      bibleChapterFrom: normalized.$1,
      bibleChapterTo: normalized.$2,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void clearBibleChapterRange() {
    if (state.bibleBookIndex == null &&
        state.bibleChapterFrom == null &&
        state.bibleChapterTo == null) {
      return;
    }
    state = state.copyWith(
      bibleBookIndex: null,
      bibleChapterFrom: null,
      bibleChapterTo: null,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateSermonYearFrom(int? yearFrom) {
    final normalized = _normalizeRange(yearFrom, state.sermonYearTo);
    if (state.sermonYearFrom == normalized.$1 &&
        state.sermonYearTo == normalized.$2) {
      return;
    }
    state = state.copyWith(
      sermonYearFrom: normalized.$1,
      sermonYearTo: normalized.$2,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void updateSermonYearTo(int? yearTo) {
    final normalized = _normalizeRange(state.sermonYearFrom, yearTo);
    if (state.sermonYearFrom == normalized.$1 &&
        state.sermonYearTo == normalized.$2) {
      return;
    }
    state = state.copyWith(
      sermonYearFrom: normalized.$1,
      sermonYearTo: normalized.$2,
    );
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void clearSermonYearRange() {
    if (state.sermonYearFrom == null && state.sermonYearTo == null) return;
    state = state.copyWith(sermonYearFrom: null, sermonYearTo: null);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void toggleLanguage() {
    final next = state.languageCode == 'en' ? 'ta' : 'en';
    state = state.copyWith(languageCode: next);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void toggleSearchLyrics() {
    state = state.copyWith(searchLyrics: !state.searchLyrics);
    if (state.query.length > 2) _executeSearch(state.query);
  }

  void reset({SearchTab? activeTab}) {
    state = SearchState(
      activeTab: activeTab ?? SearchTab.bible,
      languageCode: state.languageCode,
    );
  }

  void loadMoreCurrentTab() {
    if (state.query.length <= 2 || state.isLoading || state.isLoadingMore) {
      return;
    }
    switch (state.activeTab) {
      case SearchTab.bible:
        if (state.bibleResults.length >= state.bibleTotalCount) return;
        break;
      case SearchTab.sermon:
        if (state.sermonResults.length >= state.sermonTotalCount) return;
        break;
      case SearchTab.cod:
        if (state.codResults.length >= state.codTotalCount) return;
        break;
      case SearchTab.songs:
        if (state.songResults.length >= state.songTotalCount) return;
        break;
      case SearchTab.all:
        return;
    }
    _executeSearch(state.query, append: true);
  }

  void updateQuery(String value) {
    if (value == state.query) return;
    state = state.copyWith(query: value);
    if (value.length > 2) {
      _executeSearch(value);
    } else {
      state = state.copyWith(
        bibleResults: [],
        sermonResults: [],
        codResults: [],
        songResults: [],
        bibleTotalCount: 0,
        sermonTotalCount: 0,
        codTotalCount: 0,
        songTotalCount: 0,
        isLoading: false,
        isLoadingMore: false,
        error: null,
      );
    }
  }

  Future<void> _executeSearch(String query, {bool append = false}) async {
    state = state.copyWith(
      isLoading: append ? state.isLoading : true,
      isLoadingMore: append,
      error: null,
    );
    try {
      final isExact = state.searchType == SearchType.exact;
      final isAny = state.searchType == SearchType.any;
      final isPrefix = state.searchType == SearchType.prefix;
      final lang = state.languageCode;

      if (state.activeTab == SearchTab.all) {
        final bibleRepo = await ref.read(bibleRepoForLangProvider(lang).future);
        if (bibleRepo != null) {
          var bibleMatches = await bibleRepo.searchVerses(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            scope: state.bibleScope.name,
            sortOrder: state.sortOrder.name,
            bookIndex: state.bibleBookIndex,
            chapterFrom: state.bibleChapterFrom,
            chapterTo: state.bibleChapterTo,
          );
          if (state.matchMode == MatchMode.accurate) {
            bibleMatches = _applyAccurateBibleFilter(
              query: query,
              matches: bibleMatches,
            );
          }
          if (state.query == query) {
            state = state.copyWith(bibleResults: bibleMatches);
          }
        }

        final sermonRepo = await ref.read(
          sermonRepoForLangProvider(lang).future,
        );
        if (sermonRepo != null) {
          var sermonMatches = await sermonRepo.searchSermons(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            sortOrder: state.sortOrder.name,
            yearFrom: state.sermonYearFrom,
            yearTo: state.sermonYearTo,
          );
          if (state.matchMode == MatchMode.accurate) {
            sermonMatches = _applyAccurateSermonFilter(
              query: query,
              matches: sermonMatches,
            );
          }
          if (state.query == query) {
            state = state.copyWith(sermonResults: sermonMatches);
          }
        }

        if (state.query == query) {
          state = state.copyWith(isLoading: false);
          ref.read(searchHistoryProvider.notifier).addQuery(query);
        }
        return;
      }

      if (state.activeTab == SearchTab.bible) {
        final repo = await ref.read(bibleRepoForLangProvider(lang).future);
        if (repo != null) {
          final offset = append ? state.bibleResults.length : 0;
          final payload = await Future.wait<dynamic>([
            repo.searchVerses(
              query: query,
              limit: _pageSize,
              offset: offset,
              exactMatch: isExact,
              anyWord: isAny,
              prefixOnly: isPrefix,
              accurateMatch: state.matchMode == MatchMode.accurate,
              scope: state.bibleScope.name,
              sortOrder: state.sortOrder.name,
              bookIndex: state.bibleBookIndex,
              chapterFrom: state.bibleChapterFrom,
              chapterTo: state.bibleChapterTo,
            ),
            if (!append)
              repo.countSearchResults(
                query,
                scope: state.bibleScope.name,
                bookIndex: state.bibleBookIndex,
                chapterFrom: state.bibleChapterFrom,
                chapterTo: state.bibleChapterTo,
              ),
          ]);
          var matches = payload.first as List<BibleSearchResult>;
          if (state.matchMode == MatchMode.accurate) {
            matches = _applyAccurateBibleFilter(query: query, matches: matches);
          }
          final total = append
              ? (state.matchMode == MatchMode.accurate
                    ? state.bibleTotalCount + matches.length
                    : state.bibleTotalCount)
              : ((payload.length > 1 ? payload[1] : 0) as int);
          final effectiveTotal = state.matchMode == MatchMode.accurate
              ? (append ? total : matches.length)
              : total;
          if (state.query == query) {
            state = state.copyWith(
              isLoading: false,
              isLoadingMore: false,
              bibleResults: append
                  ? <BibleSearchResult>[...state.bibleResults, ...matches]
                  : matches,
              bibleTotalCount: effectiveTotal,
            );
            if (!append) {
              ref.read(searchHistoryProvider.notifier).addQuery(query);
            }
          }
          return;
        }
        if (state.query == query) {
          state = state.copyWith(isLoading: false, isLoadingMore: false);
        }
        return;
      }

      if (state.activeTab == SearchTab.sermon) {
        final repo = await ref.read(sermonRepoForLangProvider(lang).future);
        if (repo != null) {
          final offset = append ? state.sermonResults.length : 0;
          final payload = await Future.wait<dynamic>([
            repo.searchSermons(
              query: query,
              limit: _pageSize,
              offset: offset,
              exactMatch: isExact,
              anyWord: isAny,
              prefixOnly: isPrefix,
              accurateMatch: state.matchMode == MatchMode.accurate,
              sortOrder: state.sortOrder.name,
              yearFrom: state.sermonYearFrom,
              yearTo: state.sermonYearTo,
            ),
            if (!append)
              repo.countSearchResults(
                query: query,
                exactMatch: isExact,
                anyWord: isAny,
                prefixOnly: isPrefix,
                yearFrom: state.sermonYearFrom,
                yearTo: state.sermonYearTo,
              ),
          ]);
          var matches = payload.first as List<SermonSearchResult>;
          if (state.matchMode == MatchMode.accurate) {
            matches = _applyAccurateSermonFilter(
              query: query,
              matches: matches,
            );
          }
          final total = append
              ? (state.matchMode == MatchMode.accurate
                    ? state.sermonTotalCount + matches.length
                    : state.sermonTotalCount)
              : ((payload.length > 1 ? payload[1] : 0) as int);
          final effectiveTotal = state.matchMode == MatchMode.accurate
              ? (append ? total : matches.length)
              : total;
          if (state.query == query) {
            state = state.copyWith(
              isLoading: false,
              isLoadingMore: false,
              sermonResults: append
                  ? <SermonSearchResult>[...state.sermonResults, ...matches]
                  : matches,
              sermonTotalCount: effectiveTotal,
            );
            if (!append) {
              ref.read(searchHistoryProvider.notifier).addQuery(query);
            }
          }
          return;
        }
        if (state.query == query) {
          state = state.copyWith(isLoading: false, isLoadingMore: false);
        }
        return;
      }

      if (state.activeTab == SearchTab.cod) {
        final repo = ref.read(codRepositoryProvider(lang));
        final offset = append ? state.codResults.length : 0;
        final countLimit = append ? _pageSize + offset : _pageSize;
        final payload = await Future.wait<dynamic>([
          repo.searchAnswerParagraphHits(
            query: query,
            limit: countLimit,
            matchMode: _codSearchMatchMode(state.searchType),
          ),
          if (!append)
            repo.countAnswerParagraphHits(
              query: query,
              matchMode: _codSearchMatchMode(state.searchType),
            ),
        ]);
        final hits = (payload.first as List<CodAnswerSearchHit>)
            .skip(offset)
            .take(_pageSize)
            .toList();
        final mapped = hits
            .map((h) => _codAnswerHitToSermonResult(h, lang))
            .toList();
        final total = append
            ? state.codTotalCount
            : ((payload.length > 1 ? payload[1] : 0) as int);
        if (state.query == query) {
          state = state.copyWith(
            isLoading: false,
            isLoadingMore: false,
            codResults: append
                ? <SermonSearchResult>[...state.codResults, ...mapped]
                : mapped,
            codTotalCount: total,
          );
          if (!append) {
            ref.read(searchHistoryProvider.notifier).addQuery(query);
          }
        }
        return;
      }

      if (state.activeTab == SearchTab.songs) {
        final repo = ref.read(hymnRepositoryProvider);
        final offset = append ? state.songResults.length : 0;
        final payload = await Future.wait<dynamic>([
          repo.searchSongsAdvanced(
            query,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            searchLyrics: state.searchLyrics,
            limit: _pageSize,
            offset: offset,
          ),
          if (!append)
            repo.countSongsAdvanced(
              query,
              exactMatch: isExact,
              anyWord: isAny,
              prefixOnly: isPrefix,
              searchLyrics: state.searchLyrics,
            ),
        ]);
        final matches = payload.first as List<Hymn>;
        final total = append
            ? state.songTotalCount
            : ((payload.length > 1 ? payload[1] : 0) as int);
        if (state.query == query) {
          state = state.copyWith(
            isLoading: false,
            isLoadingMore: false,
            songResults: append
                ? <Hymn>[...state.songResults, ...matches]
                : matches,
            songTotalCount: total,
          );
          if (!append) {
            ref.read(searchHistoryProvider.notifier).addQuery(query);
          }
        }
        return;
      }
    } catch (e) {
      if (state.query == query) {
        String message = e.toString();
        if (e is FileSystemException) {
          final pathOrError = '${e.path ?? ''} ${e.toString()}'.toLowerCase();
          if (pathOrError.contains('hymn.db')) {
            message =
                'Songs database is not installed. Please import the songs database from the import screen and try again.';
          } else if (pathOrError.contains('cod_english.db') ||
              pathOrError.contains('cod_tamil.db')) {
            message =
                'COD database is not installed. Please import COD English / COD Tamil database from the import screen.';
          } else if (pathOrError.contains('sermons_') &&
              pathOrError.contains('.db')) {
            message =
                'Sermon database is not installed. Please import Tamil/English sermons database from the import screen.';
          } else if (pathOrError.contains('bible_') &&
              pathOrError.contains('.db')) {
            message =
                'Bible database is not installed. Please import Tamil/English Bible database from the import screen.';
          }
        }
        state = state.copyWith(
          isLoading: false,
          isLoadingMore: false,
          error: message,
        );
      }
    }
  }

  CodSearchMatchMode _codSearchMatchMode(SearchType t) {
    switch (t) {
      case SearchType.exact:
        return CodSearchMatchMode.phrase;
      case SearchType.any:
        return CodSearchMatchMode.anyWord;
      case SearchType.all:
      case SearchType.prefix:
        return CodSearchMatchMode.allWords;
    }
  }

  List<BibleSearchResult> _applyAccurateBibleFilter({
    required String query,
    required List<BibleSearchResult> matches,
  }) {
    final matcher = _buildAccurateMatcher(query);
    return matches.where((m) => matcher.hasMatch(m.text)).toList();
  }

  List<SermonSearchResult> _applyAccurateSermonFilter({
    required String query,
    required List<SermonSearchResult> matches,
  }) {
    final matcher = _buildAccurateMatcher(query);
    return matches
        .where((m) => matcher.hasMatch(_stripHtml(m.snippet)))
        .toList();
  }

  RegExp _buildAccurateMatcher(String rawQuery) {
    final cleaned = rawQuery.trim();
    final escaped = RegExp.escape(cleaned);
    final phrasePattern =
        "(?<![\\p{L}\\p{M}\\p{N}'’])$escaped(?![\\p{L}\\p{M}\\p{N}'’])";
    if (state.searchType == SearchType.exact) {
      return RegExp(phrasePattern, caseSensitive: false, unicode: true);
    }

    final tokens = cleaned
        .split(RegExp(r'\s+'))
        .map((token) => token.replaceAll(_queryTokenSanitizer, ''))
        .where((token) => token.isNotEmpty)
        .toList();
    if (tokens.isEmpty) {
      return RegExp(r'(?!)');
    }
    final tokenPatterns = tokens
        .map(
          (token) =>
              "(?<![\\p{L}\\p{M}\\p{N}'’])${RegExp.escape(token)}(?![\\p{L}\\p{M}\\p{N}'’])",
        )
        .toList();
    final pattern = state.searchType == SearchType.any
        ? tokenPatterns.join('|')
        : '${tokenPatterns.map((p) => '(?=.*$p)').join()}.*';
    return RegExp(pattern, caseSensitive: false, unicode: true, dotAll: true);
  }

  String _stripHtml(String value) {
    return value.replaceAll(RegExp(r'<[^>]*>'), ' ');
  }

  (int?, int?) _normalizeRange(int? from, int? to) {
    if (from != null && to != null && from > to) {
      return (to, from);
    }
    return (from, to);
  }

  SermonSearchResult _codAnswerHitToSermonResult(
    CodAnswerSearchHit h,
    String lang,
  ) {
    final qn = h.questionNumber;
    return SermonSearchResult(
      sermonId: h.questionId,
      title: h.questionTitle,
      language: lang,
      date: null,
      year: null,
      location: null,
      paragraphNumber: h.orderIndex,
      paragraphLabel: h.paraLabel,
      snippet: h.snippetHtml,
      rank: null,
      codAnswerParagraphId: h.answerParagraphId,
      displayLeadingId: qn != null ? 'q$qn' : null,
    );
  }
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(() {
  return SearchNotifier();
});
