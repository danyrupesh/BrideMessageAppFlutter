import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TypographySettings {
  final double fontSize;
  final double lineHeight;
  final String fontFamily;
  final bool isFullscreen;

  TypographySettings({
    this.fontSize = 18.0,
    this.lineHeight = 2.0,
    this.fontFamily = 'Sora',
    this.isFullscreen = false,
  });

  TypographySettings copyWith({
    double? fontSize,
    double? lineHeight,
    String? fontFamily,
    bool? isFullscreen,
  }) {
    return TypographySettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      isFullscreen: isFullscreen ?? this.isFullscreen,
    );
  }
}

class TypographyNotifier extends Notifier<TypographySettings> {
  static const _fontSizeKey = 'reader_font_size';
  static const _lineHeightKey = 'reader_line_height';
  static const _fontFamilyKey = 'reader_font_family';
  static const _fullscreenKey = 'reader_fullscreen';

  @override
  TypographySettings build() {
    _load();
    return TypographySettings();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = TypographySettings(
      fontSize: prefs.getDouble(_fontSizeKey) ?? 18.0,
      lineHeight: prefs.getDouble(_lineHeightKey) ?? 2.0,
      fontFamily: prefs.getString(_fontFamilyKey) ?? 'Sora',
      isFullscreen: prefs.getBool(_fullscreenKey) ?? false,
    );
    _applySystemUi(state.isFullscreen);
  }

  void updateFontSize(double size) {
    state = state.copyWith(fontSize: size);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_fontSizeKey, size));
  }

  void updateLineHeight(double height) {
    state = state.copyWith(lineHeight: height);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble(_lineHeightKey, height));
  }

  void updateFontFamily(String family) {
    state = state.copyWith(fontFamily: family);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString(_fontFamilyKey, family));
  }

  void toggleFullscreen() {
    final next = !state.isFullscreen;
    state = state.copyWith(isFullscreen: next);
    _applySystemUi(next);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setBool(_fullscreenKey, next));
  }

  void _applySystemUi(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}

final typographyProvider =
    NotifierProvider<TypographyNotifier, TypographySettings>(() {
  return TypographyNotifier();
});
