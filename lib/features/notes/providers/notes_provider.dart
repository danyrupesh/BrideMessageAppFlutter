import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/notes_repository.dart';
import '../models/note_model.dart';

final notesRepositoryProvider = Provider<NotesRepository>(
  (_) => NotesRepository(),
);

/// Riverpod 3: use [Notifier] instead of removed [StateProvider].
class NotesSearchQueryNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

class NotesTagFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? value) => state = value;
}

class NotesCategoryFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void setFilter(String? value) => state = value;
}

final notesSearchQueryProvider =
    NotifierProvider<NotesSearchQueryNotifier, String>(
  NotesSearchQueryNotifier.new,
);

final notesTagFilterProvider =
    NotifierProvider<NotesTagFilterNotifier, String?>(
  NotesTagFilterNotifier.new,
);

final notesCategoryFilterProvider =
    NotifierProvider<NotesCategoryFilterNotifier, String?>(
  NotesCategoryFilterNotifier.new,
);

final notesListProvider = FutureProvider<List<NoteListItem>>((ref) async {
  final repo = ref.read(notesRepositoryProvider);
  final query = ref.watch(notesSearchQueryProvider);
  final tag = ref.watch(notesTagFilterProvider);
  final category = ref.watch(notesCategoryFilterProvider);
  return repo.listNotes(query: query, tag: tag, category: category);
});

final noteByIdProvider = FutureProvider.family<NoteModel?, int>((
  ref,
  id,
) async {
  final repo = ref.read(notesRepositoryProvider);
  return repo.getById(id);
});

final noteTagsProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.read(notesRepositoryProvider);
  return repo.listKnownTags();
});

final noteCategoriesProvider = FutureProvider<List<String>>((ref) async {
  final repo = ref.read(notesRepositoryProvider);
  return repo.listKnownCategories();
});
