import 'package:shared_preferences/shared_preferences.dart';

class HymnFavoritesStore {
  static const _key = 'favorite_hymn_nos';

  Future<Set<int>> loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList(_key) ?? const [];
    return list.map(int.parse).toSet();
  }

  Future<void> toggleFavorite(int hymnNo) async {
    final prefs = await SharedPreferences.getInstance();
    final current = await loadFavorites();
    if (current.contains(hymnNo)) {
      current.remove(hymnNo);
    } else {
      current.add(hymnNo);
    }
    await prefs.setStringList(
      _key,
      current.map((e) => e.toString()).toList(),
    );
  }
}

