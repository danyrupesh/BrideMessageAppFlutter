import 'package:uuid/uuid.dart';

enum ReaderContentType { bible, sermon }

class ReaderTab {
  final String id;
  final ReaderContentType type;
  final String title;
  final String? book;
  final int? chapter;
  final int? verse; // optional — used to scroll to a specific verse on open
  final String? sermonId;

  ReaderTab({
    String? id,
    required this.type,
    required this.title,
    this.book,
    this.chapter,
    this.verse,
    this.sermonId,
  }) : id = id ?? const Uuid().v4();

  ReaderTab copyWith({
    String? title,
    String? book,
    int? chapter,
    int? verse,
    String? sermonId,
  }) {
    return ReaderTab(
      id: id,
      type: type,
      title: title ?? this.title,
      book: book ?? this.book,
      chapter: chapter ?? this.chapter,
      verse: verse,
      sermonId: sermonId ?? this.sermonId,
    );
  }
}
