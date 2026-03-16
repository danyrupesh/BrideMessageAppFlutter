import 'dart:convert';
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_tab.dart';
import '../../reading_state/models/reading_flow_models.dart';
import '../../reading_state/providers/reading_state_provider.dart';

import '../../../core/database/bible_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ReaderState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;
  final bool restoreTabs;
  final bool isInitialized;

  ReaderState({
    required this.tabs,
    required this.activeTabIndex,
    required this.restoreTabs,
    required this.isInitialized,
  });

  ReaderTab? get activeTab {
    if (tabs.isEmpty) return null;
    if (activeTabIndex < 0 || activeTabIndex >= tabs.length) return null;
    return tabs[activeTabIndex];
  }

  ReaderState copyWith({
    List<ReaderTab>? tabs,
    int? activeTabIndex,
    bool? restoreTabs,
    bool? isInitialized,
  }) {
    return ReaderState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      restoreTabs: restoreTabs ?? this.restoreTabs,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// ─── Reader notifier ─────────────────────────────────────────────────────────

class ReaderNotifier extends Notifier<ReaderState> {
  static const _restoreTabsKey = 'reader_restore_tabs';
  static const _tabsKey = 'reader_saved_tabs';
  static const _activeTabIndexKey = 'reader_active_tab_index';
  ReaderTab? _pendingOpenTab;
  String? _pendingOpenLang;

  @override
  ReaderState build() {
    ref.listen(selectedBibleLangProvider, (previous, next) {
      if (previous != next) {
        state = state.copyWith(tabs: [], isInitialized: false);
        _hydrate();
      }
    });
    
    _hydrate();
    return ReaderState(
      tabs: [],
      activeTabIndex: 0,
      restoreTabs: true,
      isInitialized: false,
    );
  }

  String get _sessionKey {
    final lang = ref.read(selectedBibleLangProvider);
    return 'bible_$lang';
  }

  Future<void> _hydrate() async {
    final prefs = await SharedPreferences.getInstance();
    final repo = ref.read(readingStateRepositoryProvider);
    const restoreTabs = true;
    final legacySavedTabsRaw = prefs.getString(_tabsKey);
    final legacySavedIndex = prefs.getInt(_activeTabIndexKey) ?? 0;

    var restoredTabs = <ReaderTab>[];
    var restoredIndex = 0;

    final activeSession = restoreTabs
        ? await repo.loadActiveSession(
            sessionKey: _sessionKey,
            fallbackFlowType: FlowType.bible,
          )
        : null;
    if (activeSession != null) {
      restoredTabs = activeSession.toReaderTabs();
      restoredIndex = activeSession.activeTabIndex;
    } else if (restoreTabs &&
        legacySavedTabsRaw != null &&
        legacySavedTabsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(legacySavedTabsRaw);
        if (decoded is List) {
          restoredTabs = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(readerTabFromJson)
              .whereType<ReaderTab>()
              .toList();
          restoredIndex = legacySavedIndex;
        }
      } catch (_) {
        restoredTabs = [];
      }

      // One-time migration from legacy SharedPreferences reader tabs.
      if (restoredTabs.isNotEmpty) {
        final migratedPayload = ReadingFlowPayloadV1.fromReaderTabs(
          flowType: FlowType.bible,
          tabs: restoredTabs,
          activeTabIndex: restoredIndex,
        );
        await repo.saveActiveSession(
          sessionKey: _sessionKey,
          payload: migratedPayload,
        );
      }
      await prefs.remove(_tabsKey);
      await prefs.remove(_activeTabIndexKey);
    }

    if (restoredTabs.isEmpty) {
      final lang = ref.read(selectedBibleLangProvider);
      final isTamil = lang == 'ta';
      restoredTabs = [
        ReaderTab(
          type: ReaderContentType.bible,
          title: isTamil ? 'ஆதியாகமம் 1' : 'Genesis 1',
          book: isTamil ? 'ஆதியாகமம்' : 'Genesis',
          chapter: 1,
        )
      ];
      restoredIndex = 0;
    }

    final safeIndex = restoredTabs.isEmpty
        ? 0
        : restoredIndex.clamp(0, restoredTabs.length - 1);

    state = state.copyWith(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      restoreTabs: restoreTabs,
      isInitialized: true,
    );
    _applyPendingOpenTab();
    await prefs.setBool(_restoreTabsKey, true);
  }

  void _applyPendingOpenTab() {
    final pending = _pendingOpenTab;
    if (pending == null) return;
    final pendingLang = _pendingOpenLang;
    final currentLang = ref.read(selectedBibleLangProvider);
    if (pendingLang != null && pendingLang != currentLang) return;
    _pendingOpenTab = null;
    _pendingOpenLang = null;
    openTab(pending);
  }

  ReadingFlowPayloadV1 _currentPayload() {
    return ReadingFlowPayloadV1.fromReaderTabs(
      flowType: FlowType.bible,
      tabs: state.tabs,
      activeTabIndex: state.activeTabIndex,
    );
  }

  String _recentBibleEntryKey(ReaderTab tab) {
    if (tab.book != null && tab.chapter != null) {
      return 'bible:${tab.book}:${tab.chapter}:${tab.verse ?? 0}';
    }
    return 'bible:tab:${tab.id}';
  }

  Future<void> _persistTabs() async {
    final repo = ref.read(readingStateRepositoryProvider);
    final prefs = await SharedPreferences.getInstance();
    if (!state.restoreTabs) {
      await repo.deleteActiveSession(_sessionKey);
    } else if (state.tabs.isNotEmpty) {
      await repo.saveActiveSession(
        sessionKey: _sessionKey,
        payload: _currentPayload(),
      );
    } else {
      await repo.deleteActiveSession(_sessionKey);
    }

    // Keep restore preference in SharedPreferences.
    await prefs.setBool(_restoreTabsKey, state.restoreTabs);

    // Recent reads should remain durable regardless of "Restore Tabs" toggle.
    final activeTab = state.activeTab;
    if (activeTab != null) {
      final title = (activeTab.book != null && activeTab.chapter != null)
          ? '${activeTab.book} ${activeTab.chapter}'
          : activeTab.title;
      await repo.upsertRecentRead(
        entryKey: _recentBibleEntryKey(activeTab),
        flowType: FlowType.bible,
        title: title,
        subtitle: 'Bible',
        snapshot: _currentPayload(),
      );
    }
    ref.invalidate(recentReadsProvider);
  }

  void openTab(ReaderTab tab) {
    final newTabs = [...state.tabs, tab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
    unawaited(_persistTabs());
  }

  void openTabForLanguage(String lang, ReaderTab tab) {
    final withLang = tab.copyWith(bibleLang: lang);
    if (!state.isInitialized) {
      _pendingOpenTab = withLang;
      _pendingOpenLang = lang;
      return;
    }
    openTab(withLang);
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
    unawaited(_persistTabs());
  }

  void switchTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
      unawaited(_persistTabs());
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
    unawaited(_persistTabs());
  }

  void restoreSession(ReadingFlowPayloadV1 payload) {
    if (payload.flowType != FlowType.bible) return;
    final restoredTabs = payload.toReaderTabs();
    final safeIndex = restoredTabs.isEmpty
        ? 0
        : payload.activeTabIndex.clamp(0, restoredTabs.length - 1);
    state = state.copyWith(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      isInitialized: true,
    );
    unawaited(_persistTabs());
  }

  Future<void> setRestoreTabs(bool enabled) async {
    state = state.copyWith(restoreTabs: enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_restoreTabsKey, enabled);
    await _persistTabs();
  }
}

