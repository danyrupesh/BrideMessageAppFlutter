import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../dashboard/module_resume_prefs.dart';
import 'providers/tamil_songs_provider.dart';
import 'models/tamil_song_models.dart';
import '../common/widgets/chips.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../help/widgets/help_button.dart';
import '../common/widgets/section_menu_button.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../onboarding/services/selective_database_importer.dart';
import '../onboarding/providers/downloader_provider.dart';
import '../database_management/providers/database_status_provider.dart';
import '../database_management/providers/local_databases_provider.dart';

class TamilSongsScreen extends ConsumerStatefulWidget {
  const TamilSongsScreen({super.key});

  @override
  ConsumerState<TamilSongsScreen> createState() => _TamilSongsScreenState();
}

class _TamilSongsScreenState extends ConsumerState<TamilSongsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isImporting = false;
  String? _importStatus;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      ref.read(tamilSongsProvider.notifier).loadSongs(refresh: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tamilSongsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('தமிழ் பாடல்கள்'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              _searchController.clear();
              ref.read(tamilSongsProvider.notifier).setQuery('');
              context.go('/');
            },
          ),
          IconButton(
            icon: const Icon(Icons.color_lens),
            onPressed: () => ThemePickerSheet.show(context),
          ),
          const SectionMenuButton(),
          const HelpButton(topicId: 'tamil_songs'),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: Column(
        children: [
          if (state.error == null || state.songs.isNotEmpty)
            _buildTopPanel(state, theme),
          Expanded(
            child: _buildSongList(state, theme),
          ),
        ],
      ),
    );
  }

  Widget _buildTopPanel(TamilSongsState state, ThemeData theme) {
    final artistsAsync = ref.watch(tamilArtistsProvider);
    final tagsAsync = ref.watch(tamilTagsProvider);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withOpacity(0.1))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search Bar
          TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: state.filter.searchContent ? 'Search lyrics...' : 'Search title or song no...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(tamilSongsProvider.notifier).setQuery('');
                      },
                    )
                  : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              filled: true,
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            onChanged: (value) => ref.read(tamilSongsProvider.notifier).setQuery(value),
          ),
          const SizedBox(height: 12),
          
          // Search Mode Toggles
          Row(
            children: [
              _buildModeChip('Title', !state.filter.searchContent, () {
                if (state.filter.searchContent) ref.read(tamilSongsProvider.notifier).toggleSearchContent();
              }),
              const SizedBox(width: 8),
              _buildModeChip('Content', state.filter.searchContent, () {
                if (!state.filter.searchContent) ref.read(tamilSongsProvider.notifier).toggleSearchContent();
              }, icon: Icons.description_outlined),
            ],
          ),
          const SizedBox(height: 12),

          // Sort By Section
          const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
          const SizedBox(height: 4),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildSortChip('A-Z', TamilSongSort.nameAz, state),
                _buildSortChip('Song No', TamilSongSort.songNo, state),
                _buildSortChip('Most Viewed', TamilSongSort.mostViewed, state),
                _buildSortChip('Downloaded', TamilSongSort.mostDownloaded, state),
                _buildSortChip('Latest', TamilSongSort.latest, state),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Artist and Tag Dropdowns
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Artist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    artistsAsync.when(
                      data: (artists) => DropdownButtonFormField<int?>(
                        value: state.filter.artistId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Artists', style: TextStyle(fontSize: 13))),
                          ...artists.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name, style: const TextStyle(fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis))),
                        ],
                        onChanged: (val) => ref.read(tamilSongsProvider.notifier).setArtist(val),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error'),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Tag', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    tagsAsync.when(
                      data: (tags) => DropdownButtonFormField<int?>(
                        value: state.filter.tagId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Tags', style: TextStyle(fontSize: 13))),
                          ...tags.map((t) => DropdownMenuItem(value: t.id, child: Text(t.name, style: const TextStyle(fontSize: 13)))),
                        ],
                        onChanged: (val) => ref.read(tamilSongsProvider.notifier).setTag(val),
                      ),
                      loading: () => const LinearProgressIndicator(),
                      error: (_, __) => const Text('Error'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Quick Filters and Clear All
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Quick Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    const SizedBox(height: 4),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _buildFilterChip('PPT only', state.filter.pptOnly, () => ref.read(tamilSongsProvider.notifier).togglePptOnly()),
                          const SizedBox(width: 8),
                          _buildFilterChip('Lyrics only', state.filter.lyricsOnly, () => ref.read(tamilSongsProvider.notifier).toggleLyricsOnly()),
                          const SizedBox(width: 8),
                          _buildFilterChip('Featured', state.filter.featuredOnly, () => ref.read(tamilSongsProvider.notifier).toggleFeaturedOnly()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => ref.read(tamilSongsProvider.notifier).clearFilters(),
                child: const Text('Clear All', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildModeChip(String label, bool selected, VoidCallback onSelected, {IconData? icon}) {
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14), const SizedBox(width: 4)],
          Text(label, style: const TextStyle(fontSize: 13)),
        ],
      ),
      selected: selected,
      onSelected: (_) => onSelected(),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSortChip(String label, TamilSongSort sort, TamilSongsState state) {
    final selected = state.filter.sortBy == sort;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label, style: const TextStyle(fontSize: 12)),
        selected: selected,
        onSelected: (val) { if (val) ref.read(tamilSongsProvider.notifier).setSort(sort); },
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onSelected) {
    return FilterChip(
      label: Text(label, style: const TextStyle(fontSize: 12)),
      selected: selected,
      onSelected: (_) => onSelected(),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildSongList(TamilSongsState state, ThemeData theme) {
    if (state.isLoading && state.songs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.error != null && state.songs.isEmpty) {
      final isMissingDb = state.error!.contains('Database file not found');
      
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
              isMissingDb ? 'தமிழ் பாடல்கள் தரவுத்தளம் இல்லை' : 'Error Loading Songs',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              isMissingDb 
                ? 'The Tamil songs database is not installed on your device.'
                : state.error!,
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
                onPressed: () => ref.read(tamilSongsProvider.notifier).loadSongs(),
                child: const Text('Retry'),
              ),
          ],
        ),
      ),
    );
    }

    if (state.songs.isEmpty) {
      return const Center(child: Text('No songs found.'));
    }

    return ListView.builder(
      controller: _scrollController,
      itemCount: state.songs.length + (state.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == state.songs.length) {
          return const Center(child: Padding(padding: EdgeInsets.all(16.0), child: CircularProgressIndicator()));
        }

        final song = state.songs[index];
        final query = state.filter.query.trim();
        final showHighlights = query.isNotEmpty;
        final titleStyle = const TextStyle(fontWeight: FontWeight.bold, fontSize: 16);
        final subtitleStyle = theme.textTheme.bodySmall;

        return ListTile(
          leading: CircleAvatar(child: Text(song.id.toString())),
          title: Text.rich(
            TextSpan(
              children: PlainQueryHighlightText.buildHighlightSpans(
                song.tamilName ?? song.name,
                showHighlights ? query : null,
                baseStyle: titleStyle,
                highlightBackground: theme.colorScheme.primaryContainer.withOpacity(0.7),
              ),
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (song.artistName != null) Text(song.artistName!, style: subtitleStyle),
              if (song.lyricsPreview != null)
                Text.rich(
                  TextSpan(
                    children: PlainQueryHighlightText.buildHighlightSpans(
                      song.lyricsPreview!,
                      showHighlights && state.filter.searchContent ? query : null,
                      baseStyle: subtitleStyle ?? const TextStyle(),
                      highlightBackground: theme.colorScheme.primaryContainer.withOpacity(0.5),
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
          trailing: Wrap(
            spacing: 4,
            children: [
              if (song.hasPpt) const Icon(Icons.slideshow, size: 16, color: Colors.blue),
              if (song.isFeatured) const Icon(Icons.star, size: 16, color: Colors.orange),
              const Icon(Icons.chevron_right),
            ],
          ),
          onTap: () {
            unawaited(ModuleResumePrefs.saveLastTamilSongId(song.id));
            final uri = Uri(
              path: '/song-detail/tamil',
              queryParameters: {
                'id': song.id.toString(),
                if (query.isNotEmpty) 'q': query,
              },
            );
            context.push(uri.toString());
          },
        );
      },
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
          languageCode: 'ta',
          displayName: 'Tamil Songs',
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
        // Refresh both the status provider and the specific module provider
        ref.invalidate(localDatabaseFilesProvider);
        ref.read(tamilSongsProvider.notifier).loadSongs();
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
