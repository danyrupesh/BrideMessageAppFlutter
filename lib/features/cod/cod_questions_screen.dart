import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/models/cod_models.dart';
import '../onboarding/onboarding_screen.dart';
import 'providers/cod_provider.dart';
import '../help/widgets/help_button.dart';
import '../common/widgets/section_menu_button.dart';

class CodQuestionsScreen extends ConsumerStatefulWidget {
  final String lang;

  const CodQuestionsScreen({super.key, required this.lang});

  @override
  ConsumerState<CodQuestionsScreen> createState() => _CodQuestionsScreenState();
}

class _CodQuestionsScreenState extends ConsumerState<CodQuestionsScreen> {
  static const int _questionsPageSize = 40;

  late final TextEditingController _questionSearchController;
  late final TextEditingController _topicStripSearchController;
  late final ScrollController _topicsScrollController;

  String? _search;
  String? _topicSearch;
  String? _category;
  String? _topicSlug;
  bool _onlyScriptures = false;
  int _questionVisibleCount = _questionsPageSize;

  @override
  void initState() {
    super.initState();
    _questionSearchController = TextEditingController();
    _topicStripSearchController = TextEditingController();
    _topicsScrollController = ScrollController();
  }

  @override
  void dispose() {
    _questionSearchController.dispose();
    _topicStripSearchController.dispose();
    _topicsScrollController.dispose();
    super.dispose();
  }

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

