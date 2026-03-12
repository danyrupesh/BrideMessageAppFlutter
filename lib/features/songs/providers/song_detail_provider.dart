import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/database/hymn_repository.dart';
import '../../../core/database/models/hymn_models.dart';

sealed class LyricsLine {
  const LyricsLine();
}

class LyricsSectionHeader extends LyricsLine {
  const LyricsSectionHeader(this.text);
  final String text;
}

class LyricsVerseLine extends LyricsLine {
  const LyricsVerseLine(this.text);
  final String text;
}

class LyricsChorusLine extends LyricsLine {
  const LyricsChorusLine(this.text);
  final String text;
}

class LyricsSpacer extends LyricsLine {
  const LyricsSpacer();
}

enum SongReaderTheme { auto, light, dark, sepia }

sealed class SongDetailUiState {
  const SongDetailUiState({
    required this.fontSize,
    required this.lineHeight,
    required this.theme,
  });

  final double fontSize;
  final double lineHeight;
  final SongReaderTheme theme;
}

class SongDetailLoading extends SongDetailUiState {
  const SongDetailLoading({
    required super.fontSize,
    required super.lineHeight,
    required super.theme,
  });
}

class SongDetailError extends SongDetailUiState {
  const SongDetailError(
    this.message, {
    required super.fontSize,
    required super.lineHeight,
    required super.theme,
  });

  final String message;
}

class SongDetailContent extends SongDetailUiState {
  const SongDetailContent({
    required this.hymn,
    required this.prevHymnNo,
    required this.nextHymnNo,
    required this.prevTitle,
    required this.nextTitle,
    required this.lyricsLines,
    required super.fontSize,
    required super.lineHeight,
    required super.theme,
  });

  final Hymn hymn;
  final int? prevHymnNo;
  final int? nextHymnNo;
  final String? prevTitle;
  final String? nextTitle;
  final List<LyricsLine> lyricsLines;

  SongDetailContent copyWith({
    Hymn? hymn,
    int? prevHymnNo,
    int? nextHymnNo,
    String? prevTitle,
    String? nextTitle,
    List<LyricsLine>? lyricsLines,
    double? fontSize,
    double? lineHeight,
    SongReaderTheme? theme,
  }) {
    return SongDetailContent(
      hymn: hymn ?? this.hymn,
      prevHymnNo: prevHymnNo ?? this.prevHymnNo,
      nextHymnNo: nextHymnNo ?? this.nextHymnNo,
      prevTitle: prevTitle ?? this.prevTitle,
      nextTitle: nextTitle ?? this.nextTitle,
      lyricsLines: lyricsLines ?? this.lyricsLines,
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      theme: theme ?? this.theme,
    );
  }
}

class SongDetailNotifier extends Notifier<SongDetailUiState> {
  late final HymnRepository _repo;
  double _fontSize = 20;
  double _lineHeight = 1.7;
  SongReaderTheme _theme = SongReaderTheme.auto;

  int _loadRequestId = 0;

  @override
  SongDetailUiState build() {
    _repo = ref.read(hymnRepositoryProvider);
    Future.microtask(_loadPersistedSettings);
    return SongDetailLoading(
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      theme: _theme,
    );
  }

