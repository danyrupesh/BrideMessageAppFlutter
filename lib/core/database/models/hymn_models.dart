class Hymn {
  final int hymnNo;
  final String title;
  final String chord;
  final String firstLine;
  final String lyrics;
  final bool isFavorite;

  Hymn({
    required this.hymnNo,
    required this.title,
    required this.chord,
    required this.firstLine,
    required this.lyrics,
    this.isFavorite = false,
  });

  factory Hymn.fromRow(
    Map<String, Object?> row, {
    bool isFavorite = false,
  }) {
    final rawLyrics = (row['HymnLyrics'] as String?) ?? '';
    final parsed = _parseChordAndLyrics(rawLyrics);

    return Hymn(
      hymnNo: row['HymnNo'] as int,
      title: (row['HymnTitle'] as String? ?? '').trim(),
      chord: parsed.$1,
      firstLine: (row['FirstIndexSearch'] as String? ?? '').trim(),
      lyrics: parsed.$2.trim(),
      isFavorite: isFavorite,
    );
  }

  /// Extracts the chord (if any) and cleaned lyrics from the raw database text.
  ///
  /// Pattern is identical to Android:
  /// - If the first line before a double newline looks like a chord (e.g. C, Ab),
  ///   treat it as chord and the rest as lyrics.
  /// - Otherwise, check the first single line.
  /// - Fallback: no chord, full text is lyrics.
  static (String, String) _parseChordAndLyrics(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return ('', '');

    final doubleNewline = trimmed.indexOf('\n\n');
    if (doubleNewline > 0) {
      final possibleChord = trimmed.substring(0, doubleNewline).trim();
      final chordRe = RegExp(r'^[A-Ga-g][b#]?$');
      if (possibleChord.length <= 4 && chordRe.hasMatch(possibleChord)) {
        final lyrics = trimmed.substring(doubleNewline).trim();
        return (possibleChord, lyrics);
      }
    }

    final firstLineEnd = trimmed.indexOf('\n');
    if (firstLineEnd > 0) {
      final firstLine = trimmed.substring(0, firstLineEnd).trim();
      final chordRe = RegExp(r'^[A-Ga-g][b#]?$');
      if (firstLine.length <= 4 && chordRe.hasMatch(firstLine)) {
        final lyrics = trimmed.substring(firstLineEnd).trim();
        return (firstLine, lyrics);
      }
    }

    return ('', trimmed);
  }
}

