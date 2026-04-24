import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/models/church_ages_models.dart';
import 'church_ages_provider.dart';

class ChurchAgesReaderData {
  final List<ChurchAgesTopic> hierarchicalTopics;
  final ChurchAgesContent? currentContent;
  final int? activeTopicId;
  final String? parentTopicName;
  final String? activeTopicTitle;

  ChurchAgesReaderData({
    required this.hierarchicalTopics,
    required this.currentContent,
    required this.activeTopicId,
    this.parentTopicName,
    this.activeTopicTitle,
  });
}

/// Stores the currently selected topic ID per language.
class SelectedChurchAgesTopicsNotifier extends Notifier<Map<String, int?>> {
  @override
  Map<String, int?> build() => {};

  void setTopic(String lang, int? id) {
    state = {...state, lang: id};
  }
}

final selectedChurchAgesTopicsProvider = NotifierProvider<SelectedChurchAgesTopicsNotifier, Map<String, int?>>(SelectedChurchAgesTopicsNotifier.new);

/// The main reader provider that resolves the data based on the selected topic.
final churchAgesReaderProvider = FutureProvider.family<ChurchAgesReaderData, String>((ref, lang) async {
  final repo = ref.watch(churchAgesRepositoryProvider(lang));
  final selectedTopics = ref.watch(selectedChurchAgesTopicsProvider);
  final selectedTopicId = selectedTopics[lang];
  
  final topics = await repo.getHierarchicalTopics();
  
  int? activeId = selectedTopicId;
  if (activeId == null && topics.isNotEmpty) {
    activeId = topics.first.children.isNotEmpty ? topics.first.children.first.id : topics.first.id;
  }
  
  ChurchAgesContent? content;
  String? parentName;
  String? activeTitle;

  if (activeId != null) {
    content = await repo.getContent(activeId);
    
    // Recursive search for the active topic to get its title and parent info
    void findDetails(List<ChurchAgesTopic> topics, String? currentParentName) {
      for (final t in topics) {
        if (t.id == activeId) {
          activeTitle = t.title;
          parentName = currentParentName ?? t.title;
          return;
        }
        if (t.children.isNotEmpty) {
          findDetails(t.children, currentParentName ?? t.title);
        }
        if (activeTitle != null) return;
      }
    }
    
    findDetails(topics, null);
  }

  return ChurchAgesReaderData(
    hierarchicalTopics: topics,
    currentContent: content,
    activeTopicId: activeId,
    parentTopicName: parentName,
    activeTopicTitle: activeTitle,
  );
});
