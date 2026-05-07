/// A book record from the catalog DB (special_books_catalog_{lang}.db).
class SpecialBook {
  const SpecialBook({
    required this.id,
    required this.lang,
    required this.title,
    this.titleEn,
    this.author,
    this.description,
    this.coverUrl,
    this.totalChapters = 0,
    this.hasImages = false,
    this.contentZipUrl,
    this.contentZipSize,
    this.contentVersion = 1,
    this.contentChecksum,
    this.sortOrder = 0,
    this.updatedAt,
  });

  final String id;
  final String lang;
  final String title;
  final String? titleEn;
  final String? author;
  final String? description;
  final String? coverUrl;
  final int totalChapters;
  final bool hasImages;
  final String? contentZipUrl;
  final int? contentZipSize;
  final int contentVersion;
  final String? contentChecksum;
  final int sortOrder;
  final String? updatedAt;

  factory SpecialBook.fromMap(Map<String, Object?> map) {
    return SpecialBook(
      id: (map['id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      title: (map['title'] ?? '').toString(),
      titleEn: map['title_en']?.toString(),
      author: map['author']?.toString(),
      description: map['description']?.toString(),
      coverUrl: map['cover_url']?.toString(),
      totalChapters: (map['total_chapters'] as int?) ?? 0,
      hasImages: ((map['has_images'] as int?) ?? 0) == 1,
      contentZipUrl: map['content_zip_url']?.toString(),
      contentZipSize: map['content_zip_size'] as int?,
      contentVersion: (map['content_version'] as int?) ?? 1,
      contentChecksum: map['content_checksum']?.toString(),
      sortOrder: (map['sort_order'] as int?) ?? 0,
      updatedAt: map['updated_at']?.toString(),
    );
  }
}

/// A chapter title from the catalog DB (always available offline, no body).
class BookChapterTitle {
  const BookChapterTitle({
    required this.id,
    required this.bookId,
    required this.lang,
    required this.title,
    this.orderIndex = 0,
  });

  final String id;
  final String bookId;
  final String lang;
  final String title;
  final int orderIndex;

  factory BookChapterTitle.fromMap(Map<String, Object?> map) {
    return BookChapterTitle(
      id: (map['id'] ?? '').toString(),
      bookId: (map['book_id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      title: (map['title'] ?? '').toString(),
      orderIndex: (map['order_index'] as int?) ?? 0,
    );
  }
}

/// Full chapter content from a downloaded per-book content DB.
class BookChapterContent {
  const BookChapterContent({
    required this.id,
    required this.bookId,
    required this.lang,
    required this.title,
    this.contentHtml,
    this.contentText,
    this.sourceDocxB64,
    this.orderIndex = 0,
  });

  final String id;
  final String bookId;
  final String lang;
  final String title;
  final String? contentHtml;
  final String? contentText;
  final String? sourceDocxB64;
  final int orderIndex;

  factory BookChapterContent.fromMap(Map<String, Object?> map) {
    return BookChapterContent(
      id: (map['id'] ?? '').toString(),
      bookId: (map['book_id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      title: (map['title'] ?? '').toString(),
      contentHtml: map['content_html']?.toString(),
      contentText: map['content_text']?.toString(),
      sourceDocxB64: map['source_docx_b64']?.toString(),
      orderIndex: (map['order_index'] as int?) ?? 0,
    );
  }
}

/// Download record for a book whose content has been installed.
class SpecialBookDownload {
  const SpecialBookDownload({
    required this.bookId,
    required this.lang,
    this.contentVersion,
    this.downloadedAt,
    required this.localDbPath,
  });

  final String bookId;
  final String lang;
  final int? contentVersion;
  final String? downloadedAt;
  final String localDbPath;

  factory SpecialBookDownload.fromMap(Map<String, Object?> map) {
    return SpecialBookDownload(
      bookId: (map['book_id'] ?? '').toString(),
      lang: (map['lang'] ?? 'en').toString(),
      contentVersion: map['content_version'] as int?,
      downloadedAt: map['downloaded_at']?.toString(),
      localDbPath: (map['local_db_path'] ?? '').toString(),
    );
  }

  Map<String, Object?> toMap() => {
        'book_id': bookId,
        'lang': lang,
        'content_version': contentVersion,
        'downloaded_at': downloadedAt,
        'local_db_path': localDbPath,
      };
}
