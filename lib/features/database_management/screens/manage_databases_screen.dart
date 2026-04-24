import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../../core/database/database_manager.dart';
import '../../onboarding/providers/downloader_provider.dart';
import '../../onboarding/services/database_discovery_service.dart';
import '../../onboarding/services/selective_database_importer.dart';
import '../providers/database_status_provider.dart';
import '../providers/local_databases_provider.dart';
import '../../church_ages/providers/church_ages_provider.dart';
import '../../church_ages/providers/church_ages_reader_provider.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);

class ManageDatabasesScreen extends ConsumerStatefulWidget {
  const ManageDatabasesScreen({super.key});

  @override
  ConsumerState<ManageDatabasesScreen> createState() =>
      _ManageDatabasesScreenState();
}

class _ManageDatabasesScreenState extends ConsumerState<ManageDatabasesScreen> {
  /// Tracks which database is currently being downloaded/imported
  String? _downloadingDatabaseId;

  @override
  void initState() {
    super.initState();
    // Re-check databases every time we enter this screen
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(databaseStatusProvider(kApiBaseUrl));
      ref.invalidate(localDatabaseFilesProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusAsync = ref.watch(databaseStatusProvider(kApiBaseUrl));
    final dlState = ref.watch(downloaderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Databases'),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(databaseStatusProvider(kApiBaseUrl));
              ref.invalidate(localDatabaseFilesProvider);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'clear_all') {
                _clearAllDatabases();
              }
            },
            itemBuilder: (BuildContext context) => [
              const PopupMenuItem(
                value: 'clear_all',
                child: Row(
                  children: [
                    Icon(Icons.delete_sweep_outlined, size: 20),
                    SizedBox(width: 12),
                    Text('Clear All Databases'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: statusAsync.when(
        loading: () => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: cs.primary),
              const SizedBox(height: 16),
              const Text('Discovering available databases...'),
            ],
          ),
        ),
        error: (err, st) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 64, color: cs.error),
                const SizedBox(height: 16),
                Text(
                  'Failed to load databases',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 8),
                Text(
                  err.toString(),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () {
                    ref.invalidate(databaseStatusProvider(kApiBaseUrl));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (databases) {
          final isOffline = databases.every((d) => d.available.version == '?' || d.available.version == 'Local');
          
          if (databases.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storage, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  const Text('No databases found on device'),
                  if (isOffline) ...[
                    const SizedBox(height: 8),
                    const Text('Server unreachable. Please check your connection.'),
                  ],
                ],
              ),
            );
          }

          return Column(
            children: [
              if (isOffline)
                Container(
                  width: double.infinity,
                  color: cs.errorContainer.withAlpha(50),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off, size: 16, color: cs.error),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Server unreachable. Showing local databases only.',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: cs.error),
                        ),
                      ),
                      TextButton(
                        onPressed: () => ref.refresh(databaseStatusProvider(kApiBaseUrl)),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: databases.length,
                  itemBuilder: (context, index) {
                    final db = databases[index];
                    final isDownloading = _downloadingDatabaseId == db.available.id;
                    final isInProgress = dlState.isActive && isDownloading;
                    final isDownloadComplete = dlState.isComplete && isDownloading;

                    return _DatabaseCard(
                      database: db,
                      isDownloading: isInProgress,
                      isDownloadComplete: isDownloadComplete,
                      downloadProgress: isInProgress ? dlState.progress : null,
                      statusMessage: isInProgress ? dlState.statusMessage : null,
                      onDownload: () => _startDownload(db.available.id, db.available.downloadUrl),
                      onDelete: () => _deleteSingleDatabase(db.available.id, db.available.displayName),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _startDownload(String databaseId, String downloadUrl) {
    setState(() => _downloadingDatabaseId = databaseId);
    ref.read(downloaderProvider.notifier).startDownload(downloadUrl);
  }

  Future<void> _deleteSingleDatabase(String databaseId, String displayName) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete $displayName?'),
        content: const Text(
          'This will remove the installed database from your device. You can reinstall it later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final dbManager = DatabaseManager();
        await dbManager.deleteDatabase(databaseId);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$displayName deleted')),
          );
          // Refresh all relevant providers
          ref.invalidate(localDatabaseFilesProvider);
          ref.invalidate(databaseStatusProvider(kApiBaseUrl));
          ref.invalidate(localDatabaseExistsProvider);
          ref.invalidate(churchAgesProvider);
          ref.invalidate(churchAgesReaderProvider);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting database: $e')),
          );
        }
      }
    }
  }

