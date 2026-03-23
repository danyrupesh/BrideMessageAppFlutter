import 'source_ref.dart';

class NoteModel {
  final int? id;
  final String title;
  final String body;
  final String? bodyJson;
  final String category;
  final List<String> tags;
  final List<NoteSourceRef> linkedSources;
  final DateTime createdAt;
  final DateTime updatedAt;

  const NoteModel({
    this.id,
    required this.title,
    required this.body,
    this.bodyJson,
    this.category = '',
    required this.tags,
    this.linkedSources = const <NoteSourceRef>[],
    required this.createdAt,
    required this.updatedAt,
  });

  NoteModel copyWith({
    int? id,
    String? title,
    String? body,
    String? bodyJson,
    String? category,
    List<String>? tags,
    List<NoteSourceRef>? linkedSources,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return NoteModel(
      id: id ?? this.id,
      title: title ?? this.title,
      body: body ?? this.body,
      bodyJson: bodyJson ?? this.bodyJson,
      category: category ?? this.category,
      tags: tags ?? this.tags,
      linkedSources: linkedSources ?? this.linkedSources,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toDbMap() {
    return {
      'id': id,
      'title': title,
      'body': body,
      'body_json': bodyJson,
      'category': category,
      'tags': tags.join(','),
      'source_ref_json': NoteSourceRef.listToEncodedJson(linkedSources),
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
    };
  }

  factory NoteModel.fromDbRow(Map<String, Object?> row) {
    final tagsRaw = (row['tags'] as String?) ?? '';
    final sourceRaw = row['source_ref_json'] as String?;
    final linkedSources = NoteSourceRef.listFromEncodedJson(sourceRaw);

    return NoteModel(
      id: (row['id'] as num?)?.toInt(),
      title: (row['title'] as String?) ?? '',
      body: (row['body'] as String?) ?? '',
      bodyJson: row['body_json'] as String?,
      category: ((row['category'] as String?) ?? '').trim(),
      tags: tagsRaw
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(growable: false),
      linkedSources: linkedSources,
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        (row['created_at'] as num?)?.toInt() ?? 0,
      ),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(
        (row['updated_at'] as num?)?.toInt() ?? 0,
      ),
    );
  }
}

class NoteListItem {
  final NoteModel note;
  final String snippet;

  const NoteListItem({required this.note, required this.snippet});
}
