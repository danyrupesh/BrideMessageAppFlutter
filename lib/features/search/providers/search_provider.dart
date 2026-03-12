import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/bible_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../../core/database/sermon_repository.dart';
import '../../../core/database/models/sermon_search_result.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import 'search_history_provider.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

enum SearchTab { bible, sermon, all }

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
  final String? error;
  final SearchTab activeTab;
  final SearchType searchType;
  final MatchMode matchMode;
  final BibleScope bibleScope;
  final SortOrder sortOrder;
  final String languageCode;

  SearchState({
    this.query = '',
    this.isLoading = false,
    this.bibleResults = const [],
    this.sermonResults = const [],
    this.error,
    this.activeTab = SearchTab.bible,
    this.searchType = SearchType.all,
    this.matchMode = MatchMode.exactMatch,
    this.bibleScope = BibleScope.both,
    this.sortOrder = SortOrder.bookOrder,
    this.languageCode = 'en',
  });

  SearchState copyWith({
    String? query,
    bool? isLoading,
    List<BibleSearchResult>? bibleResults,
    List<SermonSearchResult>? sermonResults,
    String? error,
    SearchTab? activeTab,
    SearchType? searchType,
    MatchMode? matchMode,
    BibleScope? bibleScope,
    SortOrder? sortOrder,
    String? languageCode,
  }) {
    return SearchState(
      query: query ?? this.query,
      isLoading: isLoading ?? this.isLoading,
      bibleResults: bibleResults ?? this.bibleResults,
      sermonResults: sermonResults ?? this.sermonResults,
      error: error,
      activeTab: activeTab ?? this.activeTab,
      searchType: searchType ?? this.searchType,
      matchMode: matchMode ?? this.matchMode,
      bibleScope: bibleScope ?? this.bibleScope,
      sortOrder: sortOrder ?? this.sortOrder,
      languageCode: languageCode ?? this.languageCode,
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

  void updateQuery(String value) {
    if (value == state.query) return;
    state = state.copyWith(query: value);
    if (value.length > 2) {
      _executeSearch(value);
    } else {
      state = state.copyWith(
          bibleResults: [], sermonResults: [], isLoading: false, error: null);
    }
  }

  Future<void> _executeSearch(String query) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final isExact = state.searchType == SearchType.exact;
      final isAny = state.searchType == SearchType.any;
      final isPrefix = state.searchType == SearchType.prefix;
      final lang = state.languageCode;

      if (state.activeTab == SearchTab.bible ||
          state.activeTab == SearchTab.all) {
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
        } else {
          if (state.query == query) state = state.copyWith(isLoading: false);
        }
      }

      if (state.activeTab == SearchTab.sermon ||
          state.activeTab == SearchTab.all) {
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
        } else {
          if (state.query == query) state = state.copyWith(isLoading: false);
        }
      }
    } catch (e) {
      if (state.query == query) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
    }
  }
}

final searchProvider = NotifierProvider<SearchNotifier, SearchState>(() {
  return SearchNotifier();
});
