import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
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

/// Per-language defaults for body / title / line height (font + fullscreen are global).
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

class TypographyNotifier extends Notifier<TypographySettings> {
  static const _legacyFontSizeKey = 'reader_font_size';
  static const _legacyTitleFontSizeKey = 'reader_title_font_size';
  static const _legacyLineHeightKey = 'reader_line_height';

  static const _fontFamilyKey = 'reader_font_family';
  static const _fullscreenKey = 'reader_fullscreen';
  static const _prefsMigratedKey = 'reader_typography_lang_split_v1';

  static const _en = 'en';
  static const _ta = 'ta';

  static const _defaultsEn = _LangTypographyDefaults(
    fontSize: 18.0,
    titleFontSize: 13.0,
    lineHeight: 2.0,
  );

  /// Tamil reader defaults (see product reference).
  static const _defaultsTa = _LangTypographyDefaults(
    fontSize: 18.0,
    titleFontSize: 11.0,
    lineHeight: 1.8,
  );

  String _contentLang = _en;
  String? _loadedForLang;

  int _loadGen = 0;

  static String _fontSizeKey(String lang) => 'reader_font_size_$lang';
  static String _titleFontSizeKey(String lang) =>
      'reader_title_font_size_$lang';
  static String _lineHeightKey(String lang) => 'reader_line_height_$lang';

  static String _normalizeLang(String? raw) => raw == _ta ? _ta : _en;

  static _LangTypographyDefaults _defaultsFor(String lang) =>
      lang == _ta ? _defaultsTa : _defaultsEn;

  @override
  TypographySettings build() {
    // Persisted values load when the active reader screen calls
    // [setReaderContentLanguage] (Bible / sermon / COD).
    return TypographySettings(
      fontSize: _defaultsEn.fontSize,
      titleFontSize: _defaultsEn.titleFontSize,
      lineHeight: _defaultsEn.lineHeight,
      fontFamily: TypographySettings.systemFontFamily,
      isFullscreen: false,
    );
  }

  /// Call from Bible / sermon / COD screens so size sliders map to the correct language bucket.
  void setReaderContentLanguage(String rawLang) {
    final next = _normalizeLang(rawLang);
    if (next == _contentLang && _loadedForLang == next) return;
    _contentLang = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) return;
      _reloadTypographyForCurrentLang();
    });
  }

  Future<void> _migrateLegacyPrefsIfNeeded(SharedPreferences prefs) async {
    if (prefs.getBool(_prefsMigratedKey) == true) return;

    Future<void> copyLegacyToEn(String legacyKey, String enKey) async {
      final v = prefs.getDouble(legacyKey);
      if (v != null && prefs.getDouble(enKey) == null) {
        await prefs.setDouble(enKey, v);
      }
    }

    await copyLegacyToEn(_legacyFontSizeKey, _fontSizeKey(_en));
    await copyLegacyToEn(_legacyTitleFontSizeKey, _titleFontSizeKey(_en));
    await copyLegacyToEn(_legacyLineHeightKey, _lineHeightKey(_en));

    await prefs.setBool(_prefsMigratedKey, true);
  }

  Future<void> _reloadTypographyForCurrentLang() async {
    final gen = ++_loadGen;
    final prefs = await SharedPreferences.getInstance();
    if (gen != _loadGen) return;

    await _migrateLegacyPrefsIfNeeded(prefs);
    if (gen != _loadGen) return;

    final lang = _contentLang;
    final d = _defaultsFor(lang);

    final storedFamily = prefs.getString(_fontFamilyKey);
    final normalizedFamily =
        (storedFamily == null ||
            storedFamily.trim().isEmpty ||
            storedFamily == 'System' ||
            storedFamily == 'Default')
        ? TypographySettings.systemFontFamily
        : storedFamily;

    final nextState = TypographySettings(
      fontSize: prefs.getDouble(_fontSizeKey(lang)) ?? d.fontSize,
      titleFontSize:
          prefs.getDouble(_titleFontSizeKey(lang)) ?? d.titleFontSize,
      lineHeight: prefs.getDouble(_lineHeightKey(lang)) ?? d.lineHeight,
      fontFamily: normalizedFamily,
      isFullscreen: prefs.getBool(_fullscreenKey) ?? false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!ref.mounted) return;
      if (gen != _loadGen) return;
      state = nextState;
      _loadedForLang = lang;
      _applySystemUi(state.isFullscreen);
    });
  }

  void updateFontSize(double size) {
    state = state.copyWith(fontSize: size);
    final lang = _contentLang;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_fontSizeKey(lang), size),
    );
  }

  void updateTitleFontSize(double size) {
    state = state.copyWith(titleFontSize: size);
    final lang = _contentLang;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_titleFontSizeKey(lang), size),
    );
  }

  void updateLineHeight(double height) {
    state = state.copyWith(lineHeight: height);
    final lang = _contentLang;
    SharedPreferences.getInstance().then(
      (prefs) => prefs.setDouble(_lineHeightKey(lang), height),
    );
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

final typographyProvider =
    NotifierProvider<TypographyNotifier, TypographySettings>(() {
      return TypographyNotifier();
    });
