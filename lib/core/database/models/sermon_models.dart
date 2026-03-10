class SermonEntity {
  final String id;
  final String title;
  final String language;
  final String? date;
  final int? year;
  final String? duration;
  final String? location;
  final String? session;
  final int? vogrSid;
  final int? totalParagraphs;

  SermonEntity({
    required this.id,
    required this.title,
    required this.language,
    this.date,
    this.year,
    this.duration,
    this.location,
    this.session,
    this.vogrSid,
    this.totalParagraphs,
  });

  factory SermonEntity.fromMap(Map<String, dynamic> map) {
    return SermonEntity(
      id: map['id'] as String,
      title: map['title'] as String,
      language: map['language'] as String,
      date: map['date'] as String?,
      year: map['year'] as int?,
      duration: map['duration'] as String?,
      location: map['location'] as String?,
      session: map['session'] as String?,
      vogrSid: map['vogr_sid'] as int?,
      totalParagraphs: map['total_paragraphs'] as int?,
    );
  }
}

class SermonParagraphEntity {
  final int id;
  final String sermonId;
  final int? paragraphNumber;
  final String? paragraphLabel;
  final String text;

  SermonParagraphEntity({
    required this.id,
    required this.sermonId,
    this.paragraphNumber,
    this.paragraphLabel,
    required this.text,
  });

  factory SermonParagraphEntity.fromMap(Map<String, dynamic> map) {
    return SermonParagraphEntity(
      id: map['id'] as int,
      sermonId: map['sermon_id'] as String,
      paragraphNumber: map['paragraph_number'] as int?,
      paragraphLabel: map['paragraph_label'] as String?,
      text: map['text'] as String,
    );
  }
}
