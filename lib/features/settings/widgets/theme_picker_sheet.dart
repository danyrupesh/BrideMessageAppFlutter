import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/theme_provider.dart';

class ThemePickerSheet extends ConsumerWidget {
  const ThemePickerSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const ThemePickerSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeProvider);

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
                'Appearance',
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
          const Text(
            'Theme Mode',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildModeSelector(context, ref, themeSettings),
          const SizedBox(height: 24),
          const Text(
            'Primary Color',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildColorSelector(context, ref, themeSettings),
        ],
      ),
    );
  }

  Widget _buildModeSelector(
    BuildContext context,
    WidgetRef ref,
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
          const SizedBox(width: 12),
          _ModeOption(
            icon: Icons.light_mode,
            label: 'Light',
            isSelected: settings.mode == ThemeModePreference.light,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.light),
          ),
          const SizedBox(width: 12),
          _ModeOption(
            icon: Icons.dark_mode,
            label: 'Dark',
            isSelected: settings.mode == ThemeModePreference.dark,
            onTap: () => ref
                .read(themeProvider.notifier)
                .updateMode(ThemeModePreference.dark),
          ),
          const SizedBox(width: 12),
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

  Widget _buildColorSelector(
    BuildContext context,
    WidgetRef ref,
    ThemeSettings settings,
  ) {
    final defaultColors = [
      Colors.deepPurple,
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.red,
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        ...defaultColors.map(
          (color) => _ColorOption(
            color: color,
            isSelected: settings.primaryColor.value == color.value,
            onTap: () =>
                ref.read(themeProvider.notifier).updatePrimaryColor(color),
          ),
        ),
        _CustomColorOption(
          currentColor: settings.primaryColor,
          onColorPicked: (color) {
            ref.read(themeProvider.notifier).updatePrimaryColor(color);
          },
        ),
      ],
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
            const SizedBox(height: 8),
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

class _ColorOption extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorOption({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).colorScheme.onSurface
                : Colors.transparent,
            width: 3,
          ),
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white) : null,
      ),
    );
  }
}

class _CustomColorOption extends StatelessWidget {
  final Color currentColor;
  final Function(Color) onColorPicked;

  const _CustomColorOption({
    required this.currentColor,
    required this.onColorPicked,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Color pickerColor = currentColor;
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Pick a color'),
            content: SingleChildScrollView(
              child: ColorPicker(
                pickerColor: pickerColor,
                onColorChanged: (color) {
                  pickerColor = color;
                },
                enableAlpha: false,
                labelTypes: const [], // simplify UI
              ),
            ),
            actions: [
              TextButton(
                child: const Text('Cancel'),
                onPressed: () => Navigator.of(context).pop(),
              ),
              ElevatedButton(
                child: const Text('Set'),
                onPressed: () {
                  onColorPicked(pickerColor);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        );
      },
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: Theme.of(context).colorScheme.outline),
          gradient: const SweepGradient(
            colors: [
              Colors.red,
              Colors.yellow,
              Colors.green,
              Colors.cyan,
              Colors.blue,
              Colors.purple,
              Colors.red,
            ],
          ),
        ),
        child: const Icon(
          Icons.colorize,
          color: Colors.white,
          shadows: [Shadow(blurRadius: 2, color: Colors.black54)],
        ),
      ),
    );
  }
}
