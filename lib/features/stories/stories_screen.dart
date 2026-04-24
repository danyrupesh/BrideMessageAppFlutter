import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/database/database_manager.dart';
import '../../core/database/models/story_models.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../help/widgets/help_button.dart';
import '../common/widgets/section_menu_button.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import 'models/story_model.dart';
import 'providers/stories_provider.dart';

class StoriesScreen extends ConsumerStatefulWidget {
  const StoriesScreen({super.key, required this.lang});

  final String lang;

  @override
  ConsumerState<StoriesScreen> createState() => _StoriesScreenState();
}

class _StoriesScreenState extends ConsumerState<StoriesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _searchContent = false;
  StorySectionType _section = StorySectionType.wmbStories;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final screenTitle = widget.lang == 'ta'
        ? 'தமிழ் கதைகள்'
        : 'English Stories';

    final storiesAsync = ref.watch(
      storiesProvider(
        StoriesQuery(
          lang: widget.lang,
          section: _section,
          searchText: _query,
          searchContent: _searchContent,
        ),
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(screenTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              _searchController.clear();
              setState(() {
                _query = '';
                _searchContent = false;
              });
              context.go('/');
            },
          ),
          IconButton(
            icon: const Icon(Icons.color_lens),
            onPressed: () => ThemePickerSheet.show(context),
          ),
          const SectionMenuButton(),
          const HelpButton(topicId: 'stories'),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: StorySectionType.values.map((section) {
                final selected = section == _section;

                String labelText = section.label;
                if (selected && storiesAsync is AsyncData) {
                  labelText += ' (${storiesAsync.value!.length})';
                }

                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(labelText),
                    selected: selected,
                    onSelected: (bool isSelected) {
                      if (isSelected) {
                        setState(() {
                          _section = section;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: _searchContent
                        ? 'Search content...'
                        : 'Search titles...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _query = '');
                            },
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                  ),
                  onChanged: (value) => setState(() => _query = value.trim()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Title'),
                      selected: !_searchContent,
                      onSelected: (val) {
                        if (val && _searchContent) {
                          setState(() => _searchContent = false);
                        }
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('Content'),
                      selected: _searchContent,
                      onSelected: (val) {
                        if (val && !_searchContent) {
                          setState(() => _searchContent = true);
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: storiesAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const Center(child: Text('No stories found.'));
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_query.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16.0,
                          vertical: 8.0,
                        ),
                        child: Text(
                          '${items.length} ${_searchContent ? 'occurrences' : 'stories'} found',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final displayTitle = item.title;
                          final indexedTitle = '${index + 1}. $displayTitle';
                          final hasSearch = _query.isNotEmpty;
                          final queryNorm = _query;
                          final showHighlights =
                              hasSearch && queryNorm.isNotEmpty;
                          final showContentSnippet =
                              showHighlights && _searchContent;

                          final subtitleText = _buildSubtitleSnippet(
                            story: item,
                            searchContent: _searchContent,
                            query: queryNorm,
                          );
                          final titleStyle = theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700);
                          final subtitleStyle = theme.textTheme.bodyMedium
                              ?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              );

                          return ListTile(
                            title: Text.rich(
                              TextSpan(
                                children:
                                    PlainQueryHighlightText.buildHighlightSpans(
                                      indexedTitle,
                                      showHighlights ? queryNorm : null,
                                      baseStyle:
                                          titleStyle ?? const TextStyle(),
                                      highlightBackground:
                                          theme.colorScheme.primaryContainer,
                                    ),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: showContentSnippet
                                ? Text.rich(
                                    TextSpan(
                                      children:
                                          PlainQueryHighlightText.buildHighlightSpans(
                                            subtitleText,
                                            queryNorm,
                                            baseStyle:
                                                subtitleStyle ??
                                                const TextStyle(),
                                            highlightBackground: theme
                                                .colorScheme
                                                .primaryContainer,
                                          ),
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                            onTap: () {
                              final hasSearch = _query.isNotEmpty;
                              final uri = Uri(
                                path: '/story-reader',
                                queryParameters: {
                                  'id': item.id,
                                  'lang': widget.lang,
                                  'section': _section.name,
                                  if (hasSearch) 'q': _query,
                                },
                              );
                              context.push(uri.toString());
                            },
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
              loading: () => Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 20),
                    FutureBuilder<String>(
                      future: DatabaseManager().getDatabasePath(
                        'stories_${widget.lang}.db',
                      ),
                      builder: (ctx, snap) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 40),
                          child: Text(
                            'Loading stories_${widget.lang}.db\nChecking path: ${snap.data ?? "..."}',
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              error: (error, _) {
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          size: 48,
                          color: cs.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Database Error',
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: cs.error,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          error.toString(),
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitleSnippet({
    required Story story,
    required bool searchContent,
    required String query,
  }) {
    if (!searchContent || query.isEmpty) return '';

    // Strip HTML tags for clean snippet text
    final cleanContent = story.content.replaceAll(
      RegExp(r'<[^>]*>|&[^;]+;'),
      ' ',
    );
    final source = cleanContent
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (source.isEmpty) return '';

    final idx = source.toLowerCase().indexOf(query.toLowerCase());
    if (idx < 0) {
      final previewLen = source.length > 120 ? 120 : source.length;
      return '${source.substring(0, previewLen)}${source.length > previewLen ? '...' : ''}';
    }

    final start = (idx - 40).clamp(0, source.length);
    final end = (idx + query.length + 80).clamp(0, source.length);
    final prefix = start > 0 ? '...' : '';
    final suffix = end < source.length ? '...' : '';
    return '$prefix${source.substring(start, end)}$suffix';
  }
}
