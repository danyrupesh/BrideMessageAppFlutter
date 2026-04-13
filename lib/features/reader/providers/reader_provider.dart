import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/reader_tab.dart';
import '../../reading_state/models/reading_flow_models.dart';
import '../../reading_state/providers/reading_state_provider.dart';
import '../../sermons/providers/sermon_provider.dart';

import '../../../core/database/bible_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/bible_search_result.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';

// ─── State ────────────────────────────────────────────────────────────────────

class ReaderBmMessageTab {
  final String id;
  final String title;

  const ReaderBmMessageTab({required this.id, required this.title});

  Map<String, dynamic> toJson() => {'id': id, 'title': title};

  static ReaderBmMessageTab? fromJson(Map<String, dynamic> map) {
    final id = map['id'] as String?;
    final title = map['title'] as String?;
    if (id == null || id.trim().isEmpty) return null;
    return ReaderBmMessageTab(
      id: id,
      title: (title ?? '').trim().isEmpty ? id : title!,
    );
  }
}

class ReaderState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;
  final bool restoreTabs;
  final bool isInitialized;
  final bool splitViewEnabled;
  final List<ReaderTab> splitRightTabs;
  final int splitRightActiveIndex;
  final double splitViewRatio;
  final bool bmMode;
  final List<ReaderBmMessageTab> bmMessageTabs;
  final int bmMessageActiveIndex;
  final double bmSplitRatio;

  ReaderState({
    required this.tabs,
    required this.activeTabIndex,
    required this.restoreTabs,
    required this.isInitialized,
    required this.splitViewEnabled,
    required this.splitRightTabs,
    required this.splitRightActiveIndex,
    required this.splitViewRatio,
    required this.bmMode,
    required this.bmMessageTabs,
    required this.bmMessageActiveIndex,
    required this.bmSplitRatio,
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
    bool? splitViewEnabled,
    List<ReaderTab>? splitRightTabs,
    int? splitRightActiveIndex,
    double? splitViewRatio,
    bool? bmMode,
    List<ReaderBmMessageTab>? bmMessageTabs,
    int? bmMessageActiveIndex,
    double? bmSplitRatio,
  }) {
    return ReaderState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      restoreTabs: restoreTabs ?? this.restoreTabs,
      isInitialized: isInitialized ?? this.isInitialized,
      splitViewEnabled: splitViewEnabled ?? this.splitViewEnabled,
      splitRightTabs: splitRightTabs ?? this.splitRightTabs,
      splitRightActiveIndex:
          splitRightActiveIndex ?? this.splitRightActiveIndex,
      splitViewRatio: splitViewRatio ?? this.splitViewRatio,
      bmMode: bmMode ?? this.bmMode,
      bmMessageTabs: bmMessageTabs ?? this.bmMessageTabs,
      bmMessageActiveIndex: bmMessageActiveIndex ?? this.bmMessageActiveIndex,
      bmSplitRatio: bmSplitRatio ?? this.bmSplitRatio,
    );
  }
}

// ─── Reader notifier ─────────────────────────────────────────────────────────

class ReaderNotifier extends Notifier<ReaderState> {
  static const int bmRightTabLimit = 20;
  static const int splitRightTabLimit = 20;
  static const _restoreTabsKey = 'reader_restore_tabs';
  static const _tabsKey = 'reader_saved_tabs';
  static const _activeTabIndexKey = 'reader_active_tab_index';
  static const _splitEnabledKey = 'reader_split_enabled';
  static const _splitRatioKey = 'reader_split_ratio';
  static const _splitTabsKey = 'reader_split_tabs';
  static const _splitActiveIndexKey = 'reader_split_active_index';
  static const _splitDefault = 0.6;
  static const _splitMin = 0.35;
  static const _splitMax = 0.75;
  static const _bmModeKey = 'reader_bm_mode';
  static const _bmSplitRatioKey = 'reader_bm_split_ratio';
  static const _bmTabsKey = 'reader_bm_tabs';
  static const _bmActiveIndexKey = 'reader_bm_active_index';
  static const _bmSplitDefault = 0.6;
  static const _bmSplitMin = 0.35;
  static const _bmSplitMax = 0.75;
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
      splitViewEnabled: false,
      splitRightTabs: const [],
      splitRightActiveIndex: 0,
      splitViewRatio: _splitDefault,
      bmMode: false,
      bmMessageTabs: const [],
      bmMessageActiveIndex: 0,
      bmSplitRatio: _bmSplitDefault,
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
    final savedSplitEnabled = prefs.getBool(_splitEnabledKey) ?? false;
    final savedSplitRatio = prefs.getDouble(_splitRatioKey) ?? _splitDefault;
    final savedSplitTabsRaw = prefs.getString(_splitTabsKey);
    final savedSplitActiveIndex = prefs.getInt(_splitActiveIndexKey) ?? 0;
    final savedBmMode = prefs.getBool(_bmModeKey) ?? false;
    final savedBmRatio = prefs.getDouble(_bmSplitRatioKey) ?? _bmSplitDefault;
    final savedBmTabsRaw = prefs.getString(_bmTabsKey);
    final savedBmActiveIndex = prefs.getInt(_bmActiveIndexKey) ?? 0;