final readerProvider = NotifierProvider<ReaderNotifier, ReaderState>(() {
  return ReaderNotifier();
});

// ─── Resolved Bible repository ────────────────────────────────────────────────

/// Global state: which Bible language the user is currently reading.
/// 'en' = English (default), 'ta' = Tamil.
class _BibleLangNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  void setLang(String lang) => state = lang;
}

final selectedBibleLangProvider =
    NotifierProvider<_BibleLangNotifier, String>(_BibleLangNotifier.new);

/// Resolves the default Bible from metadata based on the selected language.
final bibleRepositoryProvider = FutureProvider<BibleRepository>((ref) async {
  final lang = ref.watch(selectedBibleLangProvider);
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.bible, lang)).future,
  );
  // Fallback codes per language
  final code = installed?.code ?? (lang == 'ta' ? 'bsi' : 'kjv');
  final language = installed?.language ?? lang;
  return BibleRepository(DatabaseManager(), language, code);
});

/// Resolves a Bible repository by language ('en' or 'ta').
/// Used by the dashboard to open English or Tamil Bible directly.
final bibleRepositoryByLangProvider =
    FutureProvider.family<BibleRepository, String>((ref, lang) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.bible, lang)).future,
  );
  // Fallback codes per language
  final code = installed?.code ?? (lang == 'ta' ? 'bsi' : 'kjv');
  final language = installed?.language ?? lang;
  return BibleRepository(DatabaseManager(), language, code);
});

/// All distinct Bible books with chapter counts, ordered canonically.
final bibleBookListProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  final repo = await ref.watch(bibleRepositoryProvider.future);
  return repo.getDistinctBooks();
});

/// All distinct Bible books by language (for mixed-language tabs).
final bibleBookListByLangProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, lang) async {
  final repo = await ref.watch(bibleRepositoryByLangProvider(lang).future);
  return repo.getDistinctBooks();
});

/// Verse count for a given book + chapter (used by the verse-selection page).
final verseCountProvider = FutureProvider.family<int, (String, int)>((
  ref,
  args,
) async {
  final repo = await ref.watch(bibleRepositoryProvider.future);
  return repo.getVerseCount(args.$1, args.$2);
});

/// Verse count by language (for mixed-language tabs).
final verseCountByLangProvider =
    FutureProvider.family<int, (String, String, int)>((ref, args) async {
  final repo = await ref.watch(bibleRepositoryByLangProvider(args.$1).future);
  return repo.getVerseCount(args.$2, args.$3);
});

/// Load verses for the active reader tab using the resolved Bible repo.
final chapterVersesProvider =
    FutureProvider.family<List<BibleSearchResult>, ReaderTab>((ref, tab) async {
      if (tab.type != ReaderContentType.bible ||
          tab.book == null ||
          tab.chapter == null) {
        return [];
      }
      final lang =
          (tab.bibleLang ?? ref.read(selectedBibleLangProvider)) ?? 'en';
      final repoAsync = ref.watch(bibleRepositoryByLangProvider(lang));
      return repoAsync.when(
        data: (repo) => repo.getVersesByChapter(tab.book!, tab.chapter!),
        loading: () => Future.value([]),
        error: (e, st) => Future.value([]),
      );
    });
