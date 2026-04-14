import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/metadata/installed_content_provider.dart';
import 'providers/downloader_provider.dart';
import 'providers/database_discovery_provider.dart';
import 'services/selective_database_importer.dart';

const String kApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'https://api.endtimebride.in',
);

// ─── Main screen ─────────────────────────────────────────────────────────────

class OnboardingScreen extends ConsumerStatefulWidget {
  final bool showImportDirectly;

  const OnboardingScreen({super.key, this.showImportDirectly = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  late bool _showImportDialog = widget.showImportDirectly;

  @override
  Widget build(BuildContext context) {
    final dlState = ref.watch(downloaderProvider);

    // Navigate to Home once import succeeded and content flag is refreshed.
    ref.listen(hasInstalledContentProvider, (_, next) {
      next.whenData((hasContent) {
        if (hasContent && mounted) context.go('/');
      });
    });

    if (_showImportDialog ||
        dlState.isActive ||
        dlState.isComplete ||
        dlState.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Setup Database')),
        body: _ImportDialog(
          state: dlState,
          onDismiss: () {
            ref.read(downloaderProvider.notifier).reset();
            if (widget.showImportDirectly) {
              Navigator.of(context).pop();
            } else {
              setState(() => _showImportDialog = false);
            }
          },
          onImportComplete: () {
            ref.read(hasInstalledContentProvider.notifier).refresh();
          },
          onDownloadFromServer: () async {
            try {
              final dbInfo = await ref
                  .read(databaseDiscoveryProvider)
                  .databaseInfo(kApiBaseUrl, 'bridemessage_db_en-ta');
              if (mounted) {
                ref
                    .read(downloaderProvider.notifier)
                    .startDownload(dbInfo.downloadUrl);
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Failed to fetch download link: $e')),
                );
              }
            }
          },
        ),
      );
    }

    return _MainImportOptions(
      onImportDatabase: () => setState(() => _showImportDialog = true),
      onSkip: () {
        ref.read(hasInstalledContentProvider.notifier).skipForSession();
        context.go('/');
      },
      onDownloadFromServer: () async {
        try {
          final dbInfo = await ref
              .read(databaseDiscoveryProvider)
              .databaseInfo(kApiBaseUrl, 'bridemessage_db_en-ta');
          if (mounted) {
            ref
                .read(downloaderProvider.notifier)
                .startDownload(dbInfo.downloadUrl);
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to fetch download link: $e')),
            );
          }
        }
      },
    );
  }
}

// ─── Main options screen ──────────────────────────────────────────────────────

class _MainImportOptions extends StatelessWidget {
  const _MainImportOptions({
    required this.onImportDatabase,
    required this.onSkip,
    required this.onDownloadFromServer,
  });

