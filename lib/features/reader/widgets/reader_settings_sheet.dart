import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/typography_provider.dart';
import '../../../core/widgets/responsive_bottom_sheet.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';

class ReaderSettingsSheet extends ConsumerStatefulWidget {
  const ReaderSettingsSheet({super.key});

  static void show(BuildContext context) {
    showResponsiveBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      maxWidth: 600,
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: bottomInset + 16,
      ),
      child: SingleChildScrollView(
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

            Text(
              'Reader typography uses per-pane zoom controls in split view.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 20),
            Text('Line Height', style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    final newHeight = (typography.lineHeight - 0.1).clamp(
                      1.0,
                      2.5,
                    );
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
                    final newHeight = (typography.lineHeight + 0.1).clamp(
                      1.0,
                      2.5,
                    );
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

            const SizedBox(height: 16),
            Text('Title Size', style: Theme.of(context).textTheme.titleMedium),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove),
                  onPressed: () {
                    final newSize = (typography.titleFontSize - 1).clamp(
                      10.0,
                      22.0,
                    );
                    ref
                        .read(typographyProvider.notifier)
                        .updateTitleFontSize(newSize);
                  },
                ),
                Expanded(
                  child: Slider(
                    value: typography.titleFontSize,
                    min: 10.0,
                    max: 22.0,
                    divisions: 12,
                    onChanged: (val) => ref
                        .read(typographyProvider.notifier)
                        .updateTitleFontSize(val),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    final newSize = (typography.titleFontSize + 1).clamp(
                      10.0,
                      22.0,
                    );
                    ref
                        .read(typographyProvider.notifier)
                        .updateTitleFontSize(newSize);
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  typography.titleFontSize.toStringAsFixed(0),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),

            const SizedBox(height: 24),
            Text('Font Family', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _openFontPicker(context, typography),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.outline.withOpacity(0.6),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.font_download_outlined, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _fontLabel(typography),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),
            const Text('Theme', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildModeSelector(context, themeSettings),

            const SizedBox(height: 24),
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
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _fontLabel(TypographySettings typography) {
    return typography.resolvedFontFamily ?? 'System (Default)';
  }

  List<String> _curatedFonts() {
    if (kIsWeb) {
      return const [
        'Arial',
        'Helvetica',
        'Times New Roman',
        'Georgia',
        'Verdana',
        'Tahoma',
        'Trebuchet MS',
        'Courier New',
      ];
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        return const [
          'Segoe UI',
          'Calibri',
          'Cambria',
          'Georgia',
          'Times New Roman',
          'Verdana',
          'Tahoma',
          'Arial',
          'Consolas',
          'Courier New',
        ];
      case TargetPlatform.macOS:
        return const [
          'SF Pro Text',
          'Helvetica Neue',
          'Arial',
          'Georgia',
          'Times New Roman',
          'Menlo',
          'Monaco',
        ];
      case TargetPlatform.linux:
        return const [
          'Ubuntu',
          'Cantarell',
          'DejaVu Sans',
          'Liberation Sans',
          'Noto Sans',
          'Noto Serif',
          'Noto Sans Tamil',
          'Noto Serif Tamil',
          'Monospace',
        ];
      case TargetPlatform.android:
        return const [
          'Roboto',
          'Noto Sans',
          'Noto Serif',
          'Noto Sans Tamil',
          'Noto Serif Tamil',
          'Droid Sans',
          'Droid Serif',
        ];
      case TargetPlatform.iOS:
        return const [
          'SF Pro Text',
          'Helvetica Neue',
          'Arial',
          'Georgia',
          'Times New Roman',
          'Courier New',
        ];
      case TargetPlatform.fuchsia:
        return const ['Roboto', 'Noto Sans', 'Noto Serif'];
    }
  }

  Future<void> _openFontPicker(
    BuildContext context,
    TypographySettings typography,
  ) async {
    const systemLabel = 'System (Default)';
    const customToken = '__custom__';
    final fonts = _curatedFonts();
    final fontSearchController = TextEditingController();

    String? selection;
    try {
      selection = await showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setState) {
            final q = fontSearchController.text.toLowerCase().trim();
            final filtered = fonts
                .where((f) => f.toLowerCase().contains(q))
                .toList();

            return AlertDialog(
              title: const Text('Choose font'),
              content: SizedBox(
                width: 480,
                height: 420,
                child: Column(
                  children: [
                    TextField(
                      controller: fontSearchController,
                      decoration: InputDecoration(
                        hintText: 'Search fonts',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: fontSearchController.text.trim().isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                tooltip: 'Clear',
                                onPressed: () {
                                  fontSearchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView(
                        children: [
                          ListTile(
                            title: const Text(systemLabel),
                            subtitle: const Text('Use device default font'),
                            trailing: typography.resolvedFontFamily == null
                                ? const Icon(Icons.check)
                                : null,
                            onTap: () => Navigator.pop(ctx, systemLabel),
                          ),
                          ListTile(
                            title: const Text('Custom...'),
                            subtitle: const Text(
                              'Enter a system font family name',
                            ),
                            onTap: () => Navigator.pop(ctx, customToken),
                          ),
                          const Divider(),
                          ...filtered.map(
                            (font) => ListTile(
                              title: Text(font),
                              trailing: typography.resolvedFontFamily == font
                                  ? const Icon(Icons.check)
                                  : null,
                              onTap: () => Navigator.pop(ctx, font),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      fontSearchController.dispose();
    }

    if (selection == null) return;

    if (selection == customToken) {
      final custom = await _openCustomFontDialog(context);
      if (custom == null || custom.trim().isEmpty) return;
      ref.read(typographyProvider.notifier).updateFontFamily(custom.trim());
      return;
    }

    if (selection == systemLabel) {
      ref
          .read(typographyProvider.notifier)
          .updateFontFamily(TypographySettings.systemFontFamily);
      return;
    }

    ref.read(typographyProvider.notifier).updateFontFamily(selection);
  }

  Future<String?> _openCustomFontDialog(BuildContext context) async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom font'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Enter system font family name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    return result?.trim();
  }

  Widget _buildModeSelector(BuildContext context, ThemeSettings settings) {
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
          const SizedBox(width: 8),
          _ModeOption(
            icon: Icons.eco,
            label: 'Green',
            isSelected: settings.mode == ThemeModePreference.green,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.green),
          ),
          const SizedBox(width: 8),
          _ModeOption(
            icon: Icons.water_drop,
            label: 'Blue',
            isSelected: settings.mode == ThemeModePreference.blue,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.blue),
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
