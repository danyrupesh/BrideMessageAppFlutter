import 'dart:io';

import 'package:flutter/services.dart';

class AppRestartHelper {
  static Future<void> restartAfterDatabaseUpgrade() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await Process.start(
          Platform.resolvedExecutable,
          Platform.executableArguments,
          mode: ProcessStartMode.detached,
        );
      } catch (_) {
        // Best effort relaunch; fallback is to close app.
      }
      exit(0);
    }

    await SystemNavigator.pop();
  }
}