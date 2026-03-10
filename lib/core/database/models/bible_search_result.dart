class BibleSearchResult {
  final int id;
  final String language;
  final String book;
  final int bookIndex;
  final int chapter;
  final int verse;
  final String text;
  final String? highlighted;
  final double? rank;

  BibleSearchResult({
    required this.id,
    required this.language,
    required this.book,
    required this.bookIndex,
    required this.chapter,
    required this.verse,
    required this.text,
    this.highlighted,
    this.rank,
  });

  factory BibleSearchResult.fromMap(Map<String, dynamic> map) {
    return BibleSearchResult(
      id: map['id'] as int,
      language: map['language'] as String,
      book: map['book'] as String,
      bookIndex: map['book_index'] as int,
      chapter: map['chapter'] as int,
      verse: map['verse'] as int,
      text: map['text'] as String,
      highlighted: map['highlighted'] as String?,
      rank: map['rank'] != null ? (map['rank'] as num).toDouble() : null,
    );
  }
}
