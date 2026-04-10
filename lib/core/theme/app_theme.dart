import 'package:flutter/material.dart';

enum ThemeModePreference { system, light, dark, sepia, green, blue }

class AppTheme {
  /// Defines a high-quality color palette similar to the Android counterpart
  static ThemeData getThemeData({
    required ThemeModePreference preference,
    required Color primaryColor,
  }) {
    final isDark = preference == ThemeModePreference.dark;

    if (preference == ThemeModePreference.sepia) {
      return _buildReadingTheme(
        seedColor: const Color(0xFF704214),
        surfaceColor: const Color(0xFFFBF0D9),
        onSurfaceColor: const Color(0xFF5C4033),
        appBarBackgroundColor: const Color(0xFFF4E3C5),
        appBarForegroundColor: const Color(0xFF5C4033),
        selectionColor: const Color(0x66704214),
        selectionHandleColor: const Color(0xFF704214),
      );
    }

    if (preference == ThemeModePreference.green) {
      return _buildReadingTheme(
        seedColor: const Color(0xFF2E7D32),
        surfaceColor: const Color(0xFFF2FAF2),
        onSurfaceColor: const Color(0xFF214B23),
        appBarBackgroundColor: const Color(0xFFE3F4E3),
        appBarForegroundColor: const Color(0xFF214B23),
        selectionColor: const Color(0x662E7D32),
        selectionHandleColor: const Color(0xFF2E7D32),
      );
    }

    if (preference == ThemeModePreference.blue) {
      return _buildReadingTheme(
        seedColor: const Color(0xFF1565C0),
        surfaceColor: const Color(0xFFF1F7FD),
        onSurfaceColor: const Color(0xFF1F3F66),
        appBarBackgroundColor: const Color(0xFFDFECFA),
        appBarForegroundColor: const Color(0xFF1F3F66),
        selectionColor: const Color(0x661565C0),
        selectionHandleColor: const Color(0xFF1565C0),
      );
    }

    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFFAFAFA),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: isDark
            ? const Color(0x66FFFFFF)
            : const Color(0x663B82F6),
        selectionHandleColor: isDark ? Colors.white : const Color(0xFF3B82F6),
      ),
    );
  }

  static ThemeData _buildReadingTheme({
    required Color seedColor,
    required Color surfaceColor,
    required Color onSurfaceColor,
    required Color appBarBackgroundColor,
    required Color appBarForegroundColor,
    required Color selectionColor,
    required Color selectionHandleColor,
  }) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: Brightness.light,
      surface: surfaceColor,
      onSurface: onSurfaceColor,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: surfaceColor,
      appBarTheme: AppBarTheme(
        backgroundColor: appBarBackgroundColor,
        foregroundColor: appBarForegroundColor,
        elevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: selectionColor,
        selectionHandleColor: selectionHandleColor,
      ),
    );
  }
}
