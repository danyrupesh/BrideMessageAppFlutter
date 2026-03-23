import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/notes/providers/notes_provider.dart';
import '../../features/notes/models/note_model.dart';
import '../../features/notes/models/source_ref.dart';

final notesBySourceProvider = FutureProvider.family<List<NoteModel>, String>((ref, searchKey) async {
  final repo = ref.read(notesRepositoryProvider);
  return repo.getNotesByLinkKey(searchKey);
});

class PreviousNotesWidget extends ConsumerWidget {
  final NoteSourceType sourceType;
  final String sourceId;

  const PreviousNotesWidget({
    super.key,
    required this.sourceType,
    required this.sourceId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final searchKey = '${sourceType.name}_$sourceId';
    final notesAsync = ref.watch(notesBySourceProvider(searchKey));
    
    return notesAsync.when(
      data: (notes) {
        if (notes.isEmpty) return const SizedBox.shrink();
        
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                   Icon(Icons.history_edu, size: 18, color: Theme.of(context).colorScheme.onTertiaryContainer),
                   const SizedBox(width: 8),
                   Text('Previous Notes', style: TextStyle(fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onTertiaryContainer)),
                ],
              ),
              const SizedBox(height: 8),
              ...notes.map((n) => Card(
                elevation: 0,
                color: Theme.of(context).colorScheme.surface,
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  title: Text(n.title.isNotEmpty ? n.title : 'Untitled Note', maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(n.body, maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push('/notes/edit', extra: n.id);
                  },
                ),
              )).toList(),
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