    var restoredTabs = <ReaderTab>[];
    var restoredIndex = 0;
    var splitRightTabs = <ReaderTab>[];
    var bmTabs = <ReaderBmMessageTab>[];

    if (savedSplitTabsRaw != null && savedSplitTabsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedSplitTabsRaw);
        if (decoded is List) {
          splitRightTabs = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(readerTabFromJson)
              .whereType<ReaderTab>()
              .toList();
        }
      } catch (_) {
        splitRightTabs = [];
      }
    }

    if (savedBmTabsRaw != null && savedBmTabsRaw.isNotEmpty) {
      try {
        final decoded = jsonDecode(savedBmTabsRaw);
        if (decoded is List) {
          bmTabs = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(ReaderBmMessageTab.fromJson)
              .whereType<ReaderBmMessageTab>()
              .toList();
        }
      } catch (_) {
        bmTabs = [];
      }
    }

    if (splitRightTabs.isEmpty && bmTabs.isNotEmpty) {
      final sermonLang = ref.read(selectedSermonLangProvider);
      splitRightTabs = bmTabs
          .map(
            (tab) => ReaderTab(
              type: ReaderContentType.sermon,
              title: tab.title,
              sermonId: tab.id,
              sermonLang: sermonLang,
            ),
          )
          .toList();
    }

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
        ),
      ];
      restoredIndex = 0;
    }

    final safeIndex = restoredTabs.isEmpty
        ? 0
        : restoredIndex.clamp(0, restoredTabs.length - 1);
    final safeSplitActiveIndex = splitRightTabs.isEmpty
        ? 0
        : savedSplitActiveIndex.clamp(0, splitRightTabs.length - 1);
    final safeBmActiveIndex = bmTabs.isEmpty
        ? 0
        : savedBmActiveIndex.clamp(0, bmTabs.length - 1);

    state = state.copyWith(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      restoreTabs: restoreTabs,
      isInitialized: true,
      splitViewEnabled:
          (savedSplitEnabled || (savedBmMode && bmTabs.isNotEmpty)) &&
          splitRightTabs.isNotEmpty,
      splitRightTabs: splitRightTabs,
      splitRightActiveIndex: safeSplitActiveIndex,
      splitViewRatio: savedSplitRatio.clamp(_splitMin, _splitMax),
      bmMode: savedBmMode && bmTabs.isNotEmpty,
      bmMessageTabs: bmTabs,
      bmMessageActiveIndex: safeBmActiveIndex,
      bmSplitRatio: savedBmRatio.clamp(_bmSplitMin, _bmSplitMax),
    );
    _applyPendingOpenTab();
    await prefs.setBool(_restoreTabsKey, true);
  }

  Future<void> _persistBmState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_bmModeKey, state.bmMode);
    await prefs.setDouble(_bmSplitRatioKey, state.bmSplitRatio);
    await prefs.setInt(_bmActiveIndexKey, state.bmMessageActiveIndex);
    final encodedTabs = jsonEncode(
      state.bmMessageTabs.map((t) => t.toJson()).toList(),
    );
    await prefs.setString(_bmTabsKey, encodedTabs);
  }

  Future<void> _persistSplitState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_splitEnabledKey, state.splitViewEnabled);
    await prefs.setDouble(_splitRatioKey, state.splitViewRatio);
    await prefs.setInt(_splitActiveIndexKey, state.splitRightActiveIndex);
    final encodedTabs = jsonEncode(
      state.splitRightTabs.map(readerTabToJson).toList(),
    );
    await prefs.setString(_splitTabsKey, encodedTabs);
  }

  Future<void> persistBmState() => _persistBmState();

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

  void setSplitViewEnabled(bool enabled) {
    final effectiveEnabled = enabled && state.splitRightTabs.isNotEmpty;
    if (state.splitViewEnabled == effectiveEnabled) return;
    state = state.copyWith(splitViewEnabled: effectiveEnabled);
    unawaited(_persistSplitState());
  }

  void disableSplitView() {
    if (!state.splitViewEnabled) return;
    state = state.copyWith(splitViewEnabled: false);
    unawaited(_persistSplitState());
  }

  void setSplitViewRatio(double ratio, {bool persist = true}) {
    final clamped = ratio.clamp(_splitMin, _splitMax).toDouble();
    if (clamped == state.splitViewRatio) return;
    state = state.copyWith(splitViewRatio: clamped);
    if (persist) {
      unawaited(_persistSplitState());
    }
  }

  bool upsertSplitRightTab({
    required ReaderTab tab,
    required bool openInNewTab,
  }) {
    final tabs = [...state.splitRightTabs];
    var activeIndex = state.splitRightActiveIndex;

    bool isSameEntry(ReaderTab other) {
      if (tab.type != other.type) return false;
      if (tab.type == ReaderContentType.sermon) {
        return tab.sermonId != null &&
            tab.sermonId == other.sermonId &&
            (tab.sermonLang ?? 'en') == (other.sermonLang ?? 'en');
      }
      return tab.book == other.book &&
          tab.chapter == other.chapter &&
          (tab.bibleLang ?? 'en') == (other.bibleLang ?? 'en');
    }

    final existingIndex = tabs.indexWhere(isSameEntry);
    if (existingIndex >= 0) {
      tabs[existingIndex] = tab;
      activeIndex = existingIndex;
    } else if (tabs.isEmpty || !openInNewTab) {
      if (tabs.isEmpty) {
        tabs.add(tab);
        activeIndex = 0;
      } else {
        final replaceIndex = activeIndex.clamp(0, tabs.length - 1);
        tabs[replaceIndex] = tab;
        activeIndex = replaceIndex;
      }
    } else {
      if (tabs.length >= splitRightTabLimit) {
        return false;
      }
      tabs.add(tab);
      activeIndex = tabs.length - 1;
    }

    state = state.copyWith(
      splitViewEnabled: true,
      splitRightTabs: tabs,
      splitRightActiveIndex: activeIndex,
    );
    unawaited(_persistSplitState());
    return true;
  }

  void replaceActiveSplitRightTab(ReaderTab tab) {
    if (state.splitRightTabs.isEmpty) {
      upsertSplitRightTab(tab: tab, openInNewTab: false);
      return;
    }
    final tabs = [...state.splitRightTabs];
    final activeIndex = state.splitRightActiveIndex.clamp(0, tabs.length - 1);
    tabs[activeIndex] = tab;
    state = state.copyWith(
      splitViewEnabled: true,
      splitRightTabs: tabs,
      splitRightActiveIndex: activeIndex,
    );
    unawaited(_persistSplitState());
  }

  void setActiveSplitRightTab(int index) {
    if (index < 0 || index >= state.splitRightTabs.length) return;
    if (index == state.splitRightActiveIndex) return;
    state = state.copyWith(
      splitRightActiveIndex: index,
      splitViewEnabled: true,
    );
    unawaited(_persistSplitState());
  }

  void closeSplitRightTab(int index) {
    if (index < 0 || index >= state.splitRightTabs.length) return;
    final tabs = [...state.splitRightTabs]..removeAt(index);
    var activeIndex = state.splitRightActiveIndex;
    if (tabs.isEmpty) {
      activeIndex = 0;
    } else if (index < state.splitRightActiveIndex) {
      activeIndex = state.splitRightActiveIndex - 1;
    } else if (index == state.splitRightActiveIndex) {
      activeIndex = (state.splitRightActiveIndex - 1).clamp(0, tabs.length - 1);
    } else if (activeIndex >= tabs.length) {
      activeIndex = tabs.length - 1;
    }
    state = state.copyWith(
      splitRightTabs: tabs,
      splitRightActiveIndex: activeIndex,
      splitViewEnabled: tabs.isNotEmpty && state.splitViewEnabled,
    );
    unawaited(_persistSplitState());
  }

  void setBmSplitRatio(double ratio, {bool persist = true}) {
    final clamped = ratio.clamp(_bmSplitMin, _bmSplitMax).toDouble();
    if (clamped == state.bmSplitRatio) return;
    state = state.copyWith(bmSplitRatio: clamped);
    if (persist) {
      unawaited(_persistBmState());
    }
  }

  void disableBmMode() {
    if (!state.bmMode) return;
    state = state.copyWith(bmMode: false);
    unawaited(_persistBmState());
  }

  bool upsertBmMessageTab({
    required String id,
    required String title,
    required bool openInNewTab,
  }) {
    final nextTab = ReaderBmMessageTab(id: id, title: title);
    final existingIndex = state.bmMessageTabs.indexWhere((t) => t.id == id);
    final mutable = [...state.bmMessageTabs];
    var nextActive = state.bmMessageActiveIndex;

    if (existingIndex >= 0) {
      mutable[existingIndex] = nextTab;
      nextActive = existingIndex;
    } else if (mutable.isEmpty || !openInNewTab) {
      if (mutable.isEmpty) {
        mutable.add(nextTab);
        nextActive = 0;
      } else {
        final replaceIndex = nextActive.clamp(0, mutable.length - 1);
        mutable[replaceIndex] = nextTab;
        nextActive = replaceIndex;
      }
    } else {
      if (mutable.length >= bmRightTabLimit) {
        return false;
      }
      mutable.add(nextTab);
      nextActive = mutable.length - 1;
    }

    state = state.copyWith(
      bmMode: true,
      bmMessageTabs: mutable,
      bmMessageActiveIndex: nextActive,
    );
    unawaited(_persistBmState());
    return true;
  }

  void setActiveBmMessageTab(int index) {
    if (index < 0 || index >= state.bmMessageTabs.length) return;
    if (index == state.bmMessageActiveIndex) return;
    state = state.copyWith(bmMessageActiveIndex: index);
    unawaited(_persistBmState());
  }

  void closeBmMessageTab(int index) {
    if (index < 0 || index >= state.bmMessageTabs.length) return;
    final mutable = [...state.bmMessageTabs]..removeAt(index);
    var nextActive = state.bmMessageActiveIndex;
    if (mutable.isEmpty) {
      nextActive = 0;
    } else if (index < state.bmMessageActiveIndex) {
      // Keep the same logical tab active after list shifts left.
      nextActive = state.bmMessageActiveIndex - 1;
    } else if (index == state.bmMessageActiveIndex) {
      // Closing current tab should prefer the previous tab when available.
      nextActive = (state.bmMessageActiveIndex - 1).clamp(
        0,
        mutable.length - 1,
      );
    } else if (nextActive >= mutable.length) {
      nextActive = mutable.length - 1;
    }
    state = state.copyWith(
      bmMessageTabs: mutable,
      bmMessageActiveIndex: nextActive,
      bmMode: mutable.isNotEmpty && state.bmMode,
    );
    unawaited(_persistBmState());
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

final selectedBibleLangProvider = NotifierProvider<_BibleLangNotifier, String>(
  _BibleLangNotifier.new,
);

final bibleDatabaseExistsByLangProvider = FutureProvider.family<bool, String>((
  ref,
  lang,
) async {
  final installed = await ref.watch(
    defaultInstalledDbProvider((DbType.bible, lang)).future,
  );
  final code = installed?.code ?? (lang == 'ta' ? 'bsi' : 'kjv');
  final dbPath = await DatabaseManager().getDatabasePath('bible_$code.db');
  return File(dbPath).exists();
});

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
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      lang,
    ) async {
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
      final repo = await ref.watch(
        bibleRepositoryByLangProvider(args.$1).future,
      );
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
