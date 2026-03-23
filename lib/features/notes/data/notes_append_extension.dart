import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_quill/flutter_quill.dart';
import '../providers/notes_provider.dart';

Future<void> appendTextToNote(WidgetRef ref, int noteId, String newText) async {
  final repo = ref.read(notesRepositoryProvider);
  final note = await repo.getById(noteId);
  if (note == null) return;
  
  Document doc;
  if (note.bodyJson != null && note.bodyJson!.isNotEmpty) {
      try {
        doc = Document.fromJson(jsonDecode(note.bodyJson!));
      } catch (_) {
        doc = Document()..insert(0, note.body);
      }
  } else {
      doc = Document()..insert(0, note.body);
  }

  final length = doc.length;
  // insert at the end. length - 1 handles the trailing newline requirement.
  if (length > 1) {
      doc.insert(length - 1, '\n\n' + newText);
  } else {
      doc.insert(0, newText);
  }

  final updatedNote = note.copyWith(
      body: doc.toPlainText(),
      bodyJson: jsonEncode(doc.toDelta().toJson()),
      updatedAt: DateTime.now(),
  );

  await repo.upsert(updatedNote);
  ref.invalidate(noteByIdProvider(note.id!));
  ref.invalidate(notesListProvider);
}