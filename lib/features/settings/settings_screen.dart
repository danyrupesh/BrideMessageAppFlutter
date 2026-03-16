import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'widgets/theme_picker_sheet.dart';
import '../onboarding/onboarding_screen.dart';
import '../search/providers/search_history_provider.dart';
import 'screens/developer_details_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late Future<PackageInfo> _packageInfoFuture;

  @override
  void initState() {
    super.initState();
    _packageInfoFuture = PackageInfo.fromPlatform();
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
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
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
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cloud_download_outlined),
                  title: const Text('Import Databases'),
                  subtitle:
                      const Text('Manage Bible & Sermon databases on device'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const OnboardingScreen(
                          showImportDirectly: true,
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.storage),
                  title: const Text('App Storage & Memory'),
                  subtitle: const Text('View storage usage & data breakdown'),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const StorageOverviewScreen(),
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
                    ref
                        .read(searchHistoryProvider.notifier)
                        .clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Search history cleared'),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'About',
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.bold),
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
                                value: packageInfo?.packageName ??
                                    'com.niflarosh.bride_message_app',
                              ),
                              const SizedBox(height: 12),
                              _AppInfoRow(
                                label: 'Build',
                                value: packageInfo?.buildNumber ?? 'N/A',
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

class StorageOverviewScreen extends StatelessWidget {
  const StorageOverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storage Overview'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Total Storage Used',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '737.78 MB',
                    style: theme.textTheme.displaySmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Initial App Size + Downloaded Databases',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: const [
                _StorageTile(
                  label: 'English Sermons',
                  size: '320 MB',
                ),
                Divider(height: 1),
                _StorageTile(
                  label: 'Tamil Sermons',
                  size: '295 MB',
                ),
                Divider(height: 1),
                _StorageTile(
                  label: 'BSI Tamil Bible',
                  size: '60 MB',
                ),
                Divider(height: 1),
                _StorageTile(
                  label: 'KJV Bible',
                  size: '35 MB',
                ),
                Divider(height: 1),
                _StorageTile(
                  label: 'Your Personal Data',
                  size: '24 KB',
                ),
                Divider(height: 1),
                _StorageTile(
                  label: 'App Settings',
                  size: '12 KB',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StorageTile extends StatelessWidget {
  final String label;
  final String size;

  const _StorageTile({
    required this.label,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      trailing: Text(size),
    );
  }
}

class _AppInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _AppInfoRow({
    required this.label,
    required this.value,
  });

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
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
