import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../reader/models/reader_tab.dart';

// ─── State ────────────────────────────────────────────────────────────────────

/// Holds one Sermon reading flow:
///   tabs[0]  = the active sermon (always present, cannot be closed)
///   tabs[1+] = Bible reference tabs added by the user while reading
class SermonFlowState {
  final List<ReaderTab> tabs;
  final int activeTabIndex;

  const SermonFlowState({
    required this.tabs,
    required this.activeTabIndex,
  });

  /// The currently displayed tab, or null if no sermon is loaded.
  ReaderTab? get activeTab =>
      tabs.isEmpty ? null : tabs[activeTabIndex];

  /// True when any sermon is loaded.
  bool get hasSermon =>
      tabs.isNotEmpty && tabs.first.type == ReaderContentType.sermon;

  SermonFlowState copyWith({List<ReaderTab>? tabs, int? activeTabIndex}) {
    return SermonFlowState(
      tabs: tabs ?? this.tabs,
      activeTabIndex: activeTabIndex ?? this.activeTabIndex,
    );
  }
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class SermonFlowNotifier extends Notifier<SermonFlowState> {
  @override
  SermonFlowState build() =>
      const SermonFlowState(tabs: [], activeTabIndex: 0);

  /// Load a new sermon, clearing all previous Bible reference tabs.
  void openSermon(ReaderTab sermonTab) {
    state = SermonFlowState(
      tabs: [sermonTab],
      activeTabIndex: 0,
    );
  }

  /// Add a new sermon tab without clearing existing tabs.
  /// If the sermon is already open, just activate that tab instead.
  void addSermonTab(ReaderTab sermonTab) {
    final existingIndex = state.tabs.indexWhere(
      (t) => t.sermonId != null && t.sermonId == sermonTab.sermonId,
    );
    if (existingIndex != -1) {
      state = state.copyWith(activeTabIndex: existingIndex);
      return;
    }
    final newTabs = [...state.tabs, sermonTab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Add a Bible reference tab. Always appended after the sermon tab.
  void addBibleTab(ReaderTab bibleTab) {
    final newTabs = [...state.tabs, bibleTab];
    state = state.copyWith(
      tabs: newTabs,
      activeTabIndex: newTabs.length - 1,
    );
  }

  /// Replace the Bible tab at [index] with [tab].
  void replaceBibleTab(int index, ReaderTab tab) {
    if (index < 1 || index >= state.tabs.length) return;
    final newTabs = List<ReaderTab>.from(state.tabs);
    newTabs[index] = tab;
    state = state.copyWith(tabs: newTabs);
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
  }

  void switchTab(int index) {
    if (index >= 0 && index < state.tabs.length) {
      state = state.copyWith(activeTabIndex: index);
    }
  }
}

// ─── Provider ─────────────────────────────────────────────────────────────────

final sermonFlowProvider =
    NotifierProvider<SermonFlowNotifier, SermonFlowState>(
  SermonFlowNotifier.new,
);
