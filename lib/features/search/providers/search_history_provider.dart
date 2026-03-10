import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Simple in-memory search history for the current session.
class SearchHistoryNotifier extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void addQuery(String query) {
    final trimmed = query.trim();
    if (trimmed.length < 3) return;

    final existing = state.where((q) => q.toLowerCase() != trimmed.toLowerCase()).toList();
    state = [trimmed, ...existing].take(10).toList();
  }

  void clear() {
    state = const [];
  }
}

final searchHistoryProvider =
    NotifierProvider<SearchHistoryNotifier, List<String>>(() {
  return SearchHistoryNotifier();
});

