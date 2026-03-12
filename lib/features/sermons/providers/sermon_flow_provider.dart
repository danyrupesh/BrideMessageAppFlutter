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
class SermonFlowState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;
  final bool isInitialized;

  const SermonFlowState({
    required this.tabs,
    required this.activeTabIndex,
    required this.isInitialized,
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
  }) {
    return SermonFlowState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
      isInitialized: isInitialized ?? this.isInitialized,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class SermonFlowNotifier extends Notifier<SermonFlowState> {
  @override
  SermonFlowState build() {
    ref.listen(selectedSermonLangProvider, (previous, next) {
      if (previous != next) {
        state = state.copyWith(tabs: [], isInitialized: false);
        _hydrate();
      }
    });

    _hydrate();
    return const SermonFlowState(
      tabs: [],
      activeTabIndex: 0,
      isInitialized: false,
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
      return;
    }

    final restoredTabs = activeSession.toReaderTabs();
    if (restoredTabs.isEmpty ||
        restoredTabs.first.type != ReaderContentType.sermon) {
      state = const SermonFlowState(
        tabs: [],
        activeTabIndex: 0,
        isInitialized: true,
      );
      return;
    }

    final safeIndex = activeSession.activeTabIndex.clamp(
      0,
      restoredTabs.length - 1,
    );
    state = SermonFlowState(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      isInitialized: true,
    );
  }

  ReadingFlowPayloadV1 _currentPayload() {
    return ReadingFlowPayloadV1.fromReaderTabs(
      flowType: FlowType.sermon,
      tabs: state.tabs,
      activeTabIndex: state.activeTabIndex,
    );
  }

  Future<void> _persistFlow() async {
    final repo = ref.read(readingStateRepositoryProvider);
    if (state.tabs.isEmpty) {
      await repo.deleteActiveSession(_sessionKey);
      ref.invalidate(recentReadsProvider);
      return;
    }

    final payload = _currentPayload();
    await repo.saveActiveSession(
      sessionKey: _sessionKey,
      payload: payload,
    );

    final sermonAnchor = state.tabs.first;
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

  /// Load a new sermon, clearing all previous Bible reference tabs.
  void openSermon(ReaderTab sermonTab) {
    state = SermonFlowState(
      tabs: [sermonTab],
      activeTabIndex: 0,
      isInitialized: true,
    );
    unawaited(_persistFlow());
  }

  /// Add a new sermon tab without clearing existing tabs.
  /// If the sermon is already open, just activate that tab instead.
  void addSermonTab(ReaderTab sermonTab) {
    final existingIndex = state.tabs.indexWhere(
      (t) => t.sermonId != null && t.sermonId == sermonTab.sermonId,
    );
    if (existingIndex != -1) {
      state = state.copyWith(activeTabIndex: existingIndex);
      unawaited(_persistFlow());
      return;
    }
    final newTabs = [...state.tabs, sermonTab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
    unawaited(_persistFlow());
  }

  /// Add a Bible reference tab. Always appended after the sermon tab.
  void addBibleTab(ReaderTab bibleTab) {
    final newTabs = [...state.tabs, bibleTab];
    state = state.copyWith(tabs: newTabs, activeTabIndex: newTabs.length - 1);
    unawaited(_persistFlow());
  }

  /// Replace the Bible tab at [index] with [tab].
  void replaceBibleTab(int index, ReaderTab tab) {
    if (index < 1 || index >= state.tabs.length) return;
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[index] = tab;
    state = state.copyWith(tabs: newTabs);
    unawaited(_persistFlow());
  }

  /// Close tab at [index]. At least one tab must always remain open.
  void closeTab(int index) {
    if (index < 0 || index >= state.tabs.length) return;
    if (state.tabs.length <= 1) return;
    final newTabs = List<ReaderTab>.from(state.tabs)..removeAt(index);
    int newActive = state.activeTabIndex;
    if (newActive >= newTabs.length) {
      newActive = newTabs.length - 1;
    } else if (index < newActive) {
      newActive--;
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
    final safeIndex = payload.activeTabIndex.clamp(0, restoredTabs.length - 1);
    state = SermonFlowState(
      tabs: restoredTabs,
      activeTabIndex: safeIndex,
      isInitialized: true,
    );
    unawaited(_persistFlow());
  }

  /// Update the title of the active tab (useful for replacing "Loading..." text).
  void updateActiveTabTitle(String newTitle) {
    if (state.tabs.isEmpty || state.activeTabIndex < 0 || state.activeTabIndex >= state.tabs.length) {
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

// ─── Provider ─────────────────────────────────────────────────────────────────

final sermonFlowProvider =
    NotifierProvider<SermonFlowNotifier, SermonFlowState>(
      SermonFlowNotifier.new,
    );
