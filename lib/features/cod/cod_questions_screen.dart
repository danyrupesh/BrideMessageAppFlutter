import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/models/cod_models.dart';
import 'providers/cod_provider.dart';

class CodQuestionsScreen extends ConsumerStatefulWidget {
  final String lang;

  const CodQuestionsScreen({super.key, required this.lang});

  @override
  ConsumerState<CodQuestionsScreen> createState() => _CodQuestionsScreenState();
}

class _CodQuestionsScreenState extends ConsumerState<CodQuestionsScreen> {
  String? _search;
  String? _topicSearch;
  String? _category;
  String? _topicSlug;
  bool _onlyScriptures = false;
  static const String _allTopicsToken = '__all_topics__';
  static final RegExp _trailingQuestionRefPattern = RegExp(
    r'\s+[Qq]\.\s*\d+\s*$',
  );

  static String _categoryLabel(String slug, bool isTamil) {
    const englishMap = {
      'old-testament-questions': 'Old Testament',
      'new-testament-questions': 'New Testament',
      'hebrews-questions': 'Hebrews',
      'seals-questions': 'Seals',
    };
    const tamilMap = {
      'old-testament-questions': 'பழைய ஏற்பாடு',
      'new-testament-questions': 'புதிய ஏற்பாடு',
      'hebrews-questions': 'எபிரெயர் புத்தகத்தின்',
      'seals-questions': 'முத்திரைகள்',
    };

    final direct = isTamil ? tamilMap[slug] : englishMap[slug];
    if (direct != null) return direct;

    final fallback = slug
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\bquestions\b'), '')
        .trim();
    if (fallback.isEmpty) {
      return slug;
    }

    return fallback
        .split(' ')
        .map(
          (part) => part.isEmpty
              ? part
              : '${part[0].toUpperCase()}${part.substring(1)}',
        )
        .join(' ');
  }

  static String _displayQuestionTitle(String title) {
    final cleaned = title.replaceAll(_trailingQuestionRefPattern, '').trim();
    return cleaned.isEmpty ? title : cleaned;
  }

  static String _listQuestionTitle(CodQuestion question) {
    final shortTitle = question.topicShortTitle?.trim();
    if (shortTitle != null && shortTitle.isNotEmpty) {
      return _displayQuestionTitle(shortTitle);
    }
    return _displayQuestionTitle(question.title);
  }

  void _openAdvancedSearch() {
    final queryText = _search?.trim();
    final queryParameters = <String, String>{'tab': 'cod'};
    if (queryText != null && queryText.isNotEmpty) {
      queryParameters['q'] = queryText;
    }
    final uri = Uri(path: '/search', queryParameters: queryParameters);
    context.push(uri.toString());
  }

