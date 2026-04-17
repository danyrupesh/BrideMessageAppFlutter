import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/tract_repository.dart';
import '../models/tract_model.dart';

sealed class TractsUiState {
  const TractsUiState();
}

class TractsLoading extends TractsUiState {
  const TractsLoading();
}

class TractsSuccess extends TractsUiState {
  final List<Tract> tracts;
  final String query;
  final bool isSearchActive;
  final bool searchContent;

  const TractsSuccess({
    required this.tracts,
    required this.query,
    required this.isSearchActive,
    required this.searchContent,
  });
}

class TractsError extends TractsUiState {
  final String message;
  const TractsError(this.message);
}

class _ActiveTractLangNotifier extends Notifier<String> {
  @override
  String build() => 'en';
  void setLang(String lang) => state = lang;
}

final activeTractLangProvider =
    NotifierProvider<_ActiveTractLangNotifier, String>(_ActiveTractLangNotifier.new);

class TractsNotifier extends Notifier<TractsUiState> {
  String _query = '';
  bool _searchContent = false;
  List<Tract> _allTracts = [];

  @override
  TractsUiState build() {
    _loadInitial();
    return const TractsLoading();
  }

  Future<void> _loadInitial() async {
    try {
      final repos = [
        TractRepository(DatabaseManager(), 'en'),
        TractRepository(DatabaseManager(), 'ta'),
      ];
      final all = <Tract>[];
      for (final repo in repos) {
        final rows = await repo.listTracts();
        all.addAll(
          rows.map(
            (row) => Tract(
              id: row.id,
              lang: row.lang,
              title: row.title,
              content: row.content,
            ),
          ),
        );
      }
      _allTracts = all;
      _emit();
    } catch (e) {
      state = TractsError(e.toString());
    }
  }

  void onSearchQueryChanged(String query) {
    _query = query.trim();
    _emit();
  }

  void onClearSearch() {
    _query = '';
    _searchContent = false;
    _emit();
  }

  void toggleSearchContent() {
    _searchContent = !_searchContent;
    _emit();
  }

  void _emit() {
    if (_allTracts.isEmpty) {
      state = const TractsLoading();
      return;
    }

    final lang = ref.watch(activeTractLangProvider);
    final langTracts = _allTracts.where((t) => t.lang == lang).toList();

    List<Tract> filtered = langTracts;
    if (_query.isNotEmpty) {
      final queryNorm = _normalize(_query);
      filtered = langTracts.where((t) {
        if (_searchContent) {
          return _normalize(t.title).contains(queryNorm) ||
                 _normalize(t.content).contains(queryNorm);
        } else {
          return _normalize(t.title).contains(queryNorm);
        }
      }).toList();
    }

    state = TractsSuccess(
      tracts: filtered,
      query: _query,
      isSearchActive: _query.isNotEmpty,
      searchContent: _searchContent,
    );
  }

  String _normalize(String text) {
    // Basic lowercase normalization.
    return text.toLowerCase();
  }
}

final tractsProvider =
    NotifierProvider<TractsNotifier, TractsUiState>(TractsNotifier.new);