  void _resetQuestionPagination() {
    _questionVisibleCount = _questionsPageSize;
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
    final dialogTopicSearchController = TextEditingController();
    String? selectedSlug;
    try {
      selectedSlug = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setStateBuilder) {
              final normalizedQuery = dialogTopicSearchController.text
                  .trim()
                  .toLowerCase();
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
                        controller: dialogTopicSearchController,
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
                          suffixIcon:
                              dialogTopicSearchController.text.trim().isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 20),
                                  tooltip: isTamil ? 'அழி' : 'Clear',
                                  onPressed: () {
                                    dialogTopicSearchController.clear();
                                    setStateBuilder(() {});
                                  },
                                )
                              : null,
                        ),
                        onChanged: (_) => setStateBuilder(() {}),
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
                                    if (dialogTopicSearchController.text
                                        .trim()
                                        .isEmpty)
                                      ActionChip(
                                        key: const ValueKey(
                                          'dialog_all_topics',
                                        ),
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
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
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
                                            key: ValueKey(
                                              'dialog_topic_${topic.topicSlug}',
                                            ),
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
                                              borderRadius:
                                                  BorderRadius.circular(12),
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
    } finally {
      dialogTopicSearchController.dispose();
    }

    if (!mounted || selectedSlug == null) return;

    setState(() {
      _topicSlug = selectedSlug == _allTopicsToken ? null : selectedSlug;
      _resetQuestionPagination();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isTamil = widget.lang == 'ta';
    final codDbExistsAsync = ref.watch(codDatabaseExistsProvider(widget.lang));

    final codDbExists = codDbExistsAsync.maybeWhen(
      data: (exists) => exists,
      orElse: () => true,
    );

    if (!codDbExists) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Text(
            isTamil ? 'கேள்விகளும் பதில்களும்' : 'COD – Questions & Answers',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.folder_off_outlined,
                  size: 56,
                  color: theme.colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text(
                  isTamil
                      ? 'COD தரவுத்தளம் இல்லை'
                      : 'COD database not installed',
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isTamil
                      ? 'COD English / COD Tamil தரவுத்தளத்தை இறக்குமதி செய்யவும்.'
                      : 'Please import COD English / COD Tamil database to continue.',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const OnboardingScreen(showImportDirectly: true),
                      ),
                    );
                  },
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: Text(
                    isTamil ? 'தரவுத்தளத்தை இறக்குமதி செய்' : 'Import Database',
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final questionsAsync = _topicSlug == null
        ? ref.watch(
            codQuestionsProvider((
              lang: widget.lang,
              category: _category,
              search: _search,
              onlyWithScriptures: _onlyScriptures ? true : null,
              limit: _questionVisibleCount,
              offset: 0,
            )),
          )
        : ref.watch(
            codQuestionsByTopicProvider((
              lang: widget.lang,
              topicSlug: _topicSlug!,
              category: _category,
              search: _search,
              onlyWithScriptures: _onlyScriptures ? true : null,
              limit: _questionVisibleCount,
              offset: 0,
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
          const SectionMenuButton(),
          const HelpButton(topicId: 'cod'),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.secondary,
                foregroundColor: theme.colorScheme.onSecondary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onPressed: () {
                final uri = Uri(
                  path: '/sermons',
                  queryParameters: {
                    'mode': 'cod',
                    'title': isTamil
                        ? 'COD - கேள்விகளும் பதில்களும்'
                        : 'COD - Question and Answers',
                    'lang': widget.lang,
                  },
                );
                context.push(uri.toString());
              },
              child: Text(
                isTamil ? 'COD செய்திகள்' : 'COD Sermons',
                style: const TextStyle(fontWeight: FontWeight.w600),
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
                    Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _category == null
                              ? cs.primary
                              : Colors.transparent,
                          border: Border.all(
                            color: _category == null
                                ? cs.primary
                                : cs.outlineVariant,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() {
                              _category = null;
                              _resetQuestionPagination();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              isTamil ? 'அனைத்தும்' : 'All',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _category == null
                                    ? Colors.white
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    for (final cat in visibleCategories) ...[
                      Material(
                        key: ValueKey('cat_$cat'),
                        color: Colors.transparent,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _category == cat
                                ? cs.secondary
                                : Colors.transparent,
                            border: Border.all(
                              color: _category == cat
                                  ? cs.secondary
                                  : cs.outlineVariant,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () {
                              setState(() {
                                _category = cat;
                                _resetQuestionPagination();
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 8,
                              ),
                              child: Text(
                                _categoryLabel(cat, isTamil),
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: _category == cat
                                      ? Colors.white
                                      : cs.onSurface,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Material(
                      color: Colors.transparent,
                      child: Container(
                        decoration: BoxDecoration(
                          color: _onlyScriptures
                              ? cs.tertiary
                              : Colors.transparent,
                          border: Border.all(
                            color: _onlyScriptures
                                ? cs.tertiary
                                : cs.outlineVariant,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: InkWell(
                          key: const ValueKey('filter_scriptures'),
                          borderRadius: BorderRadius.circular(20),
                          onTap: () {
                            setState(() {
                              _onlyScriptures = !_onlyScriptures;
                              _resetQuestionPagination();
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            child: Text(
                              isTamil ? 'வேதவாக்கியங்கள்' : 'Scriptures',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: _onlyScriptures
                                    ? Colors.white
                                    : cs.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
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
                              setState(() {
                                _topicSlug = null;
                                _resetQuestionPagination();
                              });
                            },
                          ),
                        const Spacer(),
                        FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: cs.errorContainer,
                            foregroundColor: cs.onErrorContainer,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                          ),
                          onPressed: () {
                            _showAllTopicsDialog(context, topics, isTamil, cs);
                          },
                          child: Text(
                            isTamil ? 'அனைத்து தலைப்புகள்' : 'Show all topics',
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                        controller: _topicStripSearchController,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(
                            minWidth: 34,
                          ),
                          hintText: 'search topic',
                          suffixIcon:
                              _topicStripSearchController.text.trim().isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  tooltip: isTamil ? 'அழி' : 'Clear',
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  onPressed: () {
                                    _topicStripSearchController.clear();
                                    setState(() => _topicSearch = null);
                                  },
                                )
                              : null,
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
                  Builder(
                    builder: (context) {
                      final isWide = MediaQuery.sizeOf(context).width >= 900;
                      return SizedBox(
                        height: isWide ? 64 : 54,
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.arrow_left),
                              tooltip: isTamil ? 'இடது' : 'Scroll left',
                              onPressed: () {
                                final offset =
                                    (_topicsScrollController.offset - 200)
                                        .clamp(
                                          0.0,
                                          _topicsScrollController
                                              .position
                                              .maxScrollExtent,
                                        );
                                _topicsScrollController.animateTo(
                                  offset,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                            Expanded(
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context)
                                    .copyWith(
                                      dragDevices: {
                                        PointerDeviceKind.touch,
                                        PointerDeviceKind.mouse,
                                        PointerDeviceKind.trackpad,
                                      },
                                    ),
                                child: Scrollbar(
                                  controller: _topicsScrollController,
                                  thumbVisibility: true,
                                  child: ListView.separated(
                                    controller: _topicsScrollController,
                                    scrollDirection: Axis.horizontal,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 4,
                                    ),
                                    itemCount: filteredTopics.length,
                                    separatorBuilder: (context, index) =>
                                        const SizedBox(width: 8),
                                    itemBuilder: (context, index) {
                                      final topic = filteredTopics[index];
                                      final selected =
                                          _topicSlug == topic.topicSlug;

                                      return Material(
                                        key: ValueKey(
                                          'list_topic_${topic.topicSlug}',
                                        ),
                                        color: Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            color: selected
                                                ? cs.primaryContainer
                                                : cs.surfaceContainerLowest,
                                            border: Border.all(
                                              color: selected
                                                  ? cs.primary
                                                  : cs.outline,
                                              width: selected ? 3 : 2,
                                            ),
                                          ),
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            onTap: () {
                                              setState(() {
                                                _topicSlug = selected
                                                    ? null
                                                    : topic.topicSlug;
                                                _resetQuestionPagination();
                                              });
                                            },
                                            child: ConstrainedBox(
                                              constraints: BoxConstraints(
                                                maxWidth: isWide ? 280 : 220,
                                              ),
                                              child: Padding(
                                                padding: EdgeInsets.symmetric(
                                                  horizontal: isWide ? 16 : 12,
                                                  vertical: isWide ? 10 : 8,
                                                ),
                                                child: Center(
                                                  child: Text(
                                                    topic.topicTitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontWeight: selected
                                                          ? FontWeight.w700
                                                          : FontWeight.w500,
                                                      color: selected
                                                          ? cs.onPrimaryContainer
                                                          : cs.onSurface,
                                                      fontSize: isWide
                                                          ? (selected ? 16 : 15)
                                                          : (selected
                                                                ? 14
                                                                : 13),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.arrow_right),
                              tooltip: isTamil ? 'வலது' : 'Scroll right',
                              onPressed: () {
                                final maxExtent = _topicsScrollController
                                    .position
                                    .maxScrollExtent;
                                final offset =
                                    (_topicsScrollController.offset + 200)
                                        .clamp(0.0, maxExtent);
                                _topicsScrollController.animateTo(
                                  offset,
                                  duration: const Duration(milliseconds: 300),
                                  curve: Curves.easeOut,
                                );
                              },
                            ),
                          ],
                        ),
                      );
                    },
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
              controller: _questionSearchController,
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
                  minHeight: 40,
                  minWidth: 140,
                ),
                suffixIcon: Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_search != null && _search!.trim().isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          tooltip: isTamil ? 'அழி' : 'Clear',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                          onPressed: () {
                            _questionSearchController.clear();
                            setState(() {
                              _search = null;
                              _resetQuestionPagination();
                            });
                          },
                        ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: cs.tertiaryContainer,
                          foregroundColor: cs.onTertiaryContainer,
                          minimumSize: const Size(0, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onPressed: _openAdvancedSearch,
                        child: Text(
                          isTamil ? 'மேம்பட்ட தேடல்' : 'Advanced search',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              onChanged: (value) {
                setState(() {
                  _search = value.trim().isEmpty ? null : value;
                  _resetQuestionPagination();
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

                final hasMore = questions.length >= _questionVisibleCount;

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: questions.length + (hasMore ? 1 : 0),
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    if (index >= questions.length) {
                      return Center(
                        child: FilledButton.tonal(
                          onPressed: () {
                            setState(() {
                              _questionVisibleCount += _questionsPageSize;
                            });
                          },
                          child: Text(isTamil ? 'மேலும் ஏற்று' : 'Load more'),
                        ),
                      );
                    }

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
