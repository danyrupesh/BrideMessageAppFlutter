import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/update/update_service.dart';
import 'widgets/theme_picker_sheet.dart';
import '../onboarding/onboarding_screen.dart';
import '../search/providers/search_history_provider.dart';
import 'screens/developer_details_screen.dart';
import 'screens/database_management_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<PackageInfo> _packageInfoFuture;
  bool _isCheckingUpdates = false;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
  }

  Future<void> _checkForUpdates() async {
    if (_isCheckingUpdates) return;
    setState(() => _isCheckingUpdates = true);

    final messenger = ScaffoldMessenger.of(context);
    final service = UpdateService();

    try {
      final appUpdate = await service.checkAppUpdate();
      final dbUpdates = await service.checkDatabaseUpdates();
      if (!mounted) return;

      if (appUpdate == null && dbUpdates.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You are already on the latest version.'),
          ),
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Updates Found'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (appUpdate != null) ...[
                    Text(
                      'App: ${appUpdate.currentVersion} → ${appUpdate.targetVersion}',
                    ),
                    const SizedBox(height: 6),
                    Text(
                      appUpdate.mandatory
                          ? 'App update is mandatory.'
                          : 'App update is optional.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: [
                        FilledButton.tonal(
                          onPressed: () async {
                            final uri = Uri.parse(appUpdate.url);
                            await launchUrl(
                              uri,
                              mode: LaunchMode.externalApplication,
                            );
                          },
                          child: Text(
                            Platform.isAndroid
                                ? 'Open Play Store'
                                : 'Open Download',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                  ],
                  if (dbUpdates.isNotEmpty) ...[
                    Text('Database updates: ${dbUpdates.length} available'),
                    const SizedBox(height: 6),
                    ...dbUpdates.map(
                      (u) => Text(
                        '- ${u.displayName} (v${u.version})${u.mandatory ? ' • mandatory' : ''}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () async {
                        Navigator.of(context).pop();
                        await _applyDatabaseUpdates(service, dbUpdates);
                      },
                      child: const Text('Update Databases Now'),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
            ],
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not check updates: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _isCheckingUpdates = false);
      }
    }
  }

  Future<void> _applyDatabaseUpdates(
    UpdateService service,
    List<DatabaseUpdateInfo> dbUpdates,
  ) async {
    final status = ValueNotifier<String>('Preparing updates...');

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
          ),
        );
      },
    );

    try {
      await service.applyDatabaseUpdates(
        dbUpdates,
        onStatus: (message) => status.value = message,
      );
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Database updates installed successfully.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Database update failed: $e')));
    } finally {
      status.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'General',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('App Theme'),
              subtitle: const Text('Heavenly Blue • Follow system'),
              onTap: () => ThemePickerSheet.show(context),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'Import & Storage',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Import Databases'),
                  subtitle: const Text(
                    'Manage Bible & Sermon databases on device',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            const OnboardingScreen(showImportDirectly: true),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('Manage Databases'),
                  subtitle: const Text(
                    'View installed Bibles & sermons, delete or re-import',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DatabaseManagementScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined),
                  title: const Text('Clear Search History'),
                  subtitle: const Text('Remove all saved searches'),
                  onTap: () {
                    ref.read(searchHistoryProvider.notifier).clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Search history cleared')),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'About',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                // ── Expandable App Info ──
                FutureBuilder<PackageInfo>(
                  future: _packageInfoFuture,
                  builder: (context, snapshot) {
                    final packageInfo = snapshot.data;
                    return ExpansionTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('App Info'),
                      subtitle: Text(
                        'Version ${packageInfo?.version ?? 'Loading'} • ${packageInfo?.packageName ?? ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onExpansionChanged: (expanded) {
                        // State management for expansion animation
                      },
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _AppInfoRow(
                                label: 'Version',
                                value: packageInfo?.version ?? 'Loading...',
                              ),
                              const SizedBox(height: 12),
                              _AppInfoRow(
                                label: 'Package',
                                value:
                                    packageInfo?.packageName ??
                                    'com.niflarosh.bride_message_app',
                              ),
                              const SizedBox(height: 12),
                              _AppInfoRow(
                                label: 'Build',
                                value: packageInfo?.buildNumber ?? 'N/A',
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.tonalIcon(
                                  onPressed: _isCheckingUpdates
                                      ? null
                                      : _checkForUpdates,
                                  icon: _isCheckingUpdates
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.system_update_alt),
                                  label: Text(
                                    _isCheckingUpdates
                                        ? 'Checking...'
                                        : 'Check for updates',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const Divider(height: 1),
                // ── Developer & Ministry Details ──
                ListTile(
                  leading: const Icon(Icons.person_outlined),
                  title: const Text('Developer & Ministry Details'),
                  subtitle: const Text('Project guidance & development team'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const DeveloperDetailsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AppInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _AppInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}
