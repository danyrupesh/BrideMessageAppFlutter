import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class ImageViewerWidget extends StatelessWidget {
  const ImageViewerWidget({
    super.key,
    required this.imageUrl,
    this.heroTag,
  });

  final String imageUrl;
  final String? heroTag;

  Future<void> _downloadImage(BuildContext context) async {
    try {
      Uint8List? bytes;
      String ext = 'jpg';

      if (imageUrl.startsWith('data:')) {
        final commaIdx = imageUrl.indexOf(',');
        if (commaIdx == -1) throw Exception('Invalid data URL');
        final header = imageUrl.substring(0, commaIdx).toLowerCase();
        if (header.contains('png')) ext = 'png';
        if (header.contains('gif')) ext = 'gif';
        if (header.contains('webp')) ext = 'webp';
        bytes = base64Decode(imageUrl.substring(commaIdx + 1));
      } else {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot download remote image directly.'),
          ),
        );
        return;
      }

      final dir = await _getSaveDirectory();
      final fileName =
          'image_${DateTime.now().millisecondsSinceEpoch}.$ext';
      final file = File('${dir.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(bytes);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved: ${file.path}'),
          action: SnackBarAction(
            label: 'OK',
            onPressed: () {},
          ),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Download failed: $e')),
      );
    }
  }

  Future<Directory> _getSaveDirectory() async {
    try {
      final dl = await getDownloadsDirectory();
      if (dl != null) return dl;
    } catch (_) {}
    return getApplicationDocumentsDirectory();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withAlpha(160),
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_outlined),
            tooltip: 'Download image',
            onPressed: () => _downloadImage(context),
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 6.0,
          child: heroTag != null
              ? Hero(
                  tag: heroTag!,
                  child: _ImageWidget(url: imageUrl),
                )
              : _ImageWidget(url: imageUrl),
        ),
      ),
    );
  }
}

class _ImageWidget extends StatelessWidget {
  const _ImageWidget({required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    // ── Base64 data URL ──────────────────────────────────────────────────────
    if (url.startsWith('data:')) {
      final commaIdx = url.indexOf(',');
      if (commaIdx != -1) {
        try {
          final bytes = base64Decode(url.substring(commaIdx + 1));
          return Image.memory(
            bytes,
            fit: BoxFit.contain,
            errorBuilder: (context, error, stackTrace) => _brokenIcon(),
          );
        } catch (_) {}
      }
      return _brokenIcon();
    }

    // ── Network URL ──────────────────────────────────────────────────────────
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Center(
            child: CircularProgressIndicator(
              value: loadingProgress.expectedTotalBytes != null
                  ? loadingProgress.cumulativeBytesLoaded /
                      loadingProgress.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) => _brokenIcon(),
      );
    }

    // ── Asset / file path ────────────────────────────────────────────────────
    if (url.startsWith('/') || url.contains(':\\') || url.contains(':/')) {
      return Image.file(
        File(url),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => _brokenIcon(),
      );
    }

    return Image.asset(
      url,
      fit: BoxFit.contain,
      errorBuilder: (context, error, stackTrace) => _brokenIcon(),
    );
  }

  Widget _brokenIcon() => const Center(
        child: Icon(Icons.broken_image, color: Colors.white54, size: 64),
      );
}
