import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/church_ages_repository.dart';
import '../../../core/database/models/church_ages_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:io';
import 'package:path/path.dart' as p;
import '../../../core/database/database_manager.dart';

final localDatabaseExistsProvider = FutureProvider.family<bool, String>((ref, lang) async {
  final fileName = lang == 'ta' ? 'church_ages_ta.db' : 'church_ages_en.db';
  final dbDir = await DatabaseManager().getDatabaseDirectoryPath();
  final path = p.join(dbDir.path, fileName);
  return File(path).exists();
});

class ActiveChurchAgesLangNotifier extends Notifier<String> {
  static const _prefKey = 'selected_church_ages_lang';

  @override
  String build() {
    _loadLang();
    return 'en';
  }

  Future<void> _loadLang() async {
    final prefs = await SharedPreferences.getInstance();
    final lang = prefs.getString(_prefKey) ?? 'en';
    state = lang;
  }

  Future<void> setLang(String lang) async {
    state = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, lang);
  }
}

final activeChurchAgesLangProvider = NotifierProvider<ActiveChurchAgesLangNotifier, String>(ActiveChurchAgesLangNotifier.new);

final churchAgesRepositoryProvider = Provider.family<ChurchAgesRepository, String>((ref, lang) {
  return ChurchAgesRepository(DatabaseManager(), lang);
});

abstract class ChurchAgesUiState {}

class ChurchAgesLoading extends ChurchAgesUiState {}

class ChurchAgesError extends ChurchAgesUiState {
  final String message;
  ChurchAgesError(this.message);
}

class ChurchAgesSuccess extends ChurchAgesUiState {
  final List<ChurchAgesSearchResult> results;
  final List<ChurchAgesTopic> hierarchicalTopics;
  final String query;
  final bool isSearchActive;
  final bool searchContent;

  ChurchAgesSuccess({
    required this.results,
    required this.hierarchicalTopics,
    required this.query,
    required this.isSearchActive,
    required this.searchContent,
  });
}

class ChurchAgesNotifier extends Notifier<ChurchAgesUiState> {
  String _query = '';
  bool _searchContent = false;
  final String _langCode;

  ChurchAgesNotifier(this._langCode);

  @override
  ChurchAgesUiState build() {
    // Delay the initial load to the next microtask to avoid updating during build
    Future.microtask(() => _loadDefault());
    return ChurchAgesLoading();
  }

  Future<void> _loadDefault() async {
    try {
      final repo = ref.read(churchAgesRepositoryProvider(_langCode));
      
      final hierarchicalTopics = await repo.getHierarchicalTopics();

      state = ChurchAgesSuccess(
        results: const [],
        hierarchicalTopics: hierarchicalTopics,
        query: _query,
        isSearchActive: false,
        searchContent: _searchContent,
      );
    } catch (e) {
      state = ChurchAgesError(e.toString());
    }
  }

  Future<void> onSearchQueryChanged(String query) async {
    _query = query;
    if (query.trim().isEmpty) {
      _loadDefault();
      return;
    }
    _performSearch();
  }

  Future<void> toggleSearchContent() async {
    _searchContent = !_searchContent;
    if (_query.trim().isNotEmpty) {
      _performSearch();
    } else {
      if (state is ChurchAgesSuccess) {
        final current = state as ChurchAgesSuccess;
        state = ChurchAgesSuccess(
          results: current.results,
          hierarchicalTopics: current.hierarchicalTopics,
          query: _query,
          isSearchActive: false,
          searchContent: _searchContent,
        );
      }
    }
  }

  Future<void> onClearSearch() async {
    _query = '';
    _loadDefault();
  }

  Future<void> _performSearch() async {
    state = ChurchAgesLoading();
    try {
      final repo = ref.read(churchAgesRepositoryProvider(_langCode));
      
      final results = await repo.search(
        query: _query,
        searchContent: _searchContent,
      );

      state = ChurchAgesSuccess(
        results: results,
        hierarchicalTopics: const [],
        query: _query,
        isSearchActive: true,
        searchContent: _searchContent,
      );
    } catch (e) {
      state = ChurchAgesError(e.toString());
    }
  }
}

final churchAgesProvider = NotifierProvider.family<ChurchAgesNotifier, ChurchAgesUiState, String>(
  (lang) => ChurchAgesNotifier(lang),
);
