import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reader/models/reader_tab.dart';
import '../../reading_state/models/reading_flow_models.dart';
import '../../reading_state/providers/reading_state_provider.dart';
import 'sermon_provider.dart';

// ─── State ────────────────────────────────────────────────────────────────────

/// Holds one Sermon reading flow:
///   tabs[0]  = the active sermon (always present, cannot be closed)
///   tabs[1+] = Bible reference tabs added by the user while reading
class BmBibleGroup {
  final List<ReaderTab> tabs;
  final int activeIndex;

  const BmBibleGroup({required this.tabs, required this.activeIndex});

  BmBibleGroup copyWith({List<ReaderTab>? tabs, int? activeIndex}) {
    return BmBibleGroup(
      tabs: tabs ?? this.tabs,
      activeIndex: activeIndex ?? this.activeIndex,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'activeIndex': activeIndex,
      'tabs': tabs.map(readerTabToJson).toList(),
    };
  }

  factory BmBibleGroup.fromJson(Map<String, dynamic> json) {
    final tabsRaw = json['tabs'];
    final tabs = tabsRaw is List
        ? tabsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(readerTabFromJson)
              .whereType<ReaderTab>()
              .toList(growable: false)
        : <ReaderTab>[];
    var activeIndex = (json['activeIndex'] as num?)?.toInt() ?? 0;
    if (tabs.isEmpty) {
      activeIndex = 0;
    } else {
      activeIndex = activeIndex.clamp(0, tabs.length - 1);
    }
    return BmBibleGroup(tabs: tabs, activeIndex: activeIndex);
  }
}

