import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';

class DesktopFileSaver {
  static Future<String?> savePdf({
    required String suggestedName,
    required List<int> bytes,
  }) async {
    // Desktop platforms: show native Save dialog.
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
      );
      if (location == null || location.path.isEmpty) return null;
      final file = File(location.path);
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }

    // Mobile / other: fall back to sharePdf (no direct path).
    await Printing.sharePdf(bytes: bytes, filename: suggestedName);
    return null;
  }

  static Future<void> revealInExplorer(String path) async {
    if (path.isEmpty) return;

    try {
      if (Platform.isWindows) {
        await Process.start(
          'explorer',
          ['/select,', path],
        );
      } else if (Platform.isMacOS) {
        await Process.start('open', ['-R', path]);
      } else if (Platform.isLinux) {
        await Process.start('xdg-open', [p.dirname(path)]);
      }
    } catch (_) {
      // Best-effort only; ignore failures.
    }
  }
}

