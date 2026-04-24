class ChurchAgesChapter {
  final int id;
  final String title;
  final int orderIndex;

  const ChurchAgesChapter({
    required this.id,
    required this.title,
    required this.orderIndex,
  });

  factory ChurchAgesChapter.fromMap(Map<String, dynamic> map) {
    return ChurchAgesChapter(
      id: map['id'] as int,
      title: map['title'] as String,
      orderIndex: map['order_index'] as int,
    );
  }
}

class ChurchAgesTopic {
  final int id;
  final int? chapterId;
  final int? parentId;
  final String title;
  final int orderIndex;
  
  // For UI hierarchical display
  final List<ChurchAgesTopic> children;

  const ChurchAgesTopic({
    required this.id,
    this.chapterId,
    this.parentId,
    required this.title,
    required this.orderIndex,
    this.children = const [],
  });

  factory ChurchAgesTopic.fromMap(Map<String, dynamic> map) {
    return ChurchAgesTopic(
      id: map['id'] as int,
      chapterId: map['chapter_id'] as int?,
      parentId: map['parent_id'] as int?,
      title: map['title'] as String,
      orderIndex: map['order_index'] as int,
    );
  }

  ChurchAgesTopic copyWith({
    int? id,
    int? chapterId,
    int? parentId,
    String? title,
    int? orderIndex,
    List<ChurchAgesTopic>? children,
  }) {
    return ChurchAgesTopic(
      id: id ?? this.id,
      chapterId: chapterId ?? this.chapterId,
      parentId: parentId ?? this.parentId,
      title: title ?? this.title,
      orderIndex: orderIndex ?? this.orderIndex,
      children: children ?? this.children,
    );
  }
}

class ChurchAgesContent {
  final int topicId;
  final String contentHtml;
  final String contentText;

  const ChurchAgesContent({
    required this.topicId,
    required this.contentHtml,
    required this.contentText,
  });

  factory ChurchAgesContent.fromMap(Map<String, dynamic> map) {
    return ChurchAgesContent(
      topicId: map['topic_id'] as int,
      contentHtml: (map['content_html'] ?? map['content_text'] ?? '') as String,
      contentText: (map['content_text'] ?? '') as String,
    );
  }
}

class ChurchAgesSearchResult {
  final int topicId;
  final String title;
  final String snippet;
  final String? chapterTitle;

  const ChurchAgesSearchResult({
    required this.topicId,
    required this.title,
    required this.snippet,
    this.chapterTitle,
  });

  factory ChurchAgesSearchResult.fromMap(Map<String, dynamic> map) {
    return ChurchAgesSearchResult(
      topicId: map['topic_id'] as int,
      title: map['title'] as String,
      snippet: map['snippet'] as String,
      chapterTitle: map['chapter_title'] as String?,
    );
  }
}
