import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Initializes desktop sqflite factory for platforms that require ffi wiring.
class SqlitePlatformBootstrap {
  static bool _initialized = false;

  static Future<void> ensureInitialized() async {
    if (_initialized) return;

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    _initialized = true;
  }
}
