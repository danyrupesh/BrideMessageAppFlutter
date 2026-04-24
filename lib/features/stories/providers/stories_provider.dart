import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_manager.dart';
import '../../../core/database/models/story_models.dart';
import '../../../core/database/story_repository.dart';
import '../models/story_model.dart';

class StoriesQuery {
  const StoriesQuery({
    required this.lang,
    required this.section,
    this.searchText = '',
    this.searchContent = false,
  });

  final String lang;
  final StorySectionType section;
  final String searchText;
  final bool searchContent;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoriesQuery &&
          runtimeType == other.runtimeType &&
          lang == other.lang &&
          section == other.section &&
          searchText == other.searchText &&
          searchContent == other.searchContent;

  @override
  int get hashCode =>
      lang.hashCode ^
      section.hashCode ^
      searchText.hashCode ^
      searchContent.hashCode;
}

final storyRepositoryProvider = Provider.family<StoryRepository, String>((ref, lang) {
  return StoryRepository(DatabaseManager(), lang);
});

final storiesProvider = FutureProvider.family<List<Story>, StoriesQuery>((ref, query) async {
  final repository = ref.read(storyRepositoryProvider(query.lang));
  final rows = await repository.listStories(
    section: query.section,
    query: query.searchText.trim().isEmpty ? null : query.searchText.trim(),
    searchContent: query.searchContent,
  );
  return rows
      .map(
        (row) => Story(
          id: row.id,
          lang: row.lang,
          title: row.title,
          content: row.content,
          section: row.section,
        ),
      )
      .toList();
});

class StoryByIdQuery {
  const StoryByIdQuery({
    required this.lang,
    required this.section,
    required this.id,
  });

  final String lang;
  final StorySectionType section;
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StoryByIdQuery &&
          runtimeType == other.runtimeType &&
          lang == other.lang &&
          section == other.section &&
          id == other.id;

  @override
  int get hashCode => lang.hashCode ^ section.hashCode ^ id.hashCode;
}

final storyByIdProvider = FutureProvider.family<Story?, StoryByIdQuery>((ref, query) async {
  final repository = ref.read(storyRepositoryProvider(query.lang));
  final row = await repository.getById(section: query.section, id: query.id);
  if (row == null) return null;
  return Story(
    id: row.id,
    lang: row.lang,
    title: row.title,
    content: row.content,
    section: row.section,
  );
});
