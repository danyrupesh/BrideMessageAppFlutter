import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/prayer_quote_repository.dart';
import '../models/prayer_quote_model.dart';

// ─── UI State ────────────────────────────────────────────────────────────────

sealed class PrayerQuotesUiState {
  const PrayerQuotesUiState();
}

class PrayerQuotesLoading extends PrayerQuotesUiState {
  const PrayerQuotesLoading();
}

class PrayerQuotesSuccess extends PrayerQuotesUiState {
  final List<PrayerQuoteModel> quotes;
  final String query;
  final bool isSearchActive;
  final String? selectedSourceType;
  final String? selectedSourceGroup;
  final List<String> sourceTypes;
  final List<String> sourceGroups;

  const PrayerQuotesSuccess({
    required this.quotes,
    required this.query,
    required this.isSearchActive,
    required this.selectedSourceType,
    required this.selectedSourceGroup,
    required this.sourceTypes,
    required this.sourceGroups,
  });
}

class PrayerQuotesError extends PrayerQuotesUiState {
  final String message;
  const PrayerQuotesError(this.message);
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

class PrayerQuotesNotifier extends Notifier<PrayerQuotesUiState> {
  String _query = '';
  String? _selectedSourceType;
  String? _selectedSourceGroup;
  List<String> _sourceTypes = [];
  List<String> _sourceGroups = [];
  List<PrayerQuoteModel> _allQuotes = [];

  PrayerQuoteRepository? _repoInstance;
  PrayerQuoteRepository get _repo => _repoInstance ??= PrayerQuoteRepository(DatabaseManager());

  @override
  PrayerQuotesUiState build() {
    _loadInitial();
    return const PrayerQuotesLoading();
  }

  Future<void> _loadInitial() async {
    try {
      final types = await _repo.getSourceTypes();
      _sourceTypes = types;
      await _fetchQuotes();
    } catch (e) {
      state = PrayerQuotesError('Failed to load prayer quotes: $e');
    }
  }

  Future<void> _fetchQuotes() async {
    try {
      final rows = await _repo.listQuotes(
        sourceType: _selectedSourceType,
        sourceGroup: _selectedSourceGroup,
        query: _query.isEmpty ? null : _query,
      );
      _allQuotes = rows.map((r) => PrayerQuoteModel(
        id: r.id,
        lang: r.lang,
        sourceType: r.sourceType,
        sourceGroup: r.sourceGroup,
        authorNameRaw: r.authorNameRaw,
        quoteHtml: r.quoteHtml,
        quotePlain: r.quotePlain,
        referenceHtml: r.referenceHtml,
        referencePlain: r.referencePlain,
      )).toList();
      _emit();
    } catch (e) {
      state = PrayerQuotesError('Failed to load prayer quotes: $e');
    }
  }

  void _emit() {
    state = PrayerQuotesSuccess(
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

final prayerQuotesProvider =
    NotifierProvider<PrayerQuotesNotifier, PrayerQuotesUiState>(
      () => PrayerQuotesNotifier(),
    );

class PrayerQuotesFontSizeNotifier extends Notifier<double> {
  @override
  double build() => 16.0;
  void setFontSize(double size) => state = size;
}

final prayerQuotesFontSizeProvider = NotifierProvider<PrayerQuotesFontSizeNotifier, double>(
  PrayerQuotesFontSizeNotifier.new,
);
