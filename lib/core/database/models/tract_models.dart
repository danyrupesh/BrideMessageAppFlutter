class TractEntity {
  final String id;
  final String lang;
  final String title;
  final String content;

  const TractEntity({
    required this.id,
    required this.lang,
    required this.title,
    required this.content,
  });

  factory TractEntity.fromMap(Map<String, dynamic> map) {
    return TractEntity(
      id: (map['id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
    );
  }
}
