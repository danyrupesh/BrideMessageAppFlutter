import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/responsive_bottom_sheet.dart';
import '../providers/song_install_provider.dart';

class SongImportSheet extends ConsumerWidget {
  const SongImportSheet({
    super.key,
    required this.onDismiss,
  });

  final VoidCallback onDismiss;

  static Future<bool?> show(BuildContext context) {
    return showResponsiveBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => const SongImportSheet(onDismiss: nullDismiss),
    );
  }

  // Small helper so we can pass a non-null callback into the const constructor.
  static void nullDismiss() {}

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(songInstallProvider);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    Future<void> pickLocalZip() async {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: false,
      );
      final path = result?.files.single.path;
      if (path != null) {
        await ref.read(songInstallProvider.notifier).onImportFromZip(path);
      }
    }

    Widget buildIdleOrConnecting() {
      final isConnecting = state is SongInstallConnecting;
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Only Believe Songs',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  ref.read(songInstallProvider.notifier).reset();
                  Navigator.of(context).pop(false);
                  onDismiss();
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Install the Only Believe hymns database to access all songs.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: isConnecting
                ? null
                : () => ref
                    .read(songInstallProvider.notifier)
                    .onDownloadFromServer(),
            icon: isConnecting
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(cs.onPrimaryContainer),
                    ),
                  )
                : const Icon(Icons.cloud_download),
            label: Text(
              isConnecting ? 'Connecting…' : 'Download from Server',
            ),
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: isConnecting ? null : pickLocalZip,
            icon: const Icon(Icons.folder_open),
            label: const Text('Import from Device (ZIP)'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              ref.read(songInstallProvider.notifier).reset();
              Navigator.of(context).pop(false);
              onDismiss();
            },
            child: const Text('Skip for now'),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    Widget buildDownloading(SongInstallDownloading s) {
      final pct = (s.progress.clamp(0, 1) * 100).toInt();
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Downloading database…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          LinearProgressIndicator(value: s.progress),
          const SizedBox(height: 8),
          Text('$pct% completed'),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              ref.read(songInstallProvider.notifier).reset();
              Navigator.of(context).pop(false);
              onDismiss();
            },
            child: const Text('Cancel'),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    Widget buildExtracting() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Installing database…',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Center(
            child: CircularProgressIndicator(),
          ),
          const SizedBox(height: 16),
          Text(
            'This may take a few moments. Please keep the app open.',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    Widget buildSuccess() {
      // Pop with success immediately; the gate screen will continue to Songs.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pop(true);
        onDismiss();
      });

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 8),
          Icon(Icons.check_circle, size: 48, color: cs.primary),
          const SizedBox(height: 12),
          const Text(
            'Ready!',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Only Believe Songs database installed.',
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
        ],
      );
    }

    Widget buildError(SongInstallError error) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline, color: cs.error),
              const SizedBox(width: 8),
              const Text(
                'Something went wrong',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            error.message,
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    ref.read(songInstallProvider.notifier).reset();
                    Navigator.of(context).pop(false);
                    onDismiss();
                  },
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () {
                    ref.read(songInstallProvider.notifier).reset();
                  },
                  child: const Text('Retry'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    late final Widget content;
    if (state is SongInstallDownloading) {
      content = buildDownloading(state);
    } else if (state is SongInstallExtracting) {
      content = buildExtracting();
    } else if (state is SongInstallSuccess) {
      content = buildSuccess();
    } else if (state is SongInstallError) {
      content = buildError(state);
    } else {
      content = buildIdleOrConnecting();
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: MediaQuery.of(context).padding.bottom + 24,
      ),
      child: content,
    );
  }
}

