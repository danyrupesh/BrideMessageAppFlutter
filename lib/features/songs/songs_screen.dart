import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../help/widgets/help_button.dart';
import '../common/widgets/section_menu_button.dart';

import '../common/widgets/cards.dart';
import '../common/widgets/chips.dart';
import 'providers/songs_provider.dart';
import 'utils/song_search_utils.dart';
import '../dashboard/module_resume_prefs.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../onboarding/services/selective_database_importer.dart';
import '../database_management/providers/local_databases_provider.dart';

class SongsScreen extends ConsumerStatefulWidget {
  const SongsScreen({super.key});

  @override
  ConsumerState<SongsScreen> createState() => _SongsScreenState();
}

class _SongsScreenState extends ConsumerState<SongsScreen> {
  String _query = '';
  bool _isSearchExpanded = false;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isImporting = false;
  String? _importStatus;

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = ref.watch(songsProvider);
    final notifier = ref.read(songsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_isSearchExpanded) {
              setState(() {
                _isSearchExpanded = false;
                _searchController.clear();
                _query = '';
              });
              notifier.onClearSearch();
            } else {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            }
          },
        ),
        title: _isSearchExpanded
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search songs, lyrics...',
                  border: InputBorder.none,
                ),
                textInputAction: TextInputAction.search,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                  notifier.onSearchQueryChanged(value);
                },
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Only Believe Songs'),
                  Text('1196 hymns', style: theme.textTheme.bodySmall),
                ],
              ),
        actions: _isSearchExpanded
            ? [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchController.clear();
                      setState(() {
                        _query = '';
                      });
                      notifier.onClearSearch();
                    },
                  ),
              ]
            : [
                const HelpButton(topicId: 'songs'),
                IconButton(
                  icon: const Icon(Icons.manage_search),
                  tooltip: 'Advanced Search',
                  onPressed: () => context.push('/search?tab=songs'),
                ),
                IconButton(
                  icon: const Icon(Icons.search),
                  onPressed: () {
                    setState(() {
                      _isSearchExpanded = true;
                      _searchController.text = state is SongsSuccess
                          ? state.query
                          : _query;
                    });
                  },
                ),
                const SectionMenuButton(),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16.0,
              vertical: 8.0,
            ),
            child: Row(
              children: [
                if (!_isSearchExpanded) ...[
                  PillToggleChip(
                    label: 'All',
                    icon: Icons.music_note,
                    selected: state is SongsSuccess && !state.showFavoritesOnly,
                    onTap: () {
                      if (state is SongsSuccess && state.showFavoritesOnly) {
                        notifier.toggleFavoritesFilter();
                      }
                    },
                  ),
                  const SizedBox(width: 8),
                  PillToggleChip(
                    label: 'Favorites',
                    icon: Icons.favorite,
                    selected: state is SongsSuccess && state.showFavoritesOnly,
                    onTap: () {
                      notifier.toggleFavoritesFilter();
                    },
                  ),
                ] else ...[
                  PillToggleChip(
                    label: 'Lyrics',
                    icon: Icons.library_music,
                    selected: state is SongsSuccess
                        ? state.searchLyrics
                        : false,
                    onTap: notifier.toggleSearchLyrics,
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _buildBodyForState(state, notifier, theme)),
        ],
      ),
    );
  }

  Widget _buildBodyForState(
    SongsUiState state,
    SongsNotifier notifier,
    ThemeData theme,
  ) {
    if (state is SongsLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state is SongsError) {
      final isMissingDb = state.message.contains('Database file not found');
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isMissingDb ? Icons.storage_outlined : Icons.error_outline,
                size: 64,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                isMissingDb ? 'English Songs Database Missing' : 'Error Loading Songs',
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isMissingDb 
                  ? 'The English songs database (Only Believe) is not installed.'
                  : state.message,
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isMissingDb) ...[
                if (_isImporting) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  Text(_importStatus ?? 'Importing...', style: theme.textTheme.bodySmall),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => context.push('/database-management'),
                    icon: const Icon(Icons.download),
                    label: const Text('Download / Manage Databases'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickAndImportDatabase,
                    icon: const Icon(Icons.file_open),
                    label: const Text('Import from Device (.db or .zip)'),
                  ),
                ],
              ] else
                FilledButton(
                  onPressed: () => ref.read(songsProvider.notifier).onClearSearch(), // Triggers reload
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }

    final success = state as SongsSuccess;
    if (success.songs.isEmpty) {
      final isSearch = success.isSearchActive;
      final isFavs = success.showFavoritesOnly;
      final message = () {
        if (isSearch) return 'No results for "${success.query}"';
        if (isFavs) return 'No favorite songs yet.';
        return 'No songs found.';
      }();
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final label = () {
      if (success.isSearchActive) {
        final base = success.searchLyrics ? 'lyrics results' : 'results';
        return '${success.songs.length} $base for "${success.query}"';
      }
      return '${success.songs.length} of ${success.totalCount} hymns';
    }();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
          child: Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              final metrics = notification.metrics;
              if (!success.isSearchActive &&
                  success.hasMore &&
                  metrics.pixels >= metrics.maxScrollExtent - 200) {
                notifier.loadMore();
              }
              return false;
            },
            child: ListView.separated(
              controller: _scrollController,
              itemCount: success.songs.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final hymn = success.songs[index];
                final subtitle = success.isSearchActive && success.searchLyrics
                    ? buildSongSearchSubtitle(
                        firstLine: hymn.firstLine,
                        lyrics: hymn.lyrics,
                        query: _query,
                      )
                    : hymn.firstLine;
                return SongListCard(
                  number: hymn.hymnNo,
                  title: hymn.title,
                  subtitle: subtitle,
                  keyBadge: hymn.chord.isEmpty ? null : hymn.chord,
                  isFavorite: hymn.isFavorite,
                  highlightQuery: _isSearchExpanded ? _query : null,
                  onTap: () {
                    unawaited(
                      ModuleResumePrefs.saveLastEnglishHymn(hymn.hymnNo),
                    );
                    context.push('/song-detail', extra: hymn.hymnNo);
                  },
                  onToggleFavorite: () => notifier.toggleFavorite(hymn.hymnNo),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickAndImportDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db', 'zip'],
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _importStatus = 'Starting import...';
      });

      final file = File(result.files.single.path!);
      final importer = SelectiveDatabaseImporter();
      final isZip = file.path.toLowerCase().endsWith('.zip');

      ImportResult importResult;
      if (isZip) {
        importResult = await importer.importAllFromZip(
          zipPath: file.path,
          onProgress: (progress, message) {
            setState(() => _importStatus = message);
          },
        );
      } else {
        importResult = await importer.importSongsDatabase(
          sourceFile: file,
          languageCode: 'en',
          displayName: 'English Songs',
          onProgress: (progress, message) {
            setState(() => _importStatus = message);
          },
        );
      }

      if (!mounted) return;

      if (importResult.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(importResult.message)),
        );
        ref.invalidate(localDatabaseFilesProvider);
        ref.read(songsProvider.notifier).onClearSearch();
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Import Failed'),
            content: Text(importResult.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
          _importStatus = null;
        });
      }
    }
  }
}
