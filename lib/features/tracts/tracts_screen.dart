import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../dashboard/module_resume_prefs.dart';
import 'models/tract_model.dart';
import 'providers/tracts_provider.dart';
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

class TractsScreen extends ConsumerStatefulWidget {
  final String lang;

  const TractsScreen({super.key, required this.lang});

  @override
  ConsumerState<TractsScreen> createState() => _TractsScreenState();
}

class _TractsScreenState extends ConsumerState<TractsScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isImporting = false;
  String _importStatus = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(activeTractLangProvider.notifier).setLang(widget.lang);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(tractsProvider);
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.lang == 'ta' ? 'தமிழ் பிரசுரங்கள்' : 'English Tracts',
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.home),
            onPressed: () {
              _searchController.clear();
              ref.read(tractsProvider.notifier).onClearSearch();
              context.go('/');
            },
          ),
          IconButton(
            icon: const Icon(Icons.color_lens),
            onPressed: () => ThemePickerSheet.show(context),
          ),
          const SectionMenuButton(),
          const HelpButton(topicId: 'tracts'),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: isWide ? 32.0 : 0.0),
          child: Column(
            children: [
              _buildSearchBar(theme, uiState),
              Expanded(child: _buildBody(theme, uiState)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, TractsUiState state) {
    bool isSearchActive = false;
    bool searchContent = false;
    if (state is TractsSuccess) {
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
                        ref.read(tractsProvider.notifier).onClearSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              ref.read(tractsProvider.notifier).onSearchQueryChanged(value);
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
                    ref.read(tractsProvider.notifier).toggleSearchContent();
                  }
                },
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Content'),
                selected: searchContent,
                onSelected: (val) {
                  if (val && !searchContent) {
                    ref.read(tractsProvider.notifier).toggleSearchContent();
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, TractsUiState state) {
    if (state is TractsLoading) {
      return const Center(child: CircularProgressIndicator());
    } else if (state is TractsError) {
      final isFileNotFound = state.message.contains('Database file not found');
      
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isFileNotFound ? Icons.storage_outlined : Icons.error_outline,
                size: 64,
                color: isFileNotFound ? theme.colorScheme.primary : theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                isFileNotFound ? 'Tracts Database Missing' : 'Error Loading Tracts',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isFileNotFound
                    ? 'The ${widget.lang == 'ta' ? 'Tamil' : 'English'} tracts database has not been installed yet.'
                    : state.message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (isFileNotFound) ...[
                if (_isImporting) ...[
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_importStatus, style: theme.textTheme.bodySmall),
                ] else ...[
                  FilledButton.icon(
                    onPressed: () => context.push('/manage-databases'),
                    icon: const Icon(Icons.cloud_download),
                    label: const Text('Download / Manage'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _pickAndImportDatabase,
                    icon: const Icon(Icons.upload_file),
                    label: const Text('Import from Device'),
                  ),
                ],
              ] else
                FilledButton(
                  onPressed: () => ref.refresh(tractsProvider),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    } else if (state is TractsSuccess) {
      final tracts = state.tracts;

      if (tracts.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_off,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
              ),
              const SizedBox(height: 16),
              Text(
                'No tracts found',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }

      return ListView.separated(
        itemCount: tracts.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) {
          final tract = tracts[index];
          final displayTitle = _stripLeadingSerialNumber(tract.title);
          final indexedTitle = '${index + 1}. $displayTitle';
          final hasSearch = state.isSearchActive;
          final queryNorm = state.query.trim();
          final showHighlights = hasSearch && queryNorm.isNotEmpty;
          final showContentSnippet = showHighlights && state.searchContent;

          final subtitleText = _buildSubtitleSnippet(
            tract: tract,
            searchContent: state.searchContent,
            query: queryNorm,
          );
          final titleStyle = theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          );
          final subtitleStyle = theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          );

          return ListTile(
            title: Text.rich(
              TextSpan(
                children: PlainQueryHighlightText.buildHighlightSpans(
                  indexedTitle,
                  showHighlights ? queryNorm : null,
                  baseStyle: titleStyle ?? const TextStyle(),
                  highlightBackground: theme.colorScheme.primaryContainer,
                ),
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: showContentSnippet
                ? Text.rich(
                    TextSpan(
                      children: PlainQueryHighlightText.buildHighlightSpans(
                        subtitleText,
                        queryNorm,
                        baseStyle: subtitleStyle ?? const TextStyle(),
                        highlightBackground: theme.colorScheme.primaryContainer,
                      ),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : null,
            onTap: () async {
              await ModuleResumePrefs.saveLastTract(widget.lang, tract.id);
              final uri = Uri(
                path: '/tract-reader',
                queryParameters: {
                  'id': tract.id,
                  if (hasSearch) 'q': state.query,
                },
              );
              if (context.mounted) context.push(uri.toString());
            },
          );
        },
      );
    }
    return const SizedBox.shrink();
  }

  String _stripLeadingSerialNumber(String title) {
    // Hide list serial prefixes like "1.", "12)", "3 -" from UI title.
    return title.replaceFirst(RegExp(r'^\s*\d+\s*[\.\)\-:]*\s*'), '');
  }

  String _buildSubtitleSnippet({
    required Tract tract,
    required bool searchContent,
    required String query,
  }) {
    if (!searchContent || query.isEmpty) return '';
    final source = tract.content.replaceAll('\n', ' ').trim();
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

  Future<void> _pickAndImportDatabase() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowedExtensions: ['db', 'zip'],
      );

      if (result == null || result.files.single.path == null) return;

      setState(() {
        _isImporting = true;
        _importStatus = 'Preparing import...';
      });

      final filePath = result.files.single.path!;
      final file = File(filePath);
      final importer = SelectiveDatabaseImporter();

      if (filePath.toLowerCase().endsWith('.zip')) {
        setState(() => _importStatus = 'Extracting ZIP bundle...');
        final importResult = await importer.importAllFromZip(
          zipPath: filePath,
          onProgress: (pct, msg) {
            setState(() => _importStatus = msg);
          },
        );
        if (importResult.success) {
          _onImportSuccess();
        } else {
          _showError('Import Failed', importResult.message);
        }
      } else {
        setState(() => _importStatus = 'Validating database...');
        final importResult = await importer.importTractsDatabase(
          sourceFile: file,
          languageCode: widget.lang,
          displayName: widget.lang == 'ta' ? 'Tamil Tracts' : 'English Tracts',
          onProgress: (pct, msg) {
            setState(() => _importStatus = msg);
          },
        );
        if (importResult.success) {
          _onImportSuccess();
        } else {
          _showError('Import Failed', importResult.message);
        }
      }
    } catch (e) {
      _showError('Error', e.toString());
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  void _onImportSuccess() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tracts imported successfully!')),
      );
      ref.invalidate(tractsProvider);
      ref.invalidate(localDatabaseFilesProvider);
    }
  }

  void _showError(String title, String message) {
    if (!mounted) return;
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
}
