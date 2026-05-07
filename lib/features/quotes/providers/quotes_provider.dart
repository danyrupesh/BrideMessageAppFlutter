import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/quote_repository.dart';
import '../models/quote_model.dart';

// ─── UI State ────────────────────────────────────────────────────────────────

sealed class QuotesUiState {
  const QuotesUiState();
}

class QuotesLoading extends QuotesUiState {
  const QuotesLoading();
}

class QuotesSuccess extends QuotesUiState {
  final List<QuoteModel> quotes;
  final String query;
  final bool isSearchActive;
  final String? selectedSourceType;
  final String? selectedSourceGroup;
  final List<String> sourceTypes;
  final List<String> sourceGroups;

  const QuotesSuccess({
    required this.quotes,
    required this.query,
    required this.isSearchActive,
    required this.selectedSourceType,
    required this.selectedSourceGroup,
    required this.sourceTypes,
    required this.sourceGroups,
  });
}

class QuotesError extends QuotesUiState {
  final String message;
  const QuotesError(this.message);
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class QuotesNotifier extends Notifier<QuotesUiState> {
  String _query = '';
  String? _selectedSourceType;
  String? _selectedSourceGroup;
  List<String> _sourceTypes = [];
  List<String> _sourceGroups = [];
  List<QuoteModel> _allQuotes = [];

  QuoteRepository? _repoInstance;
  QuoteRepository get _repo => _repoInstance ??= QuoteRepository(DatabaseManager());

  @override
  QuotesUiState build() {
    _loadInitial();
    return const QuotesLoading();
  }

  Future<void> _loadInitial() async {
    try {
      final types = await _repo.getSourceTypes();
      _sourceTypes = types;
      await _fetchQuotes();
    } catch (e) {
      state = QuotesError('Failed to load quotes: $e');
    }
  }

  Future<void> _fetchQuotes() async {
    try {
      final rows = await _repo.listQuotes(
        sourceType: _selectedSourceType,
        sourceGroup: _selectedSourceGroup,
        query: _query.isEmpty ? null : _query,
      );
      _allQuotes = rows.map((r) => QuoteModel(
        id: r.id,
        lang: r.lang,
        sourceType: r.sourceType,
        sourceGroup: r.sourceGroup,
        listTitle: r.listTitle,
        quotePlain: r.quotePlain,
        referencePlain: r.referencePlain,
        sortOrder: r.sortOrder,
      )).toList();
      _emit();
    } catch (e) {
      state = QuotesError('Failed to load quotes: $e');
    }
  }

  void _emit() {
    state = QuotesSuccess(
      quotes: _allQuotes,
      query: _query,
      isSearchActive: _query.isNotEmpty,
      selectedSourceType: _selectedSourceType,
      selectedSourceGroup: _selectedSourceGroup,
      sourceTypes: _sourceTypes,
      sourceGroups: _sourceGroups,
    );
  }

  Future<void> onSourceTypeChanged(String? sourceType) async {
    _selectedSourceType = sourceType;
    _selectedSourceGroup = null;
    _sourceGroups = [];
    if (sourceType != null) {
      try {
        _sourceGroups = await _repo.getSourceGroups(sourceType);
      } catch (_) {}
    }
    await _fetchQuotes();
  }

  Future<void> onSourceGroupChanged(String? group) async {
    _selectedSourceGroup = group;
    await _fetchQuotes();
  }

  Future<void> onSearchQueryChanged(String query) async {
    _query = query.trim();
    await _fetchQuotes();
  }

  Future<void> onClearSearch() async {
    _query = '';
    await _fetchQuotes();
  }
}

final quotesProvider =
    NotifierProvider<QuotesNotifier, QuotesUiState>(QuotesNotifier.new);

class QuotesFontSizeNotifier extends Notifier<double> {
  @override
  double build() => 16.0;

  void setFontSize(double size) {
    state = size.clamp(14.0, 28.0);
  }

  void adjust(int deltaSteps) {
    setFontSize(state + deltaSteps);
  }
}

final quotesFontSizeProvider = NotifierProvider<QuotesFontSizeNotifier, double>(
  QuotesFontSizeNotifier.new,
);
