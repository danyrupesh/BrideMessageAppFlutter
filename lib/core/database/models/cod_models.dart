class CodQuestion {
  final String id;
  final int? number;
  final String title;
  final String? category;
  final String? topicSlug;
  final String? series;
  final String? topicTitle;
  final String? topicShortTitle;
  final String? pageRef;

  const CodQuestion({
    required this.id,
    required this.number,
    required this.title,
    this.category,
    this.topicSlug,
    this.series,
    this.topicTitle,
    this.topicShortTitle,
    this.pageRef,
  });

  factory CodQuestion.fromMap(Map<String, Object?> map) {
    return CodQuestion(
      id: map['id'] as String,
      number: map['number'] as int?,
      title: map['title'] as String,
      category: map['category'] as String?,
      topicSlug: map['topic_slug'] as String?,
      series: map['series'] as String?,
      topicTitle: map['topic_title'] as String?,
      pageRef: map['page_ref'] as String?,
      topicShortTitle: map['title_short'] as String?,
    );
  }
}

class CodAnswerParagraph {
  final int id;
  final String questionId;
  final int orderIndex;
  final String? label;
  final String plainText;

  const CodAnswerParagraph({
    required this.id,
    required this.questionId,
    required this.orderIndex,
    required this.label,
    required this.plainText,
  });

  factory CodAnswerParagraph.fromMap(Map<String, Object?> map) {
    return CodAnswerParagraph(
      id: map['id'] as int,
      questionId: map['question_id'] as String,
      orderIndex: map['order_index'] as int,
      label: map['para_label'] as String?,
      plainText: map['plain_text'] as String,
    );
  }
}

class CodTopic {
  final String topicSlug;
  final String topicTitle;

  const CodTopic({
    required this.topicSlug,
    required this.topicTitle,
  });

  factory CodTopic.fromMap(Map<String, Object?> map) {
    return CodTopic(
      topicSlug: map['topic_slug'] as String,
      topicTitle: map['topic_title'] as String,
    );
  }
}

