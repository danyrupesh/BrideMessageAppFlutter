enum StorySectionType { wmbStories, kidsCorner, timeline, witnesses }

extension StorySectionTypeTable on StorySectionType {
  String get tableName {
    switch (this) {
      case StorySectionType.wmbStories:
        return 'wmb_stories';
      case StorySectionType.kidsCorner:
        return 'kids_corner';
      case StorySectionType.timeline:
        return 'timeline';
      case StorySectionType.witnesses:
        return 'witnesses';
    }
  }

  String get label {
    switch (this) {
      case StorySectionType.wmbStories:
        return 'Stories By William Branham';
      case StorySectionType.kidsCorner:
        return "Kid's Corner (Children)";
      case StorySectionType.timeline:
        return 'Time-Line W.M. Branham';
      case StorySectionType.witnesses:
        return 'Witnesses to Branham Ministry';
    }
  }

  static StorySectionType fromName(String value) {
    return StorySectionType.values.firstWhere(
      (item) => item.name == value || item.tableName == value,
      orElse: () => StorySectionType.wmbStories,
    );
  }
}

class StoryEntity {
  const StoryEntity({
    required this.id,
    required this.lang,
    required this.title,
    required this.content,
    required this.section,
  });

  final String id;
  final String lang;
  final String title;
  final String content;
  final StorySectionType section;

  factory StoryEntity.fromMap(
    Map<String, dynamic> map,
    StorySectionType section,
  ) {
    return StoryEntity(
      id: (map['id'] ?? '').toString(),
      lang: (map['lang'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      content: (map['content'] ?? '').toString(),
      section: section,
    );
  }
}
