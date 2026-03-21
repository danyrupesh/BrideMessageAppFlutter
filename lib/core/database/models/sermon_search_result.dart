class SermonSearchResult {
  final String sermonId;
  final String title;
  final String language;
  final String? date;
  final int? year;
  final String? location;
  final int? paragraphNumber;
  final String? paragraphLabel;
  final String snippet;
  final double? rank;

  /// COD: `answers.id` — deep-link scroll target on the answer screen.
  final int? codAnswerParagraphId;

  /// COD (and similar): short label for the list row (e.g. `q38`).
  final String? displayLeadingId;

  SermonSearchResult({
    required this.sermonId,
    required this.title,
    required this.language,
    this.date,
    this.year,
    this.location,
    this.paragraphNumber,
    this.paragraphLabel,
    required this.snippet,
    this.rank,
    this.codAnswerParagraphId,
    this.displayLeadingId,
  });

  factory SermonSearchResult.fromMap(Map<String, dynamic> map) {
    return SermonSearchResult(
      sermonId: (map['sermon_id']?.toString()) ?? '',
      title: map['title'] as String,
      language: map['language'] as String,
      date: map['date'] as String?,
      year: map['year'] as int?,
      location: map['location'] as String?,
      paragraphNumber: map['paragraph_number'] as int?,
      paragraphLabel: map['paragraph_label'] as String?,
      snippet: map['highlighted'] as String? ?? map['text'] as String,
      rank: map['rank'] != null ? (map['rank'] as num).toDouble() : null,
      codAnswerParagraphId: map['cod_answer_paragraph_id'] as int?,
      displayLeadingId: map['display_leading_id'] as String?,
    );
  }
}

