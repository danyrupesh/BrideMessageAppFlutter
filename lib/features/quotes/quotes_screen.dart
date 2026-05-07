import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers/quotes_provider.dart';
import 'models/quote_model.dart';
import '../common/widgets/fts_highlight_text.dart';
import '../help/widgets/help_button.dart';
import '../settings/widgets/theme_picker_sheet.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../onboarding/services/selective_database_importer.dart';
import '../database_management/providers/local_databases_provider.dart';
import 'package:flutter/services.dart';
import '../common/widgets/horizontal_scroll_with_arrows.dart';
import '../common/widgets/section_menu_button.dart';

class QuotesScreen extends ConsumerStatefulWidget {
  const QuotesScreen({super.key});

  @override
  ConsumerState<QuotesScreen> createState() => _QuotesScreenState();
}

class _QuotesScreenState extends ConsumerState<QuotesScreen> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _isImporting = false;
  String _importStatus = '';

  String? _hoveredQuoteId;
  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final uiState = ref.watch(quotesProvider);
    final theme = Theme.of(context);
    final isWide = MediaQuery.sizeOf(context).width >= 700;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBack(context);
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _handleBack(context),
          ),
          title: const Text('English Quotes'),
          actions: [
            IconButton(
              icon: const Text(
                'A-',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              tooltip: 'Decrease font size',
              onPressed: () => ref.read(quotesFontSizeProvider.notifier).adjust(-1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Center(
                child: Text(
                  ref.watch(quotesFontSizeProvider).toStringAsFixed(0),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Text(
                'A+',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              tooltip: 'Increase font size',
              onPressed: () => ref.read(quotesFontSizeProvider.notifier).adjust(1),
            ),
            IconButton(
              icon: const Icon(Icons.home),
              onPressed: () {
                _searchController.clear();
                ref.read(quotesProvider.notifier).onClearSearch();
                context.go('/');
              },
            ),
            IconButton(
              icon: const Icon(Icons.color_lens),
              onPressed: () => ThemePickerSheet.show(context),
            ),
            const HelpButton(topicId: 'quotes'),
            const SectionMenuButton(),
          ],
        ),
        body: SafeArea(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: isWide ? 32.0 : 0.0),
            child: Column(
              children: [
                _buildFiltersAndSearch(theme, uiState),
                Expanded(child: _buildBody(theme, uiState)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _handleBack(BuildContext context) {
    _searchFocusNode.unfocus();
    _searchController.clear();
    ref.read(quotesProvider.notifier).onClearSearch();
    context.pop();
  }

  Widget _buildFiltersAndSearch(ThemeData theme, QuotesUiState state) {
    String? selectedType;
    String? selectedGroup;
    List<String> sourceTypes = [];
    List<String> sourceGroups = [];
    bool isSearchActive = false;

    if (state is QuotesSuccess) {
      selectedType = state.selectedSourceType;
      selectedGroup = state.selectedSourceGroup;
      sourceTypes = state.sourceTypes;
      sourceGroups = state.sourceGroups;
      isSearchActive = state.isSearchActive;
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            decoration: InputDecoration(
              hintText: 'Search quotes...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: isSearchActive
                  ? IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(quotesProvider.notifier).onClearSearch();
                      },
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            onChanged: (value) {
              ref.read(quotesProvider.notifier).onSearchQueryChanged(value);
            },
          ),
          const SizedBox(height: 10),
          // Phase + Group filters
          if (sourceTypes.isNotEmpty)
            HorizontalScrollWithArrows(
              children: [
                FilterChip(
                  label: const Text('All Phases'),
                  selected: selectedType == null,
                  onSelected: (_) {
                    ref.read(quotesProvider.notifier).onSourceTypeChanged(null);
                  },
                ),
                const SizedBox(width: 6),
                ...sourceTypes.map(
                  (t) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(_formatSourceType(t)),
                      selected: selectedType == t,
                      onSelected: (_) {
                        ref
                            .read(quotesProvider.notifier)
                            .onSourceTypeChanged(selectedType == t ? null : t);
                      },
                    ),
                  ),
                ),
              ],
            ),
          if (selectedType != null && sourceGroups.isNotEmpty) ...[
            const SizedBox(height: 6),
            HorizontalScrollWithArrows(
              children: [
                FilterChip(
                  label: const Text('All Groups'),
                  selected: selectedGroup == null,
                  onSelected: (_) {
                    ref
                        .read(quotesProvider.notifier)
                        .onSourceGroupChanged(null);
                  },
                ),
                const SizedBox(width: 6),
                ...sourceGroups.map(
                  (g) => Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(g),
                      selected: selectedGroup == g,
                      onSelected: (_) {
                        ref
                            .read(quotesProvider.notifier)
                            .onSourceGroupChanged(
                              selectedGroup == g ? null : g,
                            );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme, QuotesUiState state) {
    if (state is QuotesLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state is QuotesError) {
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
                color: isFileNotFound
                    ? theme.colorScheme.primary
                    : theme.colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                isFileNotFound
                    ? 'Quotes Database Missing'
                    : 'Error Loading Quotes',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                isFileNotFound
                    ? 'The English quotes database has not been installed yet. You can download it or import a ZIP bundle.'
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
                  onPressed: () => ref.refresh(quotesProvider),
                  child: const Text('Retry'),
                ),
            ],
          ),
        ),
      );
    }
    if (state is QuotesSuccess) {
      final quotes = state.quotes;
      if (quotes.isEmpty) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.format_quote,
                size: 64,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(100),
              ),
              const SizedBox(height: 16),
              Text(
                state.isSearchActive
                    ? 'No quotes found'
                    : 'No quotes available',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }
      return ListView.separated(
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: quotes.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _buildQuoteCard(
          context,
          theme,
          quotes[index],
          state.query,
          state.isSearchActive,
        ),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _buildQuoteCard(
    BuildContext context,
    ThemeData theme,
    QuoteModel quote,
    String query,
    bool isSearchActive,
  ) {
    final quoteFontSize = ref.watch(quotesFontSizeProvider);
    final titleStyle = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      height: 1.5,
      fontSize: quoteFontSize,
    );
    final metaStyle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
      fontSize: (quoteFontSize * 0.88).clamp(11.0, 22.0),
    );

    final showHighlight = isSearchActive && query.isNotEmpty;
    final showCopy = _hoveredQuoteId == quote.id;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredQuoteId = quote.id),
      onExit: (_) => setState(() => _hoveredQuoteId = null),
      child: Stack(
        children: [
          InkWell(
            onTap: () => _showQuoteDetail(context, theme, quote),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: PlainQueryHighlightText.buildHighlightSpans(
                        quote.quotePlain,
                        showHighlight ? query : null,
                        baseStyle: titleStyle ?? const TextStyle(),
                        highlightBackground: theme.colorScheme.primaryContainer,
                      ),
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (quote.referencePlain != null &&
                      quote.referencePlain!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: PlainQueryHighlightText.buildHighlightSpans(
                          'â€” ${quote.referencePlain}',
                          showHighlight ? query : null,
                          baseStyle: metaStyle ?? const TextStyle(),
                          highlightBackground:
                              theme.colorScheme.primaryContainer,
                        ),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      if (quote.sourceGroup != null &&
                          quote.sourceGroup!.isNotEmpty)
                        _TagChip(label: quote.sourceGroup!, theme: theme),
                      if (quote.listTitle != null &&
                          quote.listTitle!.isNotEmpty)
                        _TagChip(label: quote.listTitle!, theme: theme),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: _wrapWindowsCopySemantics(
              AnimatedOpacity(
                opacity: showCopy ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Material(
                  color: Colors.transparent,
                  child: IconButton(
                    tooltip: 'Copy',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: showCopy
                        ? () => _copyEnglishQuote(context, quote)
                        : null,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _wrapWindowsCopySemantics(Widget child) {
    if (!kIsWeb && Platform.isWindows) {
      return ExcludeSemantics(child: child);
    }
    return child;
  }

  String _englishQuoteClipboardText(QuoteModel quote) {
    return [
      quote.quotePlain,
      if (quote.referencePlain != null && quote.referencePlain!.isNotEmpty)
        '— ${quote.referencePlain}',
      if (quote.sourceGroup != null && quote.sourceGroup!.isNotEmpty)
        quote.sourceGroup!,
      if (quote.listTitle != null && quote.listTitle!.isNotEmpty)
        quote.listTitle!,
    ].join('\n');
  }

  Future<void> _copyEnglishQuote(BuildContext context, QuoteModel quote) async {
    await Clipboard.setData(
      ClipboardData(text: _englishQuoteClipboardText(quote)),
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
  }

  void _showQuoteDetail(
    BuildContext context,
    ThemeData theme,
    QuoteModel quote,
  ) {
    final isWide = MediaQuery.sizeOf(context).width >= 700;
    if (isWide) {
      showDialog<void>(
        context: context,
        builder: (ctx) {
          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 760,
                maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.35,
                          ),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      quote.quotePlain,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontStyle: FontStyle.italic,
                        height: 1.7,
                        fontSize: ref.watch(quotesFontSizeProvider),
                      ),
                    ),
                    if (quote.referencePlain != null &&
                        quote.referencePlain!.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        'â€” ${quote.referencePlain}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _InfoChip(
                                icon: Icons.category_outlined,
                                label: _formatSourceType(quote.sourceType),
                                theme: theme,
                              ),
                              if (quote.sourceGroup != null &&
                                  quote.sourceGroup!.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.label_outline,
                                  label: quote.sourceGroup!,
                                  theme: theme,
                                ),
                              if (quote.listTitle != null &&
                                  quote.listTitle!.isNotEmpty)
                                _InfoChip(
                                  icon: Icons.title,
                                  label: quote.listTitle!,
                                  theme: theme,
                                ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Copy',
                          icon: const Icon(Icons.copy_rounded),
                          onPressed: () => _copyEnglishQuote(ctx, quote),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
      return;
    }

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          minChildSize: 0.3,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    quote.quotePlain,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontStyle: FontStyle.italic,
                      height: 1.7,
                      fontSize: ref.watch(quotesFontSizeProvider),
                    ),
                  ),
                  if (quote.referencePlain != null &&
                      quote.referencePlain!.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      '— ${quote.referencePlain}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            _InfoChip(
                              icon: Icons.category_outlined,
                              label: _formatSourceType(quote.sourceType),
                              theme: theme,
                            ),
                            if (quote.sourceGroup != null &&
                                quote.sourceGroup!.isNotEmpty)
                              _InfoChip(
                                icon: Icons.label_outline,
                                label: quote.sourceGroup!,
                                theme: theme,
                              ),
                            if (quote.listTitle != null &&
                                quote.listTitle!.isNotEmpty)
                              _InfoChip(
                                icon: Icons.title,
                                label: quote.listTitle!,
                                theme: theme,
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Copy',
                        icon: const Icon(Icons.copy_rounded),
                        onPressed: () => _copyEnglishQuote(context, quote),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _formatSourceType(String type) {
    return type
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) {
          if (w.isEmpty) return w;
          return '${w[0].toUpperCase()}${w.substring(1)}';
        })
        .join(' ');
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
        final importResult = await importer.importQuotesDatabase(
          sourceFile: file,
          displayName: 'English Quotes',
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
        const SnackBar(content: Text('Quotes imported successfully!')),
      );
      ref.invalidate(quotesProvider);
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

class _TagChip extends StatelessWidget {
  final String label;
  final ThemeData theme;

  const _TagChip({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer.withAlpha(160),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final ThemeData theme;

  const _InfoChip({
    required this.icon,
    required this.label,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: Icon(icon, size: 14, color: theme.colorScheme.primary),
      label: Text(label, style: theme.textTheme.labelSmall),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      labelPadding: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}
