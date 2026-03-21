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

/// One search hit row: a single [answers] paragraph that matched the query.
class CodAnswerSearchHit {
  final String questionId;
  final int answerParagraphId;
  final int orderIndex;
  final String? paraLabel;
  final String questionTitle;
  final int? questionNumber;
  /// Snippet with `<b>...</b>` around the matched span (for FTS-style highlight UI).
  final String snippetHtml;

  const CodAnswerSearchHit({
    required this.questionId,
    required this.answerParagraphId,
    required this.orderIndex,
    required this.paraLabel,
    required this.questionTitle,
    required this.questionNumber,
    required this.snippetHtml,
  });
}

/// How to combine tokens from the search query against answer text.
enum CodSearchMatchMode {
  /// Whole query as a single substring.
  phrase,

  /// Every token must appear (AND).
  allWords,

  /// Any token may appear (OR).
  anyWord,
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

