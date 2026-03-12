import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/reader_provider.dart';
import '../providers/typography_provider.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';

class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const ReaderSettingsSheet(),
    );
  }

  @override
  ConsumerState<ReaderSettingsSheet> createState() =>
      _ReaderSettingsSheetState();
}

class _ReaderSettingsSheetState extends ConsumerState<ReaderSettingsSheet> {
  @override
  Widget build(BuildContext context) {
    final typography = ref.watch(typographyProvider);
    final themeSettings = ref.watch(themeProvider);
    final readerState = ref.watch(readerProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Reader Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 24),

          Text('Text Size', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () {
                  final newSize = (typography.fontSize - 1).clamp(12.0, 36.0);
                  ref
                      .read(typographyProvider.notifier)
                      .updateFontSize(newSize);
                },
              ),
              Expanded(
                child: Slider(
                  value: typography.fontSize,
                  min: 12.0,
                  max: 36.0,
                  divisions: 12,
                  onChanged: (val) =>
                      ref.read(typographyProvider.notifier).updateFontSize(val),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final newSize = (typography.fontSize + 1).clamp(12.0, 36.0);
                  ref
                      .read(typographyProvider.notifier)
                      .updateFontSize(newSize);
                },
              ),
              const SizedBox(width: 8),
              Text(
                typography.fontSize.toStringAsFixed(0),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),

          const SizedBox(height: 16),
          Text('Line Height', style: Theme.of(context).textTheme.titleMedium),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () {
                  final newHeight =
                      (typography.lineHeight - 0.1).clamp(1.0, 2.5);
                  ref
                      .read(typographyProvider.notifier)
                      .updateLineHeight(newHeight);
                },
              ),
              Expanded(
                child: Slider(
                  value: typography.lineHeight,
                  min: 1.0,
                  max: 2.5,
                  divisions: 15,
                  onChanged: (val) => ref
                      .read(typographyProvider.notifier)
                      .updateLineHeight(val),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () {
                  final newHeight =
                      (typography.lineHeight + 0.1).clamp(1.0, 2.5);
                  ref
                      .read(typographyProvider.notifier)
                      .updateLineHeight(newHeight);
                },
              ),
              const SizedBox(width: 8),
              Text(
                typography.lineHeight.toStringAsFixed(1),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            'Font Family',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _buildFontChip('Default', 'Sora', typography.fontFamily),
              _buildFontChip('Serif', 'Georgia', typography.fontFamily),
              _buildFontChip('Sans Serif', 'Sora', typography.fontFamily),
              _buildFontChip('Monospace', 'RobotoMono', typography.fontFamily),
              _buildFontChip('Cursive', 'Pacifico', typography.fontFamily),
            ],
          ),

          const SizedBox(height: 24),
          const Text(
            'Theme',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildModeSelector(context, themeSettings),

          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Restore Tabs'),
            subtitle: const Text('Restore tabs when navigating back'),
            value: readerState.restoreTabs,
            onChanged: (val) =>
                ref.read(readerProvider.notifier).setRestoreTabs(val),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Fullscreen Mode'),
            subtitle: const Text(
              'Hide top bar and bottom tabs for distraction-free reading',
            ),
            value: typography.isFullscreen,
            onChanged: (_) =>
                ref.read(typographyProvider.notifier).toggleFullscreen(),
          ),
        ],
      ),
    );
  }

  Widget _buildFontChip(
    String label,
    String fontValue,
    String currentFont,
  ) {
    final isSelected = currentFont == fontValue;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(typographyProvider.notifier).updateFontFamily(fontValue);
      },
    );
  }

  Widget _buildModeSelector(
    BuildContext context,
    ThemeSettings settings,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _ModeOption(
            icon: Icons.brightness_auto,
            label: 'System',
            isSelected: settings.mode == ThemeModePreference.system,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.system),
          ),
          const SizedBox(width: 8),
          _ModeOption(
            icon: Icons.light_mode,
            label: 'Light',
            isSelected: settings.mode == ThemeModePreference.light,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.light),
          ),
          const SizedBox(width: 8),
          _ModeOption(
            icon: Icons.dark_mode,
            label: 'Dark',
            isSelected: settings.mode == ThemeModePreference.dark,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.dark),
          ),
          const SizedBox(width: 8),
          _ModeOption(
            icon: Icons.menu_book,
            label: 'Sepia',
            isSelected: settings.mode == ThemeModePreference.sepia,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.sepia),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outline.withOpacity(0.5),
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withOpacity(0.3)
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: isSelected ? FontWeight.bold : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
