import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TypographySettings {
  static const String systemFontFamily = '__system__';

  final double fontSize;
  final double titleFontSize;
  final double lineHeight;
  final String fontFamily;
  final bool isFullscreen;

  TypographySettings({
    this.fontSize = 18.0,
    this.titleFontSize = 13.0,
    this.lineHeight = 2.0,
    this.fontFamily = systemFontFamily,
    this.isFullscreen = false,
  });

  String? get resolvedFontFamily {
    if (fontFamily == systemFontFamily || fontFamily.trim().isEmpty) {
      return null;
    }
    return fontFamily;
  }

  TypographySettings copyWith({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
    String? fontFamily,
    bool? isFullscreen,
  }) {
    return TypographySettings(
      fontSize: fontSize ?? this.fontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      fontFamily: fontFamily ?? this.fontFamily,
      isFullscreen: isFullscreen ?? this.isFullscreen,
    );
  }
}

class _LangTypographyDefaults {
  const _LangTypographyDefaults({
    required this.fontSize,
    required this.titleFontSize,
    required this.lineHeight,
  });

  final double fontSize;
  final double titleFontSize;
  final double lineHeight;
}

// ─── Global Settings (Shared across all languages) ──────────────────────────

class _TypographyGlobalState {
  final String fontFamily;
  final bool isFullscreen;

  _TypographyGlobalState({
    required this.fontFamily,
    required this.isFullscreen,
  });

  _TypographyGlobalState copyWith({
    String? fontFamily,
    bool? isFullscreen,
  }) {
    return _TypographyGlobalState(
      fontFamily: fontFamily ?? this.fontFamily,
      isFullscreen: isFullscreen ?? this.isFullscreen,
    );
  }
}

class _TypographyGlobalNotifier extends Notifier<_TypographyGlobalState> {
  static const _fontFamilyKey = 'reader_font_family';
  static const _fullscreenKey = 'reader_fullscreen';

  @override
  _TypographyGlobalState build() {
    _load();
    return _TypographyGlobalState(
      fontFamily: TypographySettings.systemFontFamily,
      isFullscreen: false,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedFamily = prefs.getString(_fontFamilyKey);
    final normalizedFamily =
        (storedFamily == null ||
            storedFamily.trim().isEmpty ||
            storedFamily == 'System' ||
            storedFamily == 'Default')
        ? TypographySettings.systemFontFamily
        : storedFamily;

    state = _TypographyGlobalState(
      fontFamily: normalizedFamily,
      isFullscreen: prefs.getBool(_fullscreenKey) ?? false,
    );
    _applySystemUi(state.isFullscreen);
  }

  void updateFontFamily(String family) {
    final normalized = family.trim().isEmpty
        ? TypographySettings.systemFontFamily
        : family;
    state = state.copyWith(fontFamily: normalized);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setString(_fontFamilyKey, normalized),
    );
  }

  void toggleFullscreen() {
    final next = !state.isFullscreen;
    state = state.copyWith(isFullscreen: next);
    _applySystemUi(next);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setBool(_fullscreenKey, next),
    );
  }

  void _applySystemUi(bool fullscreen) {
    if (fullscreen) {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
  }
}

final typographyGlobalProvider =
    NotifierProvider<_TypographyGlobalNotifier, _TypographyGlobalState>(
      _TypographyGlobalNotifier.new,
    );

// ─── Language-specific Settings ──────────────────────────────────────────────

class _TypographyLangState {
  final double fontSize;
  final double titleFontSize;
  final double lineHeight;

  _TypographyLangState({
    required this.fontSize,
    required this.titleFontSize,
    required this.lineHeight,
  });

  _TypographyLangState copyWith({
    double? fontSize,
    double? titleFontSize,
    double? lineHeight,
  }) {
    return _TypographyLangState(
      fontSize: fontSize ?? this.fontSize,
      titleFontSize: titleFontSize ?? this.titleFontSize,
      lineHeight: lineHeight ?? this.lineHeight,
    );
  }
}

abstract class _BaseTypographyLangNotifier extends Notifier<_TypographyLangState> {
  String get lang;
  _LangTypographyDefaults get defaults;

  static const _fontSizeKeyPrefix = 'reader_font_size_';
  static const _titleFontSizeKeyPrefix = 'reader_title_font_size_';
  static const _lineHeightKeyPrefix = 'reader_line_height_';

  String _fontSizeKey() => '$_fontSizeKeyPrefix$lang';
  String _titleFontSizeKey() => '$_titleFontSizeKeyPrefix$lang';
  String _lineHeightKey() => '$_lineHeightKeyPrefix$lang';

  @override
  _TypographyLangState build() {
    _load();
    return _TypographyLangState(
      fontSize: defaults.fontSize,
      titleFontSize: defaults.titleFontSize,
      lineHeight: defaults.lineHeight,
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = _TypographyLangState(
      fontSize: prefs.getDouble(_fontSizeKey()) ?? defaults.fontSize,
      titleFontSize: prefs.getDouble(_titleFontSizeKey()) ?? defaults.titleFontSize,
      lineHeight: prefs.getDouble(_lineHeightKey()) ?? defaults.lineHeight,
    );
  }

  void updateFontSize(double size) {
    state = state.copyWith(fontSize: size);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_fontSizeKey(), size),
    );
  }

  void updateTitleFontSize(double size) {
    state = state.copyWith(titleFontSize: size);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_titleFontSizeKey(), size),
    );
  }

  void updateLineHeight(double height) {
    state = state.copyWith(lineHeight: height);
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_lineHeightKey(), height),
    );
  }
}

class _ENTypographyNotifier extends _BaseTypographyLangNotifier {
  @override
  String get lang => 'en';
  @override
  _LangTypographyDefaults get defaults => const _LangTypographyDefaults(
    fontSize: 18.0,
    titleFontSize: 18.0,
    lineHeight: 2.0,
  );
}

class _TATypographyNotifier extends _BaseTypographyLangNotifier {
  @override
  String get lang => 'ta';
  @override
  _LangTypographyDefaults get defaults => const _LangTypographyDefaults(
    fontSize: 18.0,
    titleFontSize: 16.0,
    lineHeight: 1.8,
  );
}

final enTypographyProvider = NotifierProvider<_ENTypographyNotifier, _TypographyLangState>(
  _ENTypographyNotifier.new,
);

final taTypographyProvider = NotifierProvider<_TATypographyNotifier, _TypographyLangState>(
  _TATypographyNotifier.new,
);

// ─── Combined Public Provider ────────────────────────────────────────────────

final typographyProvider = Provider.family<TypographySettings, String>((ref, lang) {
  final global = ref.watch(typographyGlobalProvider);
  final langSettings = lang == 'ta' 
      ? ref.watch(taTypographyProvider) 
      : ref.watch(enTypographyProvider);

  return TypographySettings(
    fontSize: langSettings.fontSize,
    titleFontSize: langSettings.titleFontSize,
    lineHeight: langSettings.lineHeight,
    fontFamily: global.fontFamily,
    isFullscreen: global.isFullscreen,
  );
});

// For backward compatibility or areas where language isn't known yet (e.g. settings)
final defaultTypographyProvider = typographyProvider('en');
