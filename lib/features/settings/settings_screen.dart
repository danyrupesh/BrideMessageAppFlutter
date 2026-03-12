import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'widgets/theme_picker_sheet.dart';
import '../onboarding/onboarding_screen.dart';
import '../search/providers/search_history_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: const Text('App Info'),
              subtitle: const Text('Version 1.9 • com.niflarosh.bride_message_app'),
              onTap: () {
                // Could show a simple dialog with more details.
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: const [
                _AboutTile(
                  icon: Icons.favorite_border,
                  title: 'Vision & Sponsorship',
                ),
                Divider(height: 1),
                _AboutTile(
                  icon: Icons.church_outlined,
                  title: 'Spiritual Oversight',
                ),
                Divider(height: 1),
                _AboutTile(
                  icon: Icons.public,
                  title: 'App Website',
                ),
                Divider(height: 1),
                _AboutTile(
                  icon: Icons.code,
                  title: 'Developed By',
                ),
                Divider(height: 1),
                _AboutTile(
                  icon: Icons.group_outlined,
                  title: 'Development Team',
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

class _AboutTile extends StatelessWidget {
  final IconData icon;
  final String title;

  const _AboutTile({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // TODO: Link to detailed content or external URLs.
      },
    );
  }
}

