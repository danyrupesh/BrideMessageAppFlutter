import 'package:flutter/material.dart';

enum ThemeModePreference { system, light, dark, sepia }

class AppTheme {
  /// Defines a high-quality color palette similar to the Android counterpart
  static ThemeData getThemeData({
    required ThemeModePreference preference,
    required Color primaryColor,
  }) {
    // Determine exact Brightness based on preference
    final isDark = preference == ThemeModePreference.dark;

    // Core definition
    final colorScheme = ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: isDark ? Brightness.dark : Brightness.light,
    );

    // Apply specific overrides for Sepia
    if (preference == ThemeModePreference.sepia) {
      final sepiaScheme = ColorScheme.fromSeed(
        seedColor: const Color(0xFF704214), // Sepia brownish seed
        brightness: Brightness.light,
        surface: const Color(0xFFFBF0D9), // Classic sepia paper
        onSurface: const Color(0xFF5C4033), // Dark brown ink
      );

      return ThemeData(
        useMaterial3: true,
        colorScheme: sepiaScheme,
        scaffoldBackgroundColor: const Color(0xFFFBF0D9),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF4E3C5),
          foregroundColor: Color(0xFF5C4033),
          elevation: 0,
        ),
        textSelectionTheme: const TextSelectionThemeData(
          selectionColor: Color(0x66704214), // translucent sepia accent
          selectionHandleColor: Color(0xFF704214),
        ),
      );
    }

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor:
          isDark ? const Color(0xFF121212) : const Color(0xFFFAFAFA),
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: isDark
            ? const Color(0x66FFFFFF)
            : const Color(0x663B82F6), // translucent accent
        selectionHandleColor:
            isDark ? Colors.white : const Color(0xFF3B82F6),
      ),
    );
  }
}
