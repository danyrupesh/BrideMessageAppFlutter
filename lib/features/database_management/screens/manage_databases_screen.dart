import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../onboarding/providers/downloader_provider.dart';
import '../../onboarding/services/database_discovery_service.dart';
import '../../onboarding/services/selective_database_importer.dart';
import '../providers/database_status_provider.dart';

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
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusAsync = ref.watch(databaseStatusProvider(kApiBaseUrl));
    final dlState = ref.watch(downloaderProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Databases'),
        elevation: 0,
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
                    ref.refresh(databaseStatusProvider(kApiBaseUrl));
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
        data: (databases) {
          if (databases.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storage, size: 64, color: cs.outline),
                  const SizedBox(height: 16),
                  const Text('No databases available'),
                ],
              ),
            );
          }

          return ListView.builder(
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
              );
            },
          );
        },
      ),
    );
  }

  void _startDownload(String databaseId, String downloadUrl) {
    setState(() => _downloadingDatabaseId = databaseId);
    ref.read(downloaderProvider.notifier).startDownload(downloadUrl);
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
  });

  final DatabaseStatusInfo database;
  final bool isDownloading;
  final bool isDownloadComplete;
  final double? downloadProgress;
  final String? statusMessage;
  final VoidCallback onDownload;

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
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: isDownloading ? null : onDownload,
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
                  SizedBox(
                    width: double.infinity,
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
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