  Future<void> _showAllTopicsDialog(
    BuildContext context,
    List<CodTopic> topics,
    bool isTamil,
    ColorScheme cs,
  ) async {
    final selectedSlug = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        String dialogSearchQuery = '';
        return StatefulBuilder(
          builder: (context, setStateBuilder) {
            final normalizedQuery = dialogSearchQuery.trim().toLowerCase();
            final filtered = normalizedQuery.isEmpty
                ? topics
                : topics
                      .where(
                        (t) => t.topicTitle.toLowerCase().contains(
                          normalizedQuery,
                        ),
                      )
                      .toList();

            final screenWidth = MediaQuery.of(dialogContext).size.width;
            final dialogWidth = (screenWidth * 0.88)
                .clamp(320.0, 800.0)
                .toDouble();

            return AlertDialog(
              backgroundColor: cs.surfaceContainerLow,
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      isTamil ? 'தலைப்புகள்' : 'Topics',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(dialogContext).pop(),
                  ),
                ],
              ),
              contentPadding: const EdgeInsets.only(
                left: 20,
                right: 20,
                bottom: 20,
              ),
              content: SizedBox(
                width: dialogWidth,
                height: 500,
                child: Column(
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search, size: 20),
                        hintText: isTamil
                            ? 'தலைப்பைத் தேடுங்கள்...'
                            : 'Search topics...',
                        filled: true,
                        fillColor: cs.surfaceContainerHighest.withValues(
                          alpha: 0.5,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                      onChanged: (val) {
                        setStateBuilder(() {
                          dialogSearchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: filtered.isEmpty
                          ? Center(
                              child: Text(
                                isTamil
                                    ? 'தலைப்புகள் கிடைக்கவில்லை'
                                    : 'No matching topics',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              ),
                            )
                          : SingleChildScrollView(
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (dialogSearchQuery.trim().isEmpty)
                                    ActionChip(
                                      key: const ValueKey('dialog_all_topics'),
                                      label: Text(
                                        isTamil ? 'அனைத்தும்' : 'All Topics',
                                      ),
                                      backgroundColor: _topicSlug == null
                                          ? cs.primaryContainer
                                          : cs.surfaceContainerHighest,
                                      labelStyle: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: _topicSlug == null
                                            ? cs.onPrimaryContainer
                                            : cs.onSurface,
                                      ),
                                      side: BorderSide.none,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      onPressed: () {
                                        Navigator.of(
                                          dialogContext,
                                        ).pop(_allTopicsToken);
                                      },
                                    ),
                                  for (var i = 0; i < filtered.length; i++)
                                    Builder(
                                      builder: (context) {
                                        final topic = filtered[i];
                                        final isSelected =
                                            _topicSlug == topic.topicSlug;

                                        final hue = (i * 137.5) % 360;
                                        final fallbackBgColor =
                                            HSLColor.fromAHSL(
                                              1.0,
                                              hue,
                                              0.4,
                                              0.92,
                                            ).toColor();
                                        final fallbackTextColor =
                                            HSLColor.fromAHSL(
                                              1.0,
                                              hue,
                                              0.8,
                                              0.25,
                                            ).toColor();

                                        final bgColor = isSelected
                                            ? cs.primaryContainer
                                            : (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? HSLColor.fromAHSL(
                                                      1.0,
                                                      hue,
                                                      0.4,
                                                      0.15,
                                                    ).toColor()
                                                  : fallbackBgColor);
                                        final textColor = isSelected
                                            ? cs.onPrimaryContainer
                                            : (Theme.of(context).brightness ==
                                                      Brightness.dark
                                                  ? HSLColor.fromAHSL(
                                                      1.0,
                                                      hue,
                                                      0.8,
                                                      0.85,
                                                    ).toColor()
                                                  : fallbackTextColor);

                                        return ActionChip(
                                          key: ValueKey('dialog_topic_${topic.topicSlug}'),
                                          label: Text(topic.topicTitle),
                                          backgroundColor: bgColor,
                                          labelStyle: TextStyle(
                                            fontWeight: isSelected
                                                ? FontWeight.w600
                                                : FontWeight.w500,
                                            color: textColor,
                                          ),
                                          side: BorderSide.none,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          onPressed: () {
                                            Navigator.of(
                                              dialogContext,
                                            ).pop(topic.topicSlug);
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || selectedSlug == null) return;

    setState(() {
      _topicSlug = selectedSlug == _allTopicsToken ? null : selectedSlug;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTamil = widget.lang == 'ta';
    final questionsAsync = _topicSlug == null
        ? ref.watch(
            codQuestionsProvider((
              lang: widget.lang,
              category: _category,
              search: _search,
              onlyWithScriptures: _onlyScriptures ? true : null,
            )),
          )
        : ref.watch(
            codQuestionsByTopicProvider((
              lang: widget.lang,
              topicSlug: _topicSlug!,
              category: _category,
              search: _search,
              onlyWithScriptures: _onlyScriptures ? true : null,
            )),
          );
    final categoriesAsync = ref.watch(codCategoriesProvider(widget.lang));
    final topicsAsync = ref.watch(codTopicsProvider(widget.lang));
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(
          isTamil ? 'கேள்விகளும் பதில்களும்' : 'COD – Questions & Answers',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: ActionChip(
                label: Text(isTamil ? 'COD செய்திகள்' : 'COD Sermons'),
                backgroundColor: theme.colorScheme.secondaryContainer,
                labelStyle: TextStyle(
                  color: theme.colorScheme.onSecondaryContainer,
                ),
                onPressed: () {
                  final uri = Uri(
                    path: '/sermons',
                    queryParameters: {
                      'mode': 'cod',
                      'prefix': isTamil ? 'கேள்வி' : 'Question',
                      'title': isTamil
                          ? 'COD - கேள்விகளும் பதில்களும்'
                          : 'COD - Question and Answers',
                      'lang': widget.lang,
                    },
                  );
                  context.push(uri.toString());
                },
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          categoriesAsync.when(
            data: (cats) {
              final visibleCategories = cats
                  .where((c) => c != 'all-questions')
                  .toList();
              if (visibleCategories.isEmpty) return const SizedBox.shrink();
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    ChoiceChip(
                      key: const ValueKey('cat_all'),
                      label: Text(isTamil ? 'அனைத்தும்' : 'All'),
                      selected: _category == null,
                      onSelected: (_) {
                        setState(() => _category = null);
                      },
                    ),
                    const SizedBox(width: 8),
                    for (final cat in visibleCategories) ...[
                      ChoiceChip(
                        key: ValueKey('cat_$cat'),
                        label: Text(_categoryLabel(cat, isTamil)),
                        selected: _category == cat,
                        onSelected: (_) {
                          setState(() => _category = cat);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    FilterChip(
                      key: const ValueKey('filter_scriptures'),
                      label: Text(isTamil ? 'வேதவாக்கியங்கள்' : 'Scriptures'),
                      selected: _onlyScriptures,
                      onSelected: (selected) {
                        setState(() => _onlyScriptures = selected);
                      },
                    ),
                  ],
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(8),
              child: SizedBox(height: 24),
            ),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          topicsAsync.when(
            data: (topics) {
              if (topics.isEmpty) return const SizedBox.shrink();

              final normalizedTopicSearch = _topicSearch?.trim().toLowerCase();
              final filteredTopics =
                  (normalizedTopicSearch == null ||
                      normalizedTopicSearch.isEmpty)
                  ? topics
                  : topics
                        .where(
                          (topic) => topic.topicTitle.toLowerCase().contains(
                            normalizedTopicSearch,
                          ),
                        )
                        .toList();

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                    child: Row(
                      children: [
                        Text(
                          isTamil ? 'தலைப்புகள்' : 'Topics',
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(width: 8),
                        if (_topicSlug != null)
                          ActionChip(
                            key: const ValueKey('clear_topic_chip'),
                            avatar: const Icon(Icons.close, size: 16),
                            label: Text(isTamil ? 'நீக்கு' : 'Clear'),
                            onPressed: () {
                              setState(() => _topicSlug = null);
                            },
                          ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            _showAllTopicsDialog(context, topics, isTamil, cs);
                          },
                          child: Text(
                            isTamil ? 'அனைத்து தலைப்புகள்' : 'Show all topics',
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                          ),
                          hintText: 'search topic',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (value) {
                          setState(() {
                            _topicSearch = value.trim().isEmpty ? null : value;
                          });
                        },
                      ),
                    ),
                  ),
                  if (filteredTopics.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 2, 12, 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          isTamil
                              ? 'தலைப்புகள் கிடைக்கவில்லை'
                              : 'No matching topics',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    )
                  else
                    SizedBox(
                      height: 48,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: filteredTopics.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final topic = filteredTopics[index];
                          final selected = _topicSlug == topic.topicSlug;

                          return Material(
                            key: ValueKey('list_topic_${topic.topicSlug}'),
                            color: selected
                                ? cs.secondaryContainer
                                : cs.surfaceContainerHighest.withValues(
                                    alpha: 0.45,
                                  ),
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                setState(() {
                                  _topicSlug = selected
                                      ? null
                                      : topic.topicSlug;
                                });
                              },
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 220,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  child: Text(
                                    topic.topicTitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? cs.onSecondaryContainer
                                          : cs.onSurface,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: SizedBox(
                height: 48,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
            ),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: TextField(
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: isTamil
                    ? 'கேள்விகளை தேடுங்கள்…'
                    : 'Search questions…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
                suffixIconConstraints: const BoxConstraints(
                  minHeight: 34,
                  minWidth: 110,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: TextButton(
                    onPressed: _openAdvancedSearch,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 30),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      isTamil ? 'மேம்பட்ட தேடல்' : 'Advanced search',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _search = value.trim().isEmpty ? null : value;
                });
              },
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: questionsAsync.when(
              data: (questions) {
                if (questions.isEmpty) {
                  return Center(
                    child: Text(
                      isTamil
                          ? 'கேள்விகள் ஏதும் இல்லை.'
                          : 'No questions available.',
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: questions.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final q = questions[index];
                    final questionNumber = q.number ?? (index + 1);
                    final category = q.category;

                    return Card(
                      elevation: 0.7,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          context.push(
                            '/cod/detail/${q.id}?lang=${widget.lang}',
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: cs.primaryContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  'Q.$questionNumber',
                                  style: TextStyle(
                                    color: cs.onPrimaryContainer,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _listQuestionTitle(q),
                                      style: theme.textTheme.titleSmall,
                                    ),
                                    if (category != null &&
                                        category.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: cs.secondaryContainer,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            _categoryLabel(category, isTamil),
                                            style: TextStyle(
                                              color: cs.onSecondaryContainer,
                                              fontWeight: FontWeight.w600,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Failed to load questions: $err',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
