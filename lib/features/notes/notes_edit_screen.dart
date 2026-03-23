import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/utils/desktop_file_saver.dart';
import 'models/note_model.dart';
import 'models/source_ref.dart';
import 'providers/notes_provider.dart';
import 'utils/note_pdf_generator.dart';

class NotesEditScreen extends ConsumerStatefulWidget {
  const NotesEditScreen({super.key, this.noteId, this.initialSource});

  final int? noteId;
  final NoteSourceRef? initialSource;

  @override
  ConsumerState<NotesEditScreen> createState() => _NotesEditScreenState();
}

class _NotesEditScreenState extends ConsumerState<NotesEditScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _tagsController;
  late final TextEditingController _categoryController;

  bool _loading = false;
  bool _loadedInitial = false;
  List<NoteSourceRef> _linkedSources = const <NoteSourceRef>[];
  DateTime? _createdAt;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController();
    _bodyController = TextEditingController();
    _tagsController = TextEditingController();
    _categoryController = TextEditingController();
    if (widget.initialSource != null) {
      _linkedSources = [widget.initialSource!];
    }
    _loadIfEditing();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _tagsController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  void _mergeInitialSource(NoteSourceRef source) {
    final exists = _linkedSources.any((item) => item.linkKey == source.linkKey);
    if (exists) return;
    _linkedSources = [..._linkedSources, source];
  }

  Future<void> _loadIfEditing() async {
    final noteId = widget.noteId;
    if (noteId == null) {
      setState(() => _loadedInitial = true);
      return;
    }

    setState(() => _loading = true);
    final repo = ref.read(notesRepositoryProvider);
    final note = await repo.getById(noteId);
    if (!mounted) return;

    if (note != null) {
      _titleController.text = note.title;
      _bodyController.text = note.body;
      _tagsController.text = note.tags.join(', ');
      _categoryController.text = note.category;
      _linkedSources = [...note.linkedSources];
      if (widget.initialSource != null) {
        _mergeInitialSource(widget.initialSource!);
      }
      _createdAt = note.createdAt;
    }

    setState(() {
      _loading = false;
      _loadedInitial = true;
    });
  }

  List<String> _collectTags() {
    return _tagsController.text
        .split(',')
        .map((v) => v.trim())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList(growable: false);
  }

  NoteModel _buildDraftForSave() {
    final now = DateTime.now();
    return NoteModel(
      id: widget.noteId,
      title: _titleController.text.trim(),
      body: _bodyController.text,
      bodyJson: null,
      category: _categoryController.text.trim(),
      tags: _collectTags(),
      linkedSources: _linkedSources,
      createdAt: _createdAt ?? now,
      updatedAt: now,
    );
  }

  String _buildShareText(NoteModel note) {
    final parts = <String>[];
    if (note.title.trim().isNotEmpty) {
      parts.add(note.title.trim());
    }
    if (note.linkedSources.isNotEmpty) {
      parts.add(
        'Sources: ${note.linkedSources.map((value) => value.summary).join(' | ')}',
      );
    }
    if (note.category.trim().isNotEmpty) {
      parts.add('Category: ${note.category.trim()}');
    }
    if (note.tags.isNotEmpty) {
      parts.add('Tags: ${note.tags.join(', ')}');
    }
    if (note.body.trim().isNotEmpty) {
      parts.add('');
      parts.add(note.body.trim());
    }
    return parts.join('\n');
  }

  Future<int?> _save() async {
    if (_bodyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note body cannot be empty.')),
      );
      return null;
    }

    setState(() => _loading = true);
    final repo = ref.read(notesRepositoryProvider);
    final current = _buildDraftForSave();
    final savedId = await repo.upsert(current);
    if (!mounted) return null;

    ref.invalidate(notesListProvider);
    ref.invalidate(noteTagsProvider);
    ref.invalidate(noteCategoriesProvider);
    ref.invalidate(noteByIdProvider(savedId));

    setState(() => _loading = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Note saved.')));
    return savedId;
  }

  Future<NoteModel?> _buildCurrentSavedModel() async {
    final id = await _save();
    if (id == null) return null;
    final note = await ref.read(notesRepositoryProvider).getById(id);
    return note;
  }

  Future<void> _shareNote() async {
    final note = await _buildCurrentSavedModel();
    if (note == null) return;
    await SharePlus.instance.share(ShareParams(text: _buildShareText(note)));
  }

  Future<void> _printPdf() async {
    final note = await _buildCurrentSavedModel();
    if (note == null) return;
    final doc = await buildNotePdf(note);
    await Printing.layoutPdf(
      onLayout: (_) => doc.save(),
      name: note.title.trim().isEmpty ? 'Note' : note.title.trim(),
    );
  }

  Future<void> _downloadPdf() async {
    final note = await _buildCurrentSavedModel();
    if (note == null) return;
    final doc = await buildNotePdf(note);
    final bytes = await doc.save();

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final savedPath = await DesktopFileSaver.savePdf(
        suggestedName:
            '${note.title.trim().isEmpty ? 'note' : note.title.trim()}.pdf',
        bytes: bytes,
      );
      if (!mounted) return;
      if (savedPath == null || savedPath.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('PDF saved.'),
          action: SnackBarAction(
            label: 'Show',
            onPressed: () => DesktopFileSaver.revealInExplorer(savedPath),
          ),
        ),
      );
      return;
    }

    await SharePlus.instance.share(ShareParams(text: _buildShareText(note)));
  }

  Future<void> _delete() async {
    final id = widget.noteId;
    if (id == null) return;

    await ref.read(notesRepositoryProvider).deleteById(id);
    if (!mounted) return;

    ref.invalidate(notesListProvider);
    ref.invalidate(noteTagsProvider);
    ref.invalidate(noteCategoriesProvider);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Note deleted.')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final canRender = _loadedInitial;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.noteId == null ? 'New Note' : 'Edit Note'),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: 'Save',
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
            ),
            IconButton(
              tooltip: 'Share',
              onPressed: _shareNote,
              icon: const Icon(Icons.share_outlined),
            ),
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'print') {
                  _printPdf();
                } else if (value == 'download') {
                  _downloadPdf();
                } else if (value == 'delete') {
                  _delete();
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem<String>(
                  value: 'print',
                  child: Text('Print PDF'),
                ),
                const PopupMenuItem<String>(
                  value: 'download',
                  child: Text('Download PDF'),
                ),
                if (widget.noteId != null)
                  const PopupMenuItem<String>(
                    value: 'delete',
                    child: Text('Delete'),
                  ),
              ],
            ),
          ],
        ],
      ),
      body: !canRender
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_linkedSources.isNotEmpty)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 2),
                            child: Icon(Icons.link_outlined, size: 16),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: _linkedSources
                                  .map(
                                    (source) => InputChip(
                                      label: Text(source.summary),
                                      onDeleted: () {
                                        setState(() {
                                          _linkedSources = _linkedSources
                                              .where(
                                                (item) =>
                                                    item.linkKey != source.linkKey,
                                              )
                                              .toList(growable: false);
                                        });
                                      },
                                    ),
                                  )
                                  .toList(growable: false),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    controller: _categoryController,
                    decoration: const InputDecoration(
                      labelText: 'Category',
                      hintText: 'Optional category (e.g. Sermon Notes)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      hintText: 'Optional title',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _MarkdownToolbar(controller: _bodyController),
                  const SizedBox(height: 8),
                  Expanded(
                    child: TextField(
                      controller: _bodyController,
                      maxLines: null,
                      expands: true,
                      keyboardType: TextInputType.multiline,
                      textAlignVertical: TextAlignVertical.top,
                      decoration: const InputDecoration(
                        alignLabelWithHint: true,
                        labelText: 'Body',
                        hintText: 'Write your note here...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags',
                      hintText: 'faith, prayer, sermon',
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_linkedSources.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: () async {
                          final jsonText = const JsonEncoder.withIndent(
                            '  ',
                          ).convert(
                            _linkedSources
                                .map((source) => source.toJson())
                                .toList(growable: false),
                          );
                          await Clipboard.setData(
                            ClipboardData(text: jsonText),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Sources JSON copied.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_outlined, size: 16),
                        label: const Text('Copy Source JSON'),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _MarkdownToolbar extends StatelessWidget {
  const _MarkdownToolbar({required this.controller});

  final TextEditingController controller;

  void _applyWrapper(String prefix, String suffix) {
    final selection = controller.selection;
    if (!selection.isValid) {
      controller.text = '${controller.text}$prefix$suffix';
      return;
    }

    final text = controller.text;
    final start = selection.start;
    final end = selection.end;
    final selected = start >= 0 && end >= 0 ? text.substring(start, end) : '';

    final replacement = '$prefix$selected$suffix';
    controller.value = controller.value.copyWith(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
      composing: TextRange.empty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: [
        OutlinedButton(
          onPressed: () => _applyWrapper('**', '**'),
          child: const Text('Bold'),
        ),
        OutlinedButton(
          onPressed: () => _applyWrapper('*', '*'),
          child: const Text('Italic'),
        ),
        OutlinedButton(
          onPressed: () => _applyWrapper('\n- ', ''),
          child: const Text('Bullet'),
        ),
        OutlinedButton(
          onPressed: () => _applyWrapper('\n1. ', ''),
          child: const Text('Numbered'),
        ),
      ],
    );
  }
}
