/// Utility class to map query strings into valid FTS5 MATCH expressions.
class FtsQueryBuilder {
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
    if (rawQuery.trim().isEmpty) return '*';

    final cleanQuery = rawQuery.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    if (cleanQuery.isEmpty) return '*';

    if (exactMatch) {
      return '"$cleanQuery"';
    }

    final parts = cleanQuery.split(RegExp(r'\s+'));
    if (parts.isEmpty) return '*';

    if (prefixOnly) {
      final last = parts.last;
      return '$last*';
    }

    final separator = anyWord ? ' OR ' : ' AND ';
    final matchTerms = parts.map((part) => '$part*').join(separator);

    return matchTerms;
  }
}

