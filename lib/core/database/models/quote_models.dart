class QuoteEntity {
  final String id;
  final String lang;
  final String sourceType;
  final String? sourceGroup;
  final String? listTitle;
  final String quotePlain;
  final String? referencePlain;
  final int? sortOrder;

  const QuoteEntity({
    required this.id,
    required this.lang,
    required this.sourceType,
    this.sourceGroup,
    this.listTitle,
    required this.quotePlain,
    this.referencePlain,
    this.sortOrder,
  });

  factory QuoteEntity.fromMap(Map<String, dynamic> map) {
    return QuoteEntity(
      id: (map['id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      sourceType: (map['source_type'] ?? 'unknown').toString(),
      sourceGroup: map['source_group']?.toString(),
      listTitle: map['list_title']?.toString(),
      quotePlain: (map['quote_plain'] ?? '').toString(),
      referencePlain: map['reference_plain']?.toString(),
      sortOrder: map['sort_order'] as int?,
    );
  }
}

class PrayerQuoteEntity {
  final String id;
  final String lang;
  final String sourceType;
  final String? sourceGroup;
  final String? authorNameRaw;
  final String quoteHtml;
  final String quotePlain;
  final String? referenceHtml;
  final String? referencePlain;

  const PrayerQuoteEntity({
    required this.id,
    required this.lang,
    required this.sourceType,
    this.sourceGroup,
    this.authorNameRaw,
    required this.quoteHtml,
    required this.quotePlain,
    this.referenceHtml,
    this.referencePlain,
  });

  factory PrayerQuoteEntity.fromMap(Map<String, dynamic> map) {
    return PrayerQuoteEntity(
      id: (map['id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      sourceType: (map['source_type'] ?? 'unknown').toString(),
      sourceGroup: map['source_group']?.toString(),
      authorNameRaw: map['author_name_raw']?.toString(),
      quoteHtml: (map['quote_html'] ?? '').toString(),
      quotePlain: (map['quote_plain'] ?? '').toString(),
      referenceHtml: map['reference_html']?.toString(),
      referencePlain: map['reference_plain']?.toString(),
    );
  }
}
