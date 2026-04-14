import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_manager.dart';
import '../../../core/database/metadata/installed_content_provider.dart';
import '../../../core/database/metadata/installed_database_model.dart';
import '../../../core/update/app_restart_helper.dart';
import '../../../core/update/update_service.dart';
import '../../onboarding/onboarding_screen.dart';
import 'database_management_provider.dart';

class DatabaseManagementScreen extends ConsumerStatefulWidget {
  const DatabaseManagementScreen({super.key});

  @override
  ConsumerState<DatabaseManagementScreen> createState() =>
      _DatabaseManagementScreenState();
}

class _DatabaseManagementScreenState
    extends ConsumerState<DatabaseManagementScreen> {
  bool _isCheckingLatestDb = false;
  String? _currentDbVersion;

  @override
  void initState() {
    super.initState();
    _loadCurrentDbVersion();
  }

  Future<void> _loadCurrentDbVersion() async {
    final version = await UpdateService().getCurrentDatabaseVersion();
    if (!mounted) return;
    setState(() => _currentDbVersion = version);
  }

  Future<void> _checkLatestDb() async {
    if (_isCheckingLatestDb) return;
    setState(() => _isCheckingLatestDb = true);

    final messenger = ScaffoldMessenger.of(context);
    final service = UpdateService();

    try {
      final dbUpdates = await service.checkDatabaseUpdates();
      if (!mounted) return;

      if (dbUpdates.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You already have the latest database versions.'),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Database Updates Found'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Available updates: ${dbUpdates.length}'),
                  const SizedBox(height: 8),
                  ...dbUpdates.map(
                    (u) => Text(
                      '- ${u.displayName} (v${u.version})${u.mandatory ? ' • mandatory' : ''}\n  ${(u.updateMessage ?? '').trim().isEmpty ? 'New database version v${u.version} is available.' : u.updateMessage!.trim()}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () async {
                  Navigator.of(context).pop();
                  await _applyDatabaseUpdates(service, dbUpdates);
                },
                child: const Text('Update Now'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not check database updates: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingLatestDb = false);
      }
    }
  }

  Future<void> _applyDatabaseUpdates(
    UpdateService service,
    List<DatabaseUpdateInfo> dbUpdates,
  ) async {
    final status = ValueNotifier<String>('Preparing updates...');
    final cancelToken = CancelToken();
    var cancelledByUser = false;
    var progressDialogOpen = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Updating Databases'),
            content: ValueListenableBuilder<String>(
              valueListenable: status,
              builder: (_, value, __) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const LinearProgressIndicator(),
                    const SizedBox(height: 12),
                    Text(value),
                  ],
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelledByUser = true;
                  progressDialogOpen = false;
                  cancelToken.cancel('Cancelled by user');
                  Navigator.of(context).pop();
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        );
      },
    );

    try {
      await service.applyDatabaseUpdates(
        dbUpdates,
        onStatus: (message) => status.value = message,
        cancelToken: cancelToken,
      );
      if (!mounted) return;
      if (progressDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await ref.read(hasInstalledContentProvider.notifier).refresh();
      await ref.read(installedDbListProvider.notifier).refreshList();
      await _loadCurrentDbVersion();
      await AppRestartHelper.restartAfterDatabaseUpgrade();
      return;
    } catch (e) {
      if (!mounted) return;
      if (progressDialogOpen) {
        Navigator.of(context, rootNavigator: true).pop();
      }

      if (cancelledByUser ||
          (e is DioException && e.type == DioExceptionType.cancel)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database update cancelled.')),
        );
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database update failed: $e')));
    } finally {
      status.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final asyncList = ref.watch(installedDbListProvider);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Manage Databases')),
      body: asyncList.when(
        data: (items) {
          if (items.isEmpty) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ImportHeader(
                    onImport: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) =>
                              const OnboardingScreen(showImportDirectly: true),
                        ),
                      );
                    },
                    onCheckLatestDb: _checkLatestDb,
                    isCheckingLatestDb: _isCheckingLatestDb,
                    currentDbVersion: _currentDbVersion,
                  ),
                  const SizedBox(height: 24),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'No databases installed yet',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Use the button above to import your Bible and sermon databases.',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () =>
                ref.read(installedDbListProvider.notifier).refreshList(),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _ImportHeader(
                  onImport: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const OnboardingScreen(showImportDirectly: true),
                      ),
                    );
                  },
                  onCheckLatestDb: _checkLatestDb,
                  isCheckingLatestDb: _isCheckingLatestDb,
                  currentDbVersion: _currentDbVersion,
                ),
                const SizedBox(height: 16),
                Text(
                  'Installed Databases',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                ...items.map(
                  (db) => _DatabaseTile(
                    db: db,
                    onDeleted: () async {
                      await _deleteDatabase(context, ref, db);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Tip: If you re-import using a newer ZIP file, the app will automatically update metadata and indexes.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, stack) => Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                Text(
                  'Failed to load installed databases.',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  '$err',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () =>
                      ref.read(installedDbListProvider.notifier).refreshList(),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _deleteDatabase(
    BuildContext context,
    WidgetRef ref,
    InstalledDatabase db,
  ) async {
    final cs = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove database?'),
        content: Text(
          'This will remove the local file\n"${db.displayName}" '
          '(${db.language.toUpperCase()}) and clear its metadata.\n\n'
          'You can re-import it later from the import screen.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final dbManager = DatabaseManager();
      final registry = ref.read(installedDbRegistryProvider);

      await dbManager.deleteDatabaseFiles(db.dbFileName);
      await registry.delete(db.type, db.code);

      await ref.read(hasInstalledContentProvider.notifier).refresh();
      await ref.read(installedDbListProvider.notifier).refreshList();

      messenger.showSnackBar(
        SnackBar(content: Text('"${db.displayName}" removed successfully.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Failed to remove database: $e')),
      );
    }
  }
}

class _ImportHeader extends StatelessWidget {
  const _ImportHeader({
    required this.onImport,
    required this.onCheckLatestDb,
    required this.isCheckingLatestDb,
    required this.currentDbVersion,
  });

  final VoidCallback onImport;
  final VoidCallback onCheckLatestDb;
  final bool isCheckingLatestDb;
  final String? currentDbVersion;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Import / Re-import Databases',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Download all databases from server or import a ZIP file from this device.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            Text(
              'Current DB version: ${currentDbVersion == null ? 'Not available' : 'v$currentDbVersion'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: onImport,
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('Open Import Screen'),
                ),
                FilledButton.tonalIcon(
                  onPressed: isCheckingLatestDb ? null : onCheckLatestDb,
                  icon: isCheckingLatestDb
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    isCheckingLatestDb ? 'Checking...' : 'Check for latest DB',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DatabaseTile extends StatelessWidget {
  const _DatabaseTile({required this.db, required this.onDeleted});

  final InstalledDatabase db;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isBible = db.type == DbType.bible;
    final icon = isBible ? Icons.menu_book_outlined : Icons.library_books;
    final typeLabel = isBible ? 'Bible' : 'Sermons';
    final langLabel = db.language.toUpperCase();

    final fileSizeText = _formatFileSize(db.fileSize);
    final installedDate = DateTime.fromMillisecondsSinceEpoch(db.installedDate);

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cs.primaryContainer,
          foregroundColor: cs.primary,
          child: Icon(icon),
        ),
        title: Text(db.displayName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              '$typeLabel • $langLabel • $fileSizeText',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 2),
            Text(
              'Installed on '
              '${installedDate.day.toString().padLeft(2, '0')}-'
              '${installedDate.month.toString().padLeft(2, '0')}-'
              '${installedDate.year}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (db.isDefault) ...[
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Default for $langLabel',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, color: cs.error),
          onPressed: onDeleted,
        ),
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes <= 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = bytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }
}
