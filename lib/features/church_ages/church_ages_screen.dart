import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:messageapp/features/common/widgets/fts_highlight_text.dart';
import 'package:messageapp/features/common/widgets/section_menu_button.dart';
import 'package:messageapp/features/help/widgets/help_button.dart';
import 'package:messageapp/features/settings/widgets/theme_picker_sheet.dart';
import 'package:messageapp/features/database_management/providers/database_status_provider.dart';
import 'package:messageapp/features/onboarding/providers/downloader_provider.dart';
import 'package:messageapp/features/onboarding/services/selective_database_importer.dart';
import 'providers/church_ages_provider.dart';
import 'package:messageapp/core/database/models/church_ages_models.dart';
import 'dart:convert';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);

class ChurchAgesScreen extends ConsumerStatefulWidget {
  final String lang;

  const ChurchAgesScreen({super.key, required this.lang});

  @override
  ConsumerState<ChurchAgesScreen> createState() => _ChurchAgesScreenState();
}

class _ChurchAgesScreenState extends ConsumerState<ChurchAgesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isImporting = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeChurchAgesLangProvider.notifier).setLang(widget.lang);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _pickAndImportDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any, // Allow any for now, but usually .db
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _importStatus = 'Preparing import...';
      });

      final file = File(result.files.single.path!);
      final importer = SelectiveDatabaseImporter();

      final importResult = await importer.importChurchAgesDatabase(
        sourceFile: file,
        languageCode: widget.lang,
        displayName: widget.lang == 'ta'
            ? 'Tamil Church Ages'
            : 'English Church Ages',
        onProgress: (pct, msg) {
          setState(() {
            _importStatus = msg;
          });
        },
      );

      if (importResult.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Database imported successfully!')),
          );
          // Refresh both providers to update UI and trigger reload
          ref.invalidate(localDatabaseExistsProvider(widget.lang));
          ref.invalidate(churchAgesProvider(widget.lang));
        }
      } else {
        if (mounted) {
          _showErrorDialog('Import Failed', importResult.message);
        }
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Error', e.toString());
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(churchAgesProvider(widget.lang));
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    // Check local existence immediately
    final localExistsAsync = ref.watch(
      localDatabaseExistsProvider(widget.lang),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.lang == 'ta' ? 'தமிழ் சபை காலங்கள்' : 'English Church Ages',
        ),
        actions: [
          IconButton(
            tooltip: 'Home',
            icon: const Icon(Icons.home),
            onPressed: () {
              _searchController.clear();
              ref
                  .read(churchAgesProvider(widget.lang).notifier)
                  .onClearSearch();
              context.go('/');
            },
          ),
          IconButton(
            tooltip: 'Theme',
            icon: const Icon(Icons.color_lens),
            onPressed: () => ThemePickerSheet.show(context),
          ),
          const SectionMenuButton(),
          const HelpButton(topicId: 'church_ages'),
        ],
      ),
      body: localExistsAsync.when(
        data: (exists) {
          if (!exists) {
            return _buildMissingDatabaseView();
          }

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: isWide ? 32.0 : 0.0),
              child: Column(
                children: [
                  _buildSearchBar(theme, uiState),
                  Expanded(child: _buildBody(theme, uiState)),
                ],
              ),
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(child: Text(err.toString())),
      ),
    );
  }

  Widget _buildMissingDatabaseView() {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final dlState = ref.watch(downloaderProvider);
    final statusAsync = ref.watch(databaseStatusProvider(kApiBaseUrl));
    final dbId = widget.lang == 'ta' ? 'church_ages_ta' : 'church_ages_en';

    if (_isImporting) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_importStatus),
          ],
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.storage_rounded, size: 64, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              'Database Not Found',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'The ${widget.lang == 'ta' ? 'Tamil' : 'English'} Church Ages database is not installed on this device.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),

            if (dlState.isActive) ...[
              SizedBox(
                width: 300,
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: dlState.progress,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(dlState.statusMessage),
                  ],
                ),
              ),
            ] else if (dlState.isComplete) ...[
              Column(
                children: [
                  Text(
                    'Download Complete!',
                    style: TextStyle(
                      color: cs.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton(
                    onPressed: () {
                      ref.read(downloaderProvider.notifier).reset();
                      ref.invalidate(localDatabaseExistsProvider(widget.lang));
                      ref.invalidate(churchAgesProvider(widget.lang));
                    },
                    child: const Text('Start Reading'),
                  ),
                ],
              ),
            ] else ...[
              // Action Buttons
              Column(
                children: [
                  statusAsync.when(
                    data: (databases) {
                      DatabaseStatusInfo? dbInfo;
                      for (final d in databases) {
                        if (d.available.id == dbId) {
                          dbInfo = d;
                          break;
                        }
                      }

                      return FilledButton.icon(
                        onPressed: dbInfo == null
                            ? null
                            : () {
                                // print('MyLog: Starting download of ${jsonEncode(dbInfo)}');
                                ref
                                    .read(downloaderProvider.notifier)
                                    .startDownload(
                                      dbInfo!.available.downloadUrl,
                                    );
                              },
                        icon: const Icon(Icons.download),
                        label: Text(
                          dbInfo == null
                              ? 'Download Unavailable'
                              : 'Download from Server (${dbInfo.sizeText})',
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(280, 48),
                        ),
                      );
                    },
                    loading: () => FilledButton.icon(
                      onPressed: null,
                      icon: const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      label: const Text('Checking Server...'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(280, 48),
                      ),
                    ),
                    error: (err, _) => FilledButton.icon(
                      onPressed: () =>
                          ref.refresh(databaseStatusProvider(kApiBaseUrl)),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry Server Connection'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(280, 48),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickAndImportDatabase,
                    icon: const Icon(Icons.folder_open),
                    label: const Text('Import from Device (.db)'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(280, 48),
                    ),
                  ),
                  const SizedBox(height: 24),
                  TextButton(
                    onPressed: () => context.push('/manage-databases'),
                    child: const Text('Manage All Databases'),
                  ),
                ],
              ),
            ],

            if (dlState.error != null) ...[
              const SizedBox(height: 24),
              Text(
                dlState.error!,
                style: TextStyle(color: cs.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => ref.read(downloaderProvider.notifier).reset(),
                child: const Text('Retry'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, ChurchAgesUiState state) {
    bool isSearchActive = false;
    bool searchContent = false;
    if (state is ChurchAgesSuccess) {
      isSearchActive = state.isSearchActive;
      searchContent = state.searchContent;
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: searchContent
                  ? 'Search content...'
                  : 'Search titles...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: isSearchActive
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref
                            .read(churchAgesProvider(widget.lang).notifier)
                            .onClearSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              ref
                  .read(churchAgesProvider(widget.lang).notifier)
                  .onSearchQueryChanged(value);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              FilterChip(
                label: const Text('Title'),
                selected: !searchContent,
                onSelected: (val) {
                  if (val && searchContent) {
                    ref
                        .read(churchAgesProvider(widget.lang).notifier)
                        .toggleSearchContent();
                  }
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Content'),
                selected: searchContent,
                onSelected: (val) {
                  if (val && !searchContent) {
                    ref
                        .read(churchAgesProvider(widget.lang).notifier)
                        .toggleSearchContent();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, ChurchAgesUiState state) {
    if (state is ChurchAgesLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (state is ChurchAgesError) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              state.message,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => ref
                  .read(churchAgesProvider(widget.lang).notifier)
                  .onClearSearch(),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    } else if (state is ChurchAgesSuccess) {
      if (!state.isSearchActive) {
        return _buildHierarchicalList(theme, state.hierarchicalTopics);
      }

      final results = state.results;

      if (results.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withValues(
                  alpha: 0.4,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'No results found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        itemCount: results.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final result = results[index];
          final hasSearch = state.isSearchActive;
          final queryNorm = state.query.trim();
          final showHighlights = hasSearch && queryNorm.isNotEmpty;
          final isContentSearch = showHighlights && state.searchContent;
          final hasSnippet = isContentSearch && result.snippet.isNotEmpty;

          final titleStyle = theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          );
          final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 13,
            height: 1.4,
          );

          return ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 8,
            ),
            title: Text.rich(
              TextSpan(
                children: PlainQueryHighlightText.buildHighlightSpans(
                  result.title,
                  !isContentSearch ? queryNorm : null,
                  baseStyle: titleStyle ?? const TextStyle(),
                  highlightBackground: theme.colorScheme.primaryContainer,
                ),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.chapterTitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: Text(
                      result.chapterTitle!.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                if (hasSnippet)
                  Text.rich(
                    TextSpan(
                      children: _buildRichSnippetSpans(
                        result.snippet,
                        subtitleStyle ?? const TextStyle(),
                        theme,
                      ),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  )
                else if (result.chapterTitle != null)
                  Text(
                    result.title,
                    style: subtitleStyle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
            onTap: () {
              final uri = Uri(
                path: '/church-ages-reader',
                queryParameters: {
                  'id': result.topicId.toString(),
                  if (hasSearch) 'q': state.query,
                },
              );
              context.push(uri.toString());
            },
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildHierarchicalList(ThemeData theme, List<ChurchAgesTopic> topics) {
    return ListView.builder(
      itemCount: topics.length,
      itemBuilder: (context, index) {
        return _buildTopicNode(theme, topics[index], 0);
      },
    );
  }

  Widget _buildTopicNode(ThemeData theme, ChurchAgesTopic topic, int depth) {
    final hasChildren = topic.children.isNotEmpty;
    final isChapter = depth == 0;

    if (hasChildren) {
      return Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          tilePadding: EdgeInsets.only(left: 16 + (depth * 16.0), right: 16),
          title: Text(
            topic.title.toUpperCase(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              fontSize: isChapter ? 15 : 14,
              letterSpacing: isChapter ? 0.5 : null,
              color: isChapter
                  ? theme.colorScheme.onSurface
                  : theme.colorScheme.primary,
            ),
          ),
          children: topic.children
              .map((child) => _buildTopicNode(theme, child, depth + 1))
              .toList(),
        ),
      );
    }

    return ListTile(
      contentPadding: EdgeInsets.only(left: 32 + (depth * 16.0), right: 16),
      title: Text(
        topic.title,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 14,
          fontWeight: depth == 0 ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        context.push('/church-ages-reader?id=${topic.id}');
      },
    );
  }

  List<InlineSpan> _buildRichSnippetSpans(
    String snippet,
    TextStyle baseStyle,
    ThemeData theme,
  ) {
    final spans = <InlineSpan>[];
    final parts = snippet.split(RegExp(r'(<b>|</b>)'));
    bool isBold = false;

    for (var part in parts) {
      if (part == '<b>') {
        isBold = true;
        continue;
      } else if (part == '</b>') {
        isBold = false;
        continue;
      }

      if (part.isEmpty) continue;

      spans.add(
        TextSpan(
          text: part,
          style: isBold
              ? baseStyle.copyWith(
                  fontWeight: FontWeight.bold,
                  backgroundColor: theme.colorScheme.primaryContainer
                      .withValues(alpha: 0.5),
                  color: theme.colorScheme.onPrimaryContainer,
                )
              : baseStyle,
        ),
      );
    }

    return spans;
  }
}
