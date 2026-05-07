class QuoteModel {
  final String id;
  final String lang;
  final String sourceType;
  final String? sourceGroup;
  final String? listTitle;
  final String quotePlain;
  final String? referencePlain;
  final int? sortOrder;

  const QuoteModel({
    required this.id,
    required this.lang,
    required this.sourceType,
    this.sourceGroup,
    this.listTitle,
    required this.quotePlain,
    this.referencePlain,
    this.sortOrder,
  });
}