  Future<void> _loadPersistedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _fontSize = prefs.getDouble('reader_fontSize') ?? 20;
    _lineHeight = prefs.getDouble('reader_lineHeight') ?? 1.7;
    _theme = SongReaderTheme.values.firstWhere(
      (e) => e.name == (prefs.getString('reader_theme') ?? 'auto'),
      orElse: () => SongReaderTheme.auto,
    );
    _emitSettings();
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('reader_fontSize', _fontSize);
    await prefs.setDouble('reader_lineHeight', _lineHeight);
    await prefs.setString('reader_theme', _theme.name);
  }

  Future<void> navigateToNext() async {
    final current = state;
    if (current is! SongDetailContent) return;
    final nextNo = current.nextHymnNo;
    if (nextNo == null) return;
    await _load(nextNo);
  }

  Future<void> navigateToPrevious() async {
    final current = state;
    if (current is! SongDetailContent) return;
    final prevNo = current.prevHymnNo;
    if (prevNo == null) return;
    await _load(prevNo);
  }

  Future<void> toggleFavorite() async {
    final current = state;
    if (current is! SongDetailContent) return;

    final currentHymn = current.hymn;
    await _repo.toggleFavorite(currentHymn.hymnNo);

    state = current.copyWith(
      hymn: Hymn(
        hymnNo: currentHymn.hymnNo,
        title: currentHymn.title,
        chord: currentHymn.chord,
        firstLine: currentHymn.firstLine,
        lyrics: currentHymn.lyrics,
        isFavorite: !currentHymn.isFavorite,
      ),
    );
  }

  void setFontSize(double value) {
    _fontSize = value.clamp(12.0, 32.0);
    _emitSettings();
    _saveSettings();
  }

  void increaseFontSize() => setFontSize(_fontSize + 1);

  void decreaseFontSize() => setFontSize(_fontSize - 1);

  void setLineHeight(double value) {
    _lineHeight = value.clamp(1.2, 2.0);
    _emitSettings();
    _saveSettings();
  }

  void setTheme(SongReaderTheme theme) {
    _theme = theme;
    _emitSettings();
    _saveSettings();
  }

  Future<void> loadFor(int hymnNo) async {
    await _load(hymnNo);
  }

  void _emitSettings() {
    final current = state;
    state = switch (current) {
      SongDetailLoading() => SongDetailLoading(
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          theme: _theme,
        ),
      SongDetailError(:final message) => SongDetailError(
          message,
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          theme: _theme,
        ),
      SongDetailContent() => (current).copyWith(
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          theme: _theme,
        ),
    };
  }

  Future<void> _load(int hymnNo) async {
    final requestId = ++_loadRequestId;

    state = SongDetailLoading(
      fontSize: _fontSize,
      lineHeight: _lineHeight,
      theme: _theme,
    );

    try {
      final hymn = await _repo.getSongByNo(hymnNo);
      if (hymn == null) {
        if (requestId != _loadRequestId) return;
        state = SongDetailError(
          'Hymn #$hymnNo not found',
          fontSize: _fontSize,
          lineHeight: _lineHeight,
          theme: _theme,
        );
        return;
      }

      final prev = await _repo.getPreviousSong(hymnNo);
      final next = await _repo.getNextSong(hymnNo);
      final lines = _parseLyricsLines(hymn.lyrics);

      if (requestId != _loadRequestId) return;
      state = SongDetailContent(
        hymn: hymn,
        prevHymnNo: prev?.hymnNo,
        nextHymnNo: next?.hymnNo,
        prevTitle: prev?.title,
        nextTitle: next?.title,
        lyricsLines: lines,
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        theme: _theme,
      );
    } catch (e) {
      if (requestId != _loadRequestId) return;
      state = SongDetailError(
        e.toString(),
        fontSize: _fontSize,
        lineHeight: _lineHeight,
        theme: _theme,
      );
    }
  }

  List<LyricsLine> _parseLyricsLines(String rawLyrics) {
    final normalized = rawLyrics.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final rawLines = normalized.split('\n');

    final out = <LyricsLine>[];
    var inChorus = false;

    for (final raw in rawLines) {
      final line = raw.trimRight();
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        if (out.isEmpty || out.last is LyricsSpacer) continue;
        out.add(const LyricsSpacer());
        inChorus = false;
        continue;
      }

      final section = _tryParseSectionHeader(trimmed);
      if (section != null) {
        out.add(LyricsSectionHeader(section));
        final upper = section.toUpperCase();
        inChorus = upper.startsWith('CHORUS') || upper.startsWith('REFRAIN');
        continue;
      }

      out.add(inChorus ? LyricsChorusLine(trimmed) : LyricsVerseLine(trimmed));
    }

    while (out.isNotEmpty && out.last is LyricsSpacer) {
      out.removeLast();
    }

    return out;
  }

  String? _tryParseSectionHeader(String line) {
    var cleaned = line.trim();
    cleaned = cleaned.replaceAll(RegExp(r'^[\[\(]'), '');
    cleaned = cleaned.replaceAll(RegExp(r'[\]\)]$'), '');
    cleaned = cleaned.replaceAll(RegExp(r':$'), '');

    final upper = cleaned.toUpperCase();
    final match = RegExp(
      r'^(CHORUS|REFRAIN|VERSE|BRIDGE|TAG|INTRO|OUTRO)\b(.*)$',
    ).firstMatch(upper);
    if (match == null) return null;

    final tail = (match.group(2) ?? '').trim();
    if (tail.isEmpty) return match.group(1)!;

    final safeTail = tail.replaceAll(RegExp(r'[^0-9A-Z ]'), '').trim();
    if (safeTail.isEmpty) return match.group(1)!;
    return '${match.group(1)!} $safeTail';
  }
}

final songDetailProvider =
    NotifierProvider<SongDetailNotifier, SongDetailUiState>(
  SongDetailNotifier.new,
);
