import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:path/path.dart' as p;

/// Desktop-only helper for saving PDFs and revealing them in the OS file
/// explorer. Mobile platforms should handle their own save / share flows.
class DesktopFileSaver {
  static Future<String?> savePdf({
    required String suggestedName,
    required List<int> bytes,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      // Non-desktop platforms: caller is expected to handle saving/sharing.
      return null;
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF',
          extensions: ['pdf'],
        ),
      ],
    );
    if (location == null || location.path.isEmpty) return null;

    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  static Future<String?> saveText({
    required String suggestedName,
    required List<int> bytes,
  }) async {
    if (!(Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      return null;
    }

    final location = await getSaveLocation(
      suggestedName: suggestedName,
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Text',
          extensions: ['txt'],
        ),
      ],
    );
    if (location == null || location.path.isEmpty) return null;

    final file = File(location.path);
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
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

