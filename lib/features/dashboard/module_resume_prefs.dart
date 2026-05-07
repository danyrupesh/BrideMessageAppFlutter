import 'package:shared_preferences/shared_preferences.dart';

/// Last-open module locations used when opening sections from Home.
abstract final class ModuleResumePrefs {
  static String _tractIdKey(String lang) => 'module_resume_tract_id_$lang';
  static String _storyIdKey(String lang) => 'module_resume_story_id_$lang';
  static String _storySectionKey(String lang) =>
      'module_resume_story_section_$lang';
  static String _codAnswerIdKey(String lang) =>
      'module_resume_cod_detail_id_$lang';

  static const _hymnEnKey = 'module_resume_hymn_no_en';
  static const _songTaIdKey = 'module_resume_song_id_ta';

  static Future<void> saveLastTract(String lang, String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_tractIdKey(lang), id);
  }

  static Future<String?> peekLastTractId(String lang) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_tractIdKey(lang));
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> saveLastStory({
    required String lang,
    required String id,
    required String section,
  }) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_storyIdKey(lang), id);
    await p.setString(_storySectionKey(lang), section);
  }

  static Future<List<String?>> peekLastStory(String lang) async {
    final p = await SharedPreferences.getInstance();
    final id = p.getString(_storyIdKey(lang));
    final section = p.getString(_storySectionKey(lang));
    if (id == null || id.isEmpty) return const [null, null];
    return [id, section];
  }

  static Future<void> saveLastCodDetail(String lang, String id) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_codAnswerIdKey(lang), id);
  }

  static Future<String?> peekLastCodDetailId(String lang) async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_codAnswerIdKey(lang));
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static Future<void> saveLastEnglishHymn(int hymnNo) async {
    if (hymnNo <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_hymnEnKey, hymnNo);
  }

  static Future<int?> peekLastEnglishHymn() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(_hymnEnKey);
    if (n == null || n <= 0) return null;
    return n;
  }

  static Future<void> saveLastTamilSongId(int songId) async {
    if (songId <= 0) return;
    final p = await SharedPreferences.getInstance();
    await p.setInt(_songTaIdKey, songId);
  }

  static Future<int?> peekLastTamilSongId() async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(_songTaIdKey);
    if (n == null || n <= 0) return null;
    return n;
  }

  static String churchAgesTopicKey(String lang) =>
      'church_ages_selected_topic_$lang';

  static Future<int?> peekChurchAgesTopicId(String lang) async {
    final p = await SharedPreferences.getInstance();
    final n = p.getInt(churchAgesTopicKey(lang));
    if (n == null || n <= 0) return null;
    return n;
  }
}
