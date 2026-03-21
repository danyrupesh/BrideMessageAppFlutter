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
  final String query;
  final bool isLoading;
  final List<BibleSearchResult> bibleResults;
  final List<SermonSearchResult> sermonResults;
  final List<SermonSearchResult> codResults;
  final List<Hymn> songResults;
  final String? error;
  final SearchTab activeTab;
  final SearchType searchType;
  final MatchMode matchMode;
  final BibleScope bibleScope;
  final SortOrder sortOrder;
  final String languageCode;
  final bool searchLyrics;

  SearchState({
    this.query = '',
    this.isLoading = false,
    this.bibleResults = const [],
    this.sermonResults = const [],
    this.codResults = const [],
    this.songResults = const [],
    this.error,
    this.activeTab = SearchTab.bible,
    this.searchType = SearchType.all,
    this.matchMode = MatchMode.exactMatch,
    this.bibleScope = BibleScope.both,
    this.sortOrder = SortOrder.bookOrder,
    this.languageCode = 'en',
    this.searchLyrics = false,
  });

  SearchState copyWith({
    String? query,
    bool? isLoading,
    List<BibleSearchResult>? bibleResults,
    List<SermonSearchResult>? sermonResults,
    List<SermonSearchResult>? codResults,
    List<Hymn>? songResults,
    String? error,
    SearchTab? activeTab,
    SearchType? searchType,
    MatchMode? matchMode,
    BibleScope? bibleScope,
    SortOrder? sortOrder,
    String? languageCode,
    bool? searchLyrics,
  }) {
    return SearchState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      bibleResults: bibleResults ?? this.bibleResults,
      sermonResults: sermonResults ?? this.sermonResults,
      codResults: codResults ?? this.codResults,
      songResults: songResults ?? this.songResults,
      error: error,
      activeTab: activeTab ?? this.activeTab,
      searchType: searchType ?? this.searchType,
      matchMode: matchMode ?? this.matchMode,
      bibleScope: bibleScope ?? this.bibleScope,
      sortOrder: sortOrder ?? this.sortOrder,
      languageCode: languageCode ?? this.languageCode,
      searchLyrics: searchLyrics ?? this.searchLyrics,
    );
  }
}

// ─── Resolved repository providers ───────────────────────────────────────────

/// Bible repository resolved from installed-database metadata for a given language.
final bibleRepoForLangProvider =
    FutureProvider.family<BibleRepository?, String>((ref, language) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.bible, language)).future,
  );
  if (installed == null) return null;
  return BibleRepository(DatabaseManager(), installed.language, installed.code);
});

/// Sermon repository resolved from installed-database metadata for a given language.
final sermonRepoForLangProvider =
    FutureProvider.family<SermonRepository?, String>((ref, language) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.sermon, language)).future,
  );
  if (installed == null) return null;
  return SermonRepository(
      DatabaseManager(), installed.language, installed.code);
});

// ─── Search notifier ──────────────────────────────────────────────────────────

class SearchNotifier extends Notifier<SearchState> {
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
        isLoading: false,
        error: null,
      );
    }
  }

  Future<void> _executeSearch(String query) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final isExact = state.searchType == SearchType.exact;
      final isAny = state.searchType == SearchType.any;
      final isPrefix = state.searchType == SearchType.prefix;
      final lang = state.languageCode;

      if (state.activeTab == SearchTab.all) {
        final bibleRepo = await ref.read(bibleRepoForLangProvider(lang).future);
        if (bibleRepo != null) {
          final bibleMatches = await bibleRepo.searchVerses(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            scope: state.bibleScope.name,
            sortOrder: state.sortOrder.name,
          );
          if (state.query == query) {
            state = state.copyWith(bibleResults: bibleMatches);
          }
        }

        final sermonRepo =
            await ref.read(sermonRepoForLangProvider(lang).future);
        if (sermonRepo != null) {
          final sermonMatches = await sermonRepo.searchSermons(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            sortOrder: state.sortOrder.name,
          );
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
          final matches = await repo.searchVerses(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            scope: state.bibleScope.name,
            sortOrder: state.sortOrder.name,
          );
          if (state.query == query) {
            state = state.copyWith(isLoading: false, bibleResults: matches);
            ref.read(searchHistoryProvider.notifier).addQuery(query);
          }
          return;
        }
        if (state.query == query) state = state.copyWith(isLoading: false);
        return;
      }

      if (state.activeTab == SearchTab.sermon) {
        final repo = await ref.read(sermonRepoForLangProvider(lang).future);
        if (repo != null) {
          final matches = await repo.searchSermons(
            query: query,
            limit: 50,
            offset: 0,
            exactMatch: isExact,
            anyWord: isAny,
            prefixOnly: isPrefix,
            accurateMatch: state.matchMode == MatchMode.accurate,
            sortOrder: state.sortOrder.name,
          );
          if (state.query == query) {
            state = state.copyWith(isLoading: false, sermonResults: matches);
            ref.read(searchHistoryProvider.notifier).addQuery(query);
          }
          return;
        }
        if (state.query == query) state = state.copyWith(isLoading: false);
        return;
      }

      if (state.activeTab == SearchTab.cod) {
        final repo = ref.read(codRepositoryProvider(lang));
        final hits = await repo.searchAnswerParagraphHits(
          query: query,
          limit: 50,
          matchMode: _codSearchMatchMode(state.searchType),
        );
        final mapped =
            hits.map((h) => _codAnswerHitToSermonResult(h, lang)).toList();
        if (state.query == query) {
          state = state.copyWith(isLoading: false, codResults: mapped);
          ref.read(searchHistoryProvider.notifier).addQuery(query);
        }
        return;
      }

      if (state.activeTab == SearchTab.songs) {
        final repo = ref.read(hymnRepositoryProvider);
        final matches = await repo.searchSongsAdvanced(
          query,
          exactMatch: isExact,
          anyWord: isAny,
          prefixOnly: isPrefix,
          searchLyrics: state.searchLyrics,
          limit: 50,
          offset: 0,
        );
        if (state.query == query) {
          state = state.copyWith(isLoading: false, songResults: matches);
          ref.read(searchHistoryProvider.notifier).addQuery(query);
        }
        return;
      }
    } catch (e) {
      if (state.query == query) {
        String message = e.toString();
        if (e is FileSystemException &&
            e.path != null &&
            e.path!.endsWith('hymn.db')) {
          message =
              'Songs database is not installed. Please import the Only Believe songs database from the onboarding/import screen and try again.';
        }
        state = state.copyWith(isLoading: false, error: message);
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
