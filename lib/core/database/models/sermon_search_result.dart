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
    );
  }
}

