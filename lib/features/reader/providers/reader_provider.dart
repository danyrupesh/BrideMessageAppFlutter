import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/reader_tab.dart';

import '../../../core/database/bible_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ReaderState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;

  ReaderState({required this.tabs, required this.activeTabIndex});

  ReaderTab? get activeTab => tabs.isEmpty ? null : tabs[activeTabIndex];

  ReaderState copyWith({List<ReaderTab>? tabs, int? activeTabIndex}) {
    return ReaderState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }
}

// ─── Reader notifier ─────────────────────────────────────────────────────────

class ReaderNotifier extends Notifier<ReaderState> {
  @override
  ReaderState build() => ReaderState(tabs: [], activeTabIndex: 0);

  void openTab(ReaderTab tab) {
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
  }

  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    final newTabs = List<ReaderTab>.from(state.tabs)..removeAt(index);
    int newIndex = state.activeTabIndex;
    if (newTabs.isEmpty) {
      newIndex = 0;
    } else if (index <= state.activeTabIndex && state.activeTabIndex > 0) {
      newIndex--;
    } else if (newIndex >= newTabs.length) {
      newIndex = newTabs.length - 1;
    }
    state = state.copyWith(tabs: newTabs, activeTabIndex: newIndex);
  }

  void switchTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
    }
  }

  void replaceCurrentTab(ReaderTab tab) {
    if (state.tabs.isEmpty) {
      openTab(tab);
      return;
    }
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[state.activeTabIndex] = tab;
    state = state.copyWith(tabs: newTabs);
  }
}

final readerProvider = NotifierProvider<ReaderNotifier, ReaderState>(() {
  return ReaderNotifier();
});

// ─── Resolved Bible repository ────────────────────────────────────────────────

/// Resolves the default English Bible from metadata, with 'kjv' as hard fallback.
final bibleRepositoryProvider = FutureProvider<BibleRepository>((ref) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.bible, 'en')).future,
  );
  final code = installed?.code ?? 'kjv';
  final language = installed?.language ?? 'en';
  return BibleRepository(DatabaseManager(), language, code);
});

/// All distinct Bible books with chapter counts, ordered canonically.
final bibleBookListProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final repo = await ref.watch(bibleRepositoryProvider.future);
  return repo.getDistinctBooks();
});

/// Verse count for a given book + chapter (used by the verse-selection page).
final verseCountProvider =
    FutureProvider.family<int, (String, int)>((ref, args) async {
  final repo = await ref.watch(bibleRepositoryProvider.future);
  return repo.getVerseCount(args.$1, args.$2);
});

/// Load verses for the active reader tab using the resolved Bible repo.
final chapterVersesProvider =
    FutureProvider.family<List<BibleSearchResult>, ReaderTab>(
        (ref, tab) async {
  if (tab.type != ReaderContentType.bible ||
      tab.book == null ||
      tab.chapter == null) {
    return [];
  }
  final repoAsync = ref.watch(bibleRepositoryProvider);
  return repoAsync.when(
    data: (repo) => repo.getVersesByChapter(tab.book!, tab.chapter!),
    loading: () => Future.value([]),
    error: (e, st) => Future.value([]),
  );
});
