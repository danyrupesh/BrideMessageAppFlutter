import '../../../core/database/models/story_models.dart';

class Story {
  const Story({
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
}
