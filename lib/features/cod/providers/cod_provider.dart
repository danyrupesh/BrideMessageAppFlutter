import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/cod_repository.dart';
import '../../../core/database/database_manager.dart';
import '../../../core/database/models/cod_models.dart';

final _dbManagerProvider = Provider<DatabaseManager>((_) => DatabaseManager());

final codRepositoryProvider = Provider.family<CodRepository, String>((
  ref,
  lang,
) {
  return CodRepository(ref.read(_dbManagerProvider), languageCode: lang);
});

final codQuestionsProvider =
    FutureProvider.family<
      List<CodQuestion>,
      ({
        String lang,
        String? category,
        String? search,
        bool? onlyWithScriptures,
      })
    >((ref, params) async {
      final repo = ref.read(codRepositoryProvider(params.lang));
      return repo.getQuestions(
        category: params.category,
        search: params.search,
        onlyWithScriptures: params.onlyWithScriptures,
      );
    });

final codTopicsProvider = FutureProvider.family<List<CodTopic>, String>((
  ref,
  lang,
) async {
  final repo = ref.read(codRepositoryProvider(lang));
  return repo.getTopicList();
});

final codQuestionsByTopicProvider =
    FutureProvider.family<
      List<CodQuestion>,
      ({
        String lang,
        String topicSlug,
        String? category,
        String? search,
        bool? onlyWithScriptures,
      })
    >((ref, params) async {
      final repo = ref.read(codRepositoryProvider(params.lang));
      return repo.getQuestionsByTopic(
        params.topicSlug,
        category: params.category,
        search: params.search,
        onlyWithScriptures: params.onlyWithScriptures,
      );
    });

final codQuestionDetailProvider =
    FutureProvider.family<
      (CodQuestion?, List<CodAnswerParagraph>),
      ({String lang, String id})
    >((ref, params) async {
      final repo = ref.read(codRepositoryProvider(params.lang));
      final question = await repo.getQuestion(params.id);
      final answers = question != null
          ? await repo.getAnswerParagraphs(question.id)
          : <CodAnswerParagraph>[];
      return (question, answers);
    });

final codCategoriesProvider = FutureProvider.family<List<String>, String>((
  ref,
  lang,
) async {
  final repo = ref.read(codRepositoryProvider(lang));
  return repo.getCategories();
});