class SermonFlowState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;
  final bool isInitialized;
  final bool bmMode;
  final BmBibleGroup bmBibleGroup;

  const SermonFlowState({
    required this.tabs,
    required this.activeTabIndex,
    required this.isInitialized,
    required this.bmMode,
    required this.bmBibleGroup,
  });

  /// The currently displayed tab, or null if no sermon is loaded.
  ReaderTab? get activeTab => tabs.isEmpty ? null : tabs[activeTabIndex];

  /// True when any sermon is loaded.
  bool get hasSermon =>
      tabs.isNotEmpty && tabs.first.type == ReaderContentType.sermon;

  SermonFlowState copyWith({
    List<ReaderTab>? tabs,
    int? activeTabIndex,
    bool? isInitialized,
    bool? bmMode,
    BmBibleGroup? bmBibleGroup,
  }) {
    return SermonFlowState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      isInitialized: isInitialized ?? this.isInitialized,
      bmMode: bmMode ?? this.bmMode,
      bmBibleGroup: bmBibleGroup ?? this.bmBibleGroup,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class SermonFlowNotifier extends Notifier<SermonFlowState> {
  static const int sermonTabLimit = 20;
  static const int bmBibleTabLimit = 20;
  ReaderTab? _pendingOpenSermon;
  String? _pendingOpenLang;
  bool _persistInFlight = false;
  bool _persistQueued = false;

  @override
  SermonFlowState build() {
    ref.listen(selectedSermonLangProvider, (previous, next) {
      if (previous != next) {
        state = state.copyWith(
          tabs: [],
          isInitialized: false,
          bmMode: false,
          bmBibleGroup: const BmBibleGroup(tabs: [], activeIndex: 0),
        );
        _hydrate();
      }
    });

    _hydrate();
    return const SermonFlowState(
      tabs: [],
      activeTabIndex: 0,
      isInitialized: false,
      bmMode: false,
      bmBibleGroup: BmBibleGroup(tabs: [], activeIndex: 0),
    );
  }

  String get _sessionKey {
    final lang = ref.read(selectedSermonLangProvider);
    return 'sermon_$lang';
  }

  Future<void> _hydrate() async {
    final repo = ref.read(readingStateRepositoryProvider);
    final activeSession = await repo.loadActiveSession(
      sessionKey: _sessionKey,
      fallbackFlowType: FlowType.sermon,
    );

    if (activeSession == null) {
      state = state.copyWith(isInitialized: true);
      _applyPendingOpenSermon();
      return;
    }

    final restoredTabs = activeSession.toReaderTabs();
    if (restoredTabs.isEmpty ||
        restoredTabs.first.type != ReaderContentType.sermon) {
      state = const SermonFlowState(
        tabs: [],
        activeTabIndex: 0,
        isInitialized: true,
        bmMode: false,
        bmBibleGroup: BmBibleGroup(tabs: [], activeIndex: 0),
      );
      _applyPendingOpenSermon();
      return;
    }

    var safeIndex = activeSession.activeTabIndex.clamp(
      0,
      restoredTabs.length - 1,
    );
    final bmState = _bmStateFromMeta(
      activeSession.meta,
      restoredTabs,
      safeIndex,
    );
    if (bmState.enabled &&
        restoredTabs[safeIndex].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(restoredTabs);
      if (firstSermon != -1) safeIndex = firstSermon;
    }
    if (!bmState.enabled &&
        restoredTabs[safeIndex].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(restoredTabs);
      if (firstSermon != -1) safeIndex = firstSermon;
    }
    state = SermonFlowState(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      isInitialized: true,
      bmMode: bmState.enabled,
      bmBibleGroup: bmState.group,
    );
    _applyPendingOpenSermon();
  }

  void _applyPendingOpenSermon() {
    final pending = _pendingOpenSermon;
    if (pending == null) return;
    final pendingLang = _pendingOpenLang;
    final currentLang = ref.read(selectedSermonLangProvider);
    if (pendingLang != null && pendingLang != currentLang) return;
    _pendingOpenSermon = null;
    _pendingOpenLang = null;
    openSermon(pending);
  }

  int _firstSermonIndex(List<ReaderTab> tabs) {
    return tabs.indexWhere((t) => t.type == ReaderContentType.sermon);
  }

  _BmState _bmStateFromMeta(
    Map<String, dynamic>? meta,
    List<ReaderTab> tabs,
    int activeIndex,
  ) {
    var enabled = false;
    var group = const BmBibleGroup(tabs: [], activeIndex: 0);
    final bmRaw = meta?['bm'];
    if (bmRaw is Map) {
      final bm = Map<String, dynamic>.from(bmRaw as Map);
      enabled = bm['enabled'] == true;
      final groupRaw = bm['group'];
      if (groupRaw is Map) {
        group = BmBibleGroup.fromJson(
          Map<String, dynamic>.from(groupRaw as Map),
        );
      } else {
        final groupsRaw = bm['groups'];
        if (groupsRaw is Map) {
          String? activeKey;
          if (activeIndex >= 0 && activeIndex < tabs.length) {
            final activeTab = tabs[activeIndex];
            if (activeTab.type == ReaderContentType.sermon) {
              activeKey = activeTab.sermonId ?? activeTab.id;
            }
          }
          Map<String, dynamic>? pick;
          if (activeKey != null && groupsRaw[activeKey] is Map) {
            pick = Map<String, dynamic>.from(groupsRaw[activeKey] as Map);
          } else {
            for (final entry in groupsRaw.entries) {
              if (entry.value is Map) {
                pick = Map<String, dynamic>.from(entry.value as Map);
                break;
              }
            }
          }
          if (pick != null) {
            group = BmBibleGroup.fromJson(pick);
          }
        }
      }
    }
    return _BmState(enabled: enabled, group: group);
  }

  Map<String, dynamic> _bmMetaFromState(SermonFlowState source) {
    return {'enabled': source.bmMode, 'group': source.bmBibleGroup.toJson()};
  }

  ReadingFlowPayloadV1 _currentPayload(SermonFlowState source) {
    return ReadingFlowPayloadV1.fromReaderTabs(
      flowType: FlowType.sermon,
      tabs: source.tabs,
      activeTabIndex: source.activeTabIndex,
      meta: {'bm': _bmMetaFromState(source)},
    );
  }

  Future<void> _persistFlowSnapshot(SermonFlowState snapshot) async {
    final repo = ref.read(readingStateRepositoryProvider);
    if (snapshot.tabs.isEmpty) {
      await repo.deleteActiveSession(_sessionKey);
      ref.invalidate(recentReadsProvider);
      return;
    }

    final payload = _currentPayload(snapshot);
    await repo.saveActiveSession(sessionKey: _sessionKey, payload: payload);

    final sermonAnchor = snapshot.tabs.first;
    final entryKey = sermonAnchor.sermonId != null
        ? 'sermon:${sermonAnchor.sermonId}'
        : 'sermon:tab:${sermonAnchor.id}';
    await repo.upsertRecentRead(
      entryKey: entryKey,
      flowType: FlowType.sermon,
      title: sermonAnchor.title,
      subtitle: 'Sermon',
      snapshot: payload,
    );
    ref.invalidate(recentReadsProvider);
  }

  Future<void> _persistFlow() async {
    if (_persistInFlight) {
      _persistQueued = true;
      return;
    }

    _persistInFlight = true;
    try {
      do {
        _persistQueued = false;
        final snapshot = state;
        await _persistFlowSnapshot(snapshot);
      } while (_persistQueued);
    } finally {
      _persistInFlight = false;
    }
  }

  /// Load a new sermon, clearing all previous Bible reference tabs.
  void openSermon(ReaderTab sermonTab) {
    state = SermonFlowState(
      tabs: [sermonTab],
      activeTabIndex: 0,
      isInitialized: true,
      bmMode: false,
      bmBibleGroup: const BmBibleGroup(tabs: [], activeIndex: 0),
    );
    unawaited(_persistFlow());
  }

  void openSermonForLanguage(String lang, ReaderTab sermonTab) {
    final currentLang = ref.read(selectedSermonLangProvider);
    if (!state.isInitialized || currentLang != lang) {
      _pendingOpenSermon = sermonTab;
      _pendingOpenLang = lang;
      if (currentLang != lang) {
        ref.read(selectedSermonLangProvider.notifier).setLang(lang);
      }
      return;
    }
    openSermon(sermonTab);
  }

  /// Add a new sermon tab without clearing existing tabs.
  /// If the sermon is already open, just activate that tab instead.
  bool addSermonTab(ReaderTab sermonTab) {
    final existingIndex = state.tabs.indexWhere(
      (t) => t.sermonId != null && t.sermonId == sermonTab.sermonId,
    );
    if (existingIndex != -1) {
      state = state.copyWith(activeTabIndex: existingIndex);
      unawaited(_persistFlow());
      return true;
    }
    if (state.tabs.length >= sermonTabLimit) {
      return false;
    }
    final newTabs = [...state.tabs, sermonTab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
    unawaited(_persistFlow());
    return true;
  }

  /// Add a Bible reference tab. Always appended after the sermon tab.
  bool addBibleTab(ReaderTab bibleTab) {
    if (state.tabs.length >= sermonTabLimit) {
      return false;
    }
    final newTabs = [...state.tabs, bibleTab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
    unawaited(_persistFlow());
    return true;
  }

  /// Replace the Bible tab at [index] with [tab].
  void replaceBibleTab(int index, ReaderTab tab) {
    if (index < 1 || index >= state.tabs.length) return;
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[index] = tab;
    state = state.copyWith(tabs: newTabs);
    unawaited(_persistFlow());
  }

  /// Replace the sermon tab at [index] with [tab] and make it active.
  void replaceSermonTab(int index, ReaderTab tab) {
    if (index < 0 || index >= state.tabs.length) return;
    if (tab.type != ReaderContentType.sermon) return;
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[index] = tab;
    state = state.copyWith(tabs: newTabs, activeTabIndex: index);
    unawaited(_persistFlow());
  }

  /// Close tab at [index]. At least one tab must always remain open.
  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    if (state.tabs.length <= 1) return;
    final removedTab = state.tabs[index];
    final newTabs = List<ReaderTab>.from(state.tabs)..removeAt(index);
    int newActive = state.activeTabIndex;
    if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    } else if (index < newActive) {
      newActive--;
    }
    if (state.bmMode &&
        newTabs.isNotEmpty &&
        newTabs[newActive].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(newTabs);
      if (firstSermon != -1) newActive = firstSermon;
    }
    state = state.copyWith(tabs: newTabs, activeTabIndex: newActive);
    unawaited(_persistFlow());
  }

  void switchTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
      unawaited(_persistFlow());
    }
  }

  void restoreSession(ReadingFlowPayloadV1 payload) {
    if (payload.flowType != FlowType.sermon) return;
    final restoredTabs = payload.toReaderTabs();
    if (restoredTabs.isEmpty ||
        restoredTabs.first.type != ReaderContentType.sermon) {
      return;
    }
    var safeIndex = payload.activeTabIndex.clamp(0, restoredTabs.length - 1);
    final bmState = _bmStateFromMeta(payload.meta, restoredTabs, safeIndex);
    if (bmState.enabled &&
        restoredTabs[safeIndex].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(restoredTabs);
      if (firstSermon != -1) safeIndex = firstSermon;
    }
    if (!bmState.enabled &&
        restoredTabs[safeIndex].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(restoredTabs);
      if (firstSermon != -1) safeIndex = firstSermon;
    }
    state = SermonFlowState(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      isInitialized: true,
      bmMode: bmState.enabled,
      bmBibleGroup: bmState.group,
    );
    unawaited(_persistFlow());
  }

  void setBmMode(bool enabled) {
    if (state.bmMode == enabled) return;
    var newActive = state.activeTabIndex;
    if (state.tabs.isNotEmpty &&
        state.tabs[newActive].type != ReaderContentType.sermon) {
      final firstSermon = _firstSermonIndex(state.tabs);
      if (firstSermon != -1) newActive = firstSermon;
    }
    state = state.copyWith(bmMode: enabled, activeTabIndex: newActive);
    unawaited(_persistFlow());
  }

  void toggleBmMode() => setBmMode(!state.bmMode);

  bool upsertBmBibleTab({
    required ReaderTab bibleTab,
    required bool openInNewTab,
  }) {
    final current = state.bmBibleGroup;
    final tabs = List<ReaderTab>.from(current.tabs);
    var activeIndex = current.activeIndex;
    if (openInNewTab || tabs.isEmpty) {
      if (tabs.length >= bmBibleTabLimit) {
        return false;
      }
      tabs.add(bibleTab);
      activeIndex = tabs.length - 1;
    } else {
      final replaceIndex = activeIndex.clamp(0, tabs.length - 1);
      tabs[replaceIndex] = bibleTab;
    }
    state = state.copyWith(
      bmBibleGroup: BmBibleGroup(tabs: tabs, activeIndex: activeIndex),
    );
    unawaited(_persistFlow());
    return true;
  }

  void setBmBibleActive(int index) {
    final current = state.bmBibleGroup;
    if (current.tabs.isEmpty) return;
    if (index < 0 || index >= current.tabs.length) return;
    state = state.copyWith(bmBibleGroup: current.copyWith(activeIndex: index));
    unawaited(_persistFlow());
  }

  void closeBmBibleTab(int index) {
    final current = state.bmBibleGroup;
    if (index < 0 || index >= current.tabs.length) return;
    final tabs = List<ReaderTab>.from(current.tabs)..removeAt(index);
    var activeIndex = current.activeIndex;
    if (tabs.isEmpty) {
      activeIndex = 0;
    } else if (index < activeIndex) {
      activeIndex = activeIndex - 1;
    } else if (index == activeIndex) {
      activeIndex = activeIndex.clamp(0, tabs.length - 1);
    }
    state = state.copyWith(
      bmBibleGroup: BmBibleGroup(tabs: tabs, activeIndex: activeIndex),
    );
    unawaited(_persistFlow());
  }

  /// Update the title of the active tab (useful for replacing "Loading..." text).
  void updateActiveTabTitle(String newTitle) {
    if (state.tabs.isEmpty ||
        state.activeTabIndex < 0 ||
        state.activeTabIndex >= state.tabs.length) {
      return;
    }

    final currentTab = state.tabs[state.activeTabIndex];
    if (currentTab.title == newTitle) return; // No change

    final updatedTab = currentTab.copyWith(title: newTitle);
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[state.activeTabIndex] = updatedTab;

    state = state.copyWith(tabs: newTabs);
    unawaited(_persistFlow());
  }
}

class _BmState {
  final bool enabled;
  final BmBibleGroup group;

  const _BmState({required this.enabled, required this.group});
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final sermonFlowProvider =
    NotifierProvider<SermonFlowNotifier, SermonFlowState>(
      SermonFlowNotifier.new,
    );