  Future<void> _clearAllDatabases() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear All Databases?'),
        content: const Text(
          'This will remove all installed databases from your device. You can reinstall them later from the server.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        final dbManager = DatabaseManager();
        final databaseIds = [
          'bridemessage_db_en-ta',
          'bridemessage_db_en',
          'bridemessage_db_ta',
          'bible_en',
          'bible_ta',
          'sermons_en',
          'sermons_ta',
          'tracts_en',
          'tracts_ta',
          'cod_en',
          'cod_ta',
          'church_ages_en',
          'church_ages_ta',
        ];

        for (final id in databaseIds) {
          try {
            await dbManager.deleteDatabase(id);
          } catch (e) {
            debugPrint('Error deleting $id: $e');
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('All databases cleared')),
          );
          // Refresh all relevant providers
          ref.invalidate(localDatabaseFilesProvider);
          ref.invalidate(databaseStatusProvider(kApiBaseUrl));
          ref.invalidate(localDatabaseExistsProvider);
          ref.invalidate(churchAgesProvider);
          ref.invalidate(churchAgesReaderProvider);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error clearing databases: $e')),
          );
        }
      }
    }
  }
}

class _DatabaseCard extends ConsumerWidget {
  const _DatabaseCard({
    required this.database,
    required this.isDownloading,
    required this.isDownloadComplete,
    this.downloadProgress,
    this.statusMessage,
    required this.onDownload,
    required this.onDelete,
  });

  final DatabaseStatusInfo database;
  final bool isDownloading;
  final bool isDownloadComplete;
  final double? downloadProgress;
  final String? statusMessage;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final db = database.available;

    // Determine status color
    Color statusColor;
    IconData statusIcon;
    
    if (database.isInstalled && database.hasUpdate) {
      statusColor = cs.errorContainer;
      statusIcon = Icons.update;
    } else if (database.isInstalled) {
      statusColor = cs.tertiaryContainer;
      statusIcon = Icons.check_circle;
    } else {
      statusColor = cs.surfaceVariant;
      statusIcon = Icons.cloud_download_outlined;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outline.withAlpha(30)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                // Header row: Icon, name, status badge
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: statusColor,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(statusIcon, color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            db.displayName,
                            style: Theme.of(context).textTheme.titleMedium,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            database.statusText,
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    Chip(
                      label: Text('v${db.version}'),
                      side: BorderSide(color: cs.outline.withAlpha(50)),
                      backgroundColor: Colors.transparent,
                      labelStyle: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Details row: size, installed version
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Size',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            database.sizeText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (database.isInstalled)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Installed',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: cs.onSurfaceVariant),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'v${database.installedVersion}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                
                // Progress bar (if downloading)
                if (isDownloading && downloadProgress != null) ...[
                  const SizedBox(height: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: downloadProgress!.clamp(0.0, 1.0),
                          minHeight: 6,
                          backgroundColor: cs.surfaceVariant,
                          valueColor: AlwaysStoppedAnimation(cs.primary),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        statusMessage ?? 'Downloading...',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ] else if (isDownloadComplete) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.check_circle, color: cs.primary, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Installation complete',
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: cs.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ] else if (!isDownloading) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonal(
                          onPressed: (database.isInstalled && !database.hasUpdate)
                              ? null
                              : onDownload,
                          child: Text(
                            database.isInstalled
                                ? (database.hasUpdate ? 'Update' : 'Already updated')
                                : 'Install',
                          ),
                        ),
                      ),
                      if (database.isInstalled) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: onDelete,
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Delete'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: cs.error,
                            side: BorderSide(color: cs.error.withAlpha(128)),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      );
  }
}
