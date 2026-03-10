import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_theme.dart';

class ThemeSettings {
  final ThemeModePreference mode;
  final Color primaryColor;

  ThemeSettings({
    this.mode = ThemeModePreference.system,
    this.primaryColor = Colors.deepPurple, // Default Primary
  });

  ThemeSettings copyWith({ThemeModePreference? mode, Color? primaryColor}) {
    return ThemeSettings(
      mode: mode ?? this.mode,
      primaryColor: primaryColor ?? this.primaryColor,
    );
  }
}

class ThemeNotifier extends Notifier<ThemeSettings> {
  static const _modeKey = 'theme_mode';
  static const _colorKey = 'theme_color';

  @override
  ThemeSettings build() {
    _loadSettings();
    // Return initial default while loading
    return ThemeSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final modeIndex = prefs.getInt(_modeKey) ?? 0;
    final colorValue = prefs.getInt(_colorKey) ?? Colors.deepPurple.value;

    state = ThemeSettings(
      mode: ThemeModePreference.values.elementAt(modeIndex),
      primaryColor: Color(colorValue),
    );
  }

  Future<void> updateMode(ThemeModePreference mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_modeKey, mode.index);
    state = state.copyWith(mode: mode);
  }

  Future<void> updatePrimaryColor(Color color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color.value);
    state = state.copyWith(primaryColor: color);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeSettings>(() {
  return ThemeNotifier();
});
