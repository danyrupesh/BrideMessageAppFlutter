import 'dart:convert';

enum NoteSourceType { bible, sermon, cod, song }

NoteSourceType? noteSourceTypeFromString(String? raw) {
  if (raw == null || raw.trim().isEmpty) return null;
  for (final value in NoteSourceType.values) {
    if (value.name == raw) return value;
  }
  return null;
}

class NoteSourceRef {
  final NoteSourceType type;
  final String id;
  final String? title;
  final String? book;
  final int? chapter;
  final int? verse;
  final String? sermonId;
  final String? codId;
  final int? hymnNo;
  final String? lang;
  final int? paragraphIndex;
  final Map<String, dynamic>? extra;

  const NoteSourceRef({
    required this.type,
    required this.id,
    this.title,
    this.book,
    this.chapter,
    this.verse,
    this.sermonId,
    this.codId,
    this.hymnNo,
    this.lang,
    this.paragraphIndex,
    this.extra,
  });

  NoteSourceRef copyWith({
    NoteSourceType? type,
    String? id,
    String? title,
    String? book,
    int? chapter,
    int? verse,
    String? sermonId,
    String? codId,
    int? hymnNo,
    String? lang,
    int? paragraphIndex,
    Map<String, dynamic>? extra,
  }) {
    return NoteSourceRef(
      type: type ?? this.type,
      id: id ?? this.id,
      title: title ?? this.title,
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
      verse: verse ?? this.verse,
      sermonId: sermonId ?? this.sermonId,
      codId: codId ?? this.codId,
      hymnNo: hymnNo ?? this.hymnNo,
      lang: lang ?? this.lang,
      paragraphIndex: paragraphIndex ?? this.paragraphIndex,
      extra: extra ?? this.extra,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'id': id,
      'title': title,
      'book': book,
      'chapter': chapter,
      'verse': verse,
      'sermonId': sermonId,
      'codId': codId,
      'hymnNo': hymnNo,
      'lang': lang,
      'paragraphIndex': paragraphIndex,
      'extra': extra,
    };
  }

  factory NoteSourceRef.fromJson(Map<String, dynamic> json) {
    return NoteSourceRef(
      type:
          noteSourceTypeFromString(json['type'] as String?) ??
          NoteSourceType.bible,
      id: (json['id'] as String?) ?? '',
      title: json['title'] as String?,
      book: json['book'] as String?,
      chapter: (json['chapter'] as num?)?.toInt(),
      verse: (json['verse'] as num?)?.toInt(),
      sermonId: json['sermonId'] as String?,
      codId: json['codId'] as String?,
      hymnNo: (json['hymnNo'] as num?)?.toInt(),
      lang: json['lang'] as String?,
      paragraphIndex: (json['paragraphIndex'] as num?)?.toInt(),
      extra: (json['extra'] as Map?)?.cast<String, dynamic>(),
    );
  }

  static NoteSourceRef? fromEncodedJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      return NoteSourceRef.fromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static List<NoteSourceRef> listFromEncodedJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const <NoteSourceRef>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map(
              (value) => NoteSourceRef.fromJson(value.cast<String, dynamic>()),
            )
            .toList(growable: false);
      }
      if (decoded is Map) {
        return <NoteSourceRef>[
          NoteSourceRef.fromJson(decoded.cast<String, dynamic>()),
        ];
      }
      return const <NoteSourceRef>[];
    } catch (_) {
      return const <NoteSourceRef>[];
    }
  }

  static String? listToEncodedJson(List<NoteSourceRef> refs) {
    if (refs.isEmpty) return null;
    return jsonEncode(refs.map((ref) => ref.toJson()).toList(growable: false));
  }

  String get linkKey {
    return [
      type.name,
      id,
      (book ?? '').trim(),
      chapter?.toString() ?? '',
      verse?.toString() ?? '',
      (sermonId ?? '').trim(),
      (codId ?? '').trim(),
      hymnNo?.toString() ?? '',
      paragraphIndex?.toString() ?? '',
    ].join('|');
  }

  static NoteSourceRef? fromQueryParameters(Map<String, String> query) {
    final type = noteSourceTypeFromString(query['type']);
    if (type == null) return null;
    final id = (query['id_ref'] ?? query['id'] ?? '').trim();
    if (id.isEmpty) return null;

    return NoteSourceRef(
      type: type,
      id: id,
      title: query['title'],
      book: query['book'],
      chapter: int.tryParse(query['chapter'] ?? ''),
      verse: int.tryParse(query['verse'] ?? ''),
      sermonId: query['sermonId'],
      codId: query['codId'],
      hymnNo: int.tryParse(query['hymnNo'] ?? ''),
      lang: query['lang'],
      paragraphIndex: int.tryParse(query['paragraphIndex'] ?? ''),
    );
  }

  Map<String, String> toQueryParameters() {
    return {
      'type': type.name,
      'id': id,
      if ((title ?? '').trim().isNotEmpty) 'title': title!.trim(),
      if ((book ?? '').trim().isNotEmpty) 'book': book!.trim(),
      if (chapter != null) 'chapter': '$chapter',
      if (verse != null) 'verse': '$verse',
      if ((sermonId ?? '').trim().isNotEmpty) 'sermonId': sermonId!.trim(),
      if ((codId ?? '').trim().isNotEmpty) 'codId': codId!.trim(),
      if (hymnNo != null) 'hymnNo': '$hymnNo',
      if ((lang ?? '').trim().isNotEmpty) 'lang': lang!.trim(),
      if (paragraphIndex != null) 'paragraphIndex': '$paragraphIndex',
    };
  }

  String get summary {
    switch (type) {
      case NoteSourceType.bible:
        final verseSuffix = verse != null ? ':$verse' : '';
        return '${book ?? 'Bible'} ${chapter ?? ''}$verseSuffix ${lang ?? ''}'
            .trim();
      case NoteSourceType.sermon:
        return [
          if (title != null && title!.trim().isNotEmpty) title!.trim(),
          if (sermonId != null && sermonId!.trim().isNotEmpty)
            '#${sermonId!.trim()}',
        ].join(' ');
      case NoteSourceType.cod:
        return [
          'COD',
          if (codId != null && codId!.trim().isNotEmpty) codId!.trim(),
          if (lang != null && lang!.trim().isNotEmpty) '(${lang!.trim()})',
        ].join(' ');
      case NoteSourceType.song:
        return [
          'Song',
          if (hymnNo != null) '#$hymnNo',
          if (title != null && title!.trim().isNotEmpty) title!.trim(),
        ].join(' ');
    }
  }
}