  final VoidCallback onImportDatabase;
  final VoidCallback onSkip;
  final VoidCallback onDownloadFromServer;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const Spacer(),
              // Icon
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.cloud_download_outlined,
                  size: 40,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Welcome to\nBride Message',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Import your spiritual databases to access Bible readings and sermon collections.',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 40),

              // Import card
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: cs.outline.withAlpha(50)),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: onImportDatabase,
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.cloud_download_outlined,
                            size: 30,
                            color: cs.primary,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Import / Download Database',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Full bundle: Bible, Sermons, and COD databases',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
                      ],
                    ),
                  ),
                ),
              ),

              const Spacer(),

              // Skip
              TextButton(
                onPressed: onSkip,
                child: Text(
                  'Skip for now',
                  style: TextStyle(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'You can always import your content later from the Settings menu.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.outline,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Import dialog panel ──────────────────────────────────────────────────────

class _ImportDialog extends ConsumerWidget {
  const _ImportDialog({
    required this.state,
    required this.onDismiss,
    required this.onImportComplete,
    required this.onDownloadFromServer,
  });

  final DownloaderState state;
  final VoidCallback onDismiss;
  final VoidCallback onImportComplete;
  final VoidCallback onDownloadFromServer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;

    if (state.isComplete) {
      return _buildSuccess(context, ref, cs);
    }
    if (state.error != null) {
      return _buildError(context, ref, cs);
    }
    if (state.isActive) {
      return _buildProgress(context, cs);
    }

    // Idle: show options
    return _buildOptions(context, ref, cs);
  }

  Widget _buildOptions(BuildContext context, WidgetRef ref, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header card
          Card(
            color: cs.primaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.folder_zip, size: 48, color: cs.primary),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Import All Databases',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Choose server download or select a full ZIP bundle from device',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Download from server
          FilledButton.icon(
            onPressed: onDownloadFromServer,
            icon: const Icon(Icons.cloud_download_outlined),
            label: const Text('Download from Server (~200MB)'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          const SizedBox(height: 12),

          // Import from device
          OutlinedButton.icon(
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['zip'],
                withData: false,
              );
              if (result != null && result.files.single.path != null) {
                ref
                    .read(downloaderProvider.notifier)
                    .importFromZip(result.files.single.path!);
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Import from Device'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 16),

          // File hint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Import file:',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'bridemessage_db_en-ta.zip',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Must include: bible_en_kjv.db, bible_ta_bsi.db, sermons_en.db, sermons_ta.db, cod_english.db, cod_tamil.db',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: 4),
                Text(
                  'Security: ZIP must include signed manifest (manifest.json + manifest.sig/signature.ed25519).',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),

          const Spacer(),
          TextButton(onPressed: onDismiss, child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildProgress(BuildContext context, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 40),
          Icon(Icons.cloud_download_outlined, size: 64, color: cs.primary),
          const SizedBox(height: 24),
          Text(
            state.statusMessage,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(
            value: state.progress > 0 ? state.progress : null,
          ),
          const SizedBox(height: 8),
          if (state.progress > 0)
            Text(
              '${(state.progress * 100).toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          const Spacer(),
          TextButton(onPressed: onDismiss, child: const Text('Background')),
        ],
      ),
    );
  }

  Widget _buildSuccess(BuildContext context, WidgetRef ref, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle, size: 80, color: cs.primary),
          const SizedBox(height: 24),
          Text(
            'Installation Complete!',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: state.report == null
                ? Text(
                    state.statusMessage,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  )
                : _buildImportReport(context, cs, state.report!),
          ),
          const SizedBox(height: 32),
          FilledButton(
            onPressed: onImportComplete,
            style: FilledButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
            child: const Text('Continue to App'),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.warning, size: 80, color: cs.error),
          const SizedBox(height: 24),
          Text(
            'Import Failed',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: cs.error,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.errorContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: state.report == null
                ? Text(
                    state.error!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: cs.onErrorContainer,
                    ),
                    textAlign: TextAlign.center,
                  )
                : _buildImportReport(
                    context,
                    cs,
                    state.report!,
                    errorText: state.error,
                  ),
          ),
          const SizedBox(height: 32),
          OutlinedButton.icon(
            onPressed: () async {
              ref.read(downloaderProvider.notifier).reset();
              final result = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['zip'],
                withData: false,
              );
              if (result != null && result.files.single.path != null) {
                ref
                    .read(downloaderProvider.notifier)
                    .importFromZip(result.files.single.path!);
              }
            },
            icon: const Icon(Icons.folder_open),
            label: const Text('Retry - Import from Device'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () {
              ref.read(downloaderProvider.notifier).reset();
            },
            child: const Text('Back'),
          ),
        ],
      ),
    );
  }

  Widget _buildImportReport(
    BuildContext context,
    ColorScheme cs,
    ImportReport report, {
    String? errorText,
  }) {
    final textTheme = Theme.of(context).textTheme;

    Widget buildSection(String title, List<String> items, Color color) {
      if (items.isEmpty) {
        return const SizedBox.shrink();
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 6),
          ...items.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(line, style: textTheme.bodySmall),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (errorText != null && errorText.isNotEmpty) ...[
          Text(errorText, style: textTheme.bodyMedium),
          const SizedBox(height: 10),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text('Imported: ${report.importedCount}')),
            Chip(label: Text('Failed: ${report.failedCount}')),
            Chip(label: Text('Skipped: ${report.skippedCount}')),
          ],
        ),
        const SizedBox(height: 10),
        buildSection('Imported', report.imported, cs.primary),
        if (report.imported.isNotEmpty) const SizedBox(height: 8),
        buildSection('Failed', report.failed, cs.error),
        if (report.failed.isNotEmpty) const SizedBox(height: 8),
        buildSection('Skipped', report.skipped, cs.onSurfaceVariant),
      ],
    );
  }
}
