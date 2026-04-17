class Tract {
  final String id;
  final String lang;
  final String title;
  final String content;

  Tract({
    required this.id,
    required this.lang,
    required this.title,
    required this.content,
  });

  factory Tract.fromJson(Map<String, dynamic> json) {
    return Tract(
      id: json['id'] as String,
      lang: json['lang'] as String,
      title: json['title'] as String,
      content: json['content'] as String,
    );
  }
}
