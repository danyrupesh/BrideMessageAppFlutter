import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/models/special_book_models.dart';
import '../../../core/database/special_books_catalog_repository.dart';

// ── Language ──────────────────────────────────────────────────────────────────

class SpecialBooksLangNotifier extends Notifier<String> {
  @override
  String build() => 'en';

  void setLang(String lang) => state = lang;
}

final specialBooksLangProvider =
    NotifierProvider<SpecialBooksLangNotifier, String>(
  SpecialBooksLangNotifier.new,
);

// ── Book list ─────────────────────────────────────────────────────────────────

final specialBooksListProvider = FutureProvider.family<List<SpecialBook>, String>(
  (ref, lang) async {
    final repo = SpecialBooksCatalogRepository(lang: lang);
    return repo.listBooks();
  },
);

final specialBooksCatalogAvailableProvider = FutureProvider.family<bool, String>(
  (ref, lang) async {
    final repo = SpecialBooksCatalogRepository(lang: lang);
    return repo.isAvailable;
  },
);

// ── Single book ───────────────────────────────────────────────────────────────

final specialBookDetailProvider =
    FutureProvider.family<SpecialBook?, SpecialBookDetailKey>(
  (ref, key) async {
    final repo = SpecialBooksCatalogRepository(lang: key.lang);
    return repo.getBook(key.bookId);
  },
);

final specialBookChapterTitlesProvider =
    FutureProvider.family<List<BookChapterTitle>, SpecialBookDetailKey>(
  (ref, key) async {
    final repo = SpecialBooksCatalogRepository(lang: key.lang);
    return repo.listChapterTitles(key.bookId);
  },
);

final specialBookHasCatalogContentProvider =
    FutureProvider.family<bool, SpecialBookDetailKey>(
  (ref, key) async {
    final repo = SpecialBooksCatalogRepository(lang: key.lang);
    return repo.hasChapterContent(key.bookId);
  },
);

class SpecialBookDetailKey {
  const SpecialBookDetailKey({required this.bookId, required this.lang});
  final String bookId;
  final String lang;

  @override
  bool operator ==(Object other) =>
      other is SpecialBookDetailKey &&
      other.bookId == bookId &&
      other.lang == lang;

  @override
  int get hashCode => Object.hash(bookId, lang);
}
