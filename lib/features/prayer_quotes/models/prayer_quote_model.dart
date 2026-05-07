class PrayerQuoteModel {
  final String id;
  final String lang;
  final String sourceType;
  final String? sourceGroup;
  final String? authorNameRaw;
  final String quoteHtml;
  final String quotePlain;
  final String? referenceHtml;
  final String? referencePlain;

  const PrayerQuoteModel({
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
}
