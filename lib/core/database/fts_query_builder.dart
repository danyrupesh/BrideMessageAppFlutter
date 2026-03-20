/// Utility class to map query strings into valid FTS5 MATCH expressions.
class FtsQueryBuilder {
  static final RegExp _quoteChars = RegExp(r'["“”]');
  static final RegExp _splitter = RegExp(r'\s+');
  // Keep combining marks too, so Indic scripts (Tamil, etc.) are preserved.
  static final RegExp _tokenChars = RegExp(
    r'[^\p{L}\p{M}\p{N}_]',
    unicode: true,
  );

  /// Converts a user search query into a FTS5 MATCH pattern.
  ///
  /// - [exactMatch]: quote the whole phrase as-is.
  /// - [anyWord]: use `OR` between tokens instead of `AND`.
  /// - [prefixOnly]: only use the last token as a prefix term (for autocomplete).
  static String buildMatchQuery(
    String rawQuery, {
    bool exactMatch = false,
    bool anyWord = false,
    bool prefixOnly = false,
  }) {
    if (rawQuery.trim().isEmpty) return '__no_match__';

    // Keep Unicode letters/numbers (Tamil, etc.) and strip FTS operators.
    final cleanQuery = rawQuery.replaceAll(_quoteChars, ' ').trim();
    if (cleanQuery.isEmpty) return '__no_match__';

    final parts = cleanQuery
        .split(_splitter)
        .map((part) => part.replaceAll(_tokenChars, ''))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '__no_match__';

    if (exactMatch) {
      return '"${parts.join(' ')}"';
    }

    if (prefixOnly) {
      final last = parts.last;
      return '$last*';
    }

    final separator = anyWord ? ' OR ' : ' AND ';
    final matchTerms = parts.map((part) => '$part*').join(separator);

    return matchTerms;
  }
}

