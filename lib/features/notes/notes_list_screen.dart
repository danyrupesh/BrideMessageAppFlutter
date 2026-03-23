import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'models/source_ref.dart';
import 'providers/notes_provider.dart';

class NotesListScreen extends ConsumerStatefulWidget {
  const NotesListScreen({
    super.key,
    this.initialSource,
    this.attachToExisting = false,
  });

  final NoteSourceRef? initialSource;
  final bool attachToExisting;

  @override
  ConsumerState<NotesListScreen> createState() => _NotesListScreenState();
}

class _NotesListScreenState extends ConsumerState<NotesListScreen> {
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notesAsync = ref.watch(notesListProvider);
    final query = ref.watch(notesSearchQueryProvider);
    final tagsAsync = ref.watch(noteTagsProvider);
    final selectedTag = ref.watch(notesTagFilterProvider);
    final categoriesAsync = ref.watch(noteCategoriesProvider);
    final selectedCategory = ref.watch(notesCategoryFilterProvider);

    if (_searchController.text != query) {
      _searchController.value = TextEditingValue(
        text: query,
        selection: TextSelection.collapsed(offset: query.length),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notes'),
        actions: [
          categoriesAsync.when(
            data: (categories) {
              if (categories.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String?>(
                tooltip: 'Filter by category',
                icon: const Icon(Icons.folder_open_outlined),
                onSelected: (value) {
                  ref.read(notesCategoryFilterProvider.notifier).setFilter(value);
                  ref.invalidate(notesListProvider);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text('All categories'),
                  ),
                  ...categories.map(
                    (category) => PopupMenuItem<String?>(
                      value: category,
                      child: Row(
                        children: [
                          if (selectedCategory == category)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.check, size: 16),
                            ),
                          Text(category),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
          tagsAsync.when(
            data: (tags) {
              if (tags.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String?>(
                tooltip: 'Filter by tag',
                icon: const Icon(Icons.filter_alt_outlined),
                onSelected: (value) {
                  ref.read(notesTagFilterProvider.notifier).setFilter(value);
                  ref.invalidate(notesListProvider);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem<String?>(
                    value: null,
                    child: Text('All tags'),
                  ),
                  ...tags.map(
                    (tag) => PopupMenuItem<String?>(
                      value: tag,
                      child: Row(
                        children: [
                          if (selectedTag == tag)
                            const Padding(
                              padding: EdgeInsets.only(right: 8),
                              child: Icon(Icons.check, size: 16),
                            ),
                          Text(tag),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final source = widget.initialSource;
          if (source == null) {
            context.push('/notes/edit');
            return;
          }

          final query = source.toQueryParameters();
          context.push(
            Uri(path: '/notes/edit', queryParameters: query).toString(),
          );
        },
        icon: const Icon(Icons.note_add_outlined),
        label: const Text('New Note'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search notes',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: query.trim().isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          ref
                              .read(notesSearchQueryProvider.notifier)
                              .setQuery('');
                          ref.invalidate(notesListProvider);
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onChanged: (value) {
                ref.read(notesSearchQueryProvider.notifier).setQuery(value);
                ref.invalidate(notesListProvider);
              },
            ),
          ),
          Expanded(
            child: notesAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('No notes found.'));
                }

                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final note = item.note;
                    final title = note.title.trim().isEmpty
                        ? 'Untitled Note'
                        : note.title.trim();

                    return ListTile(
                      title: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (note.category.trim().isNotEmpty)
                            Text(
                              'Category: ${note.category.trim()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (note.linkedSources.isNotEmpty)
                            Text(
                              note.linkedSources.first.summary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 2),
                          Text(
                            item.snippet,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        if (note.id == null) return;
                        final source = widget.initialSource;
                        if (widget.attachToExisting && source != null) {
                          final sourceQuery = source.toQueryParameters();
                          final query = <String, String>{
                            'id': '${note.id}',
                            ...sourceQuery,
                          };
                          query['id_ref'] = source.id;
                          query.remove('id');
                          query['id'] = '${note.id}';
                          context.push(
                            Uri(
                              path: '/notes/edit',
                              queryParameters: query,
                            ).toString(),
                          );
                          return;
                        }

                        context.push('/notes/edit?id=${note.id}');
                      },
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Failed to load notes: $error'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
