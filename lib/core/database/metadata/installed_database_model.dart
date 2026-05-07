/// Equivalent to Android's DatabaseType enum and InstalledDatabaseEntity.
enum DbType { bible, sermon, churchAges, quote, prayerQuote }

class InstalledDatabase {
  final int? id;
  final DbType type;
  final String code; // 'kjv', 'bsi' for Bible; 'en', 'ta' for Sermon
  final String displayName;
  final String language; // 'en' or 'ta'
  final int installedDate; // epoch ms
  final int fileSize; // bytes
  final int? recordCount; // total rows for this content (e.g., total sermons)
  final bool isDefault;

  const InstalledDatabase({
    this.id,
    required this.type,
    required this.code,
    required this.displayName,
    required this.language,
    required this.installedDate,
    required this.fileSize,
    this.recordCount,
    this.isDefault = false,
  });

  /// Returns the expected DB filename on device.
  String get dbFileName {
    switch (type) {
      case DbType.bible:
        return 'bible_$code.db';
      case DbType.sermon:
        return 'sermons_$code.db';
      case DbType.churchAges:
        return 'church_ages_$code.db';
      case DbType.quote:
        return 'quotes_$code.db';
      case DbType.prayerQuote:
        return 'prayer_quotes_$code.db';
    }
  }

  factory InstalledDatabase.fromMap(Map<String, dynamic> map) {
    return InstalledDatabase(
      id: map['id'] as int?,
      type: _parseType(map['type'] as String),
      code: map['code'] as String,
      displayName: map['display_name'] as String,
      language: map['language'] as String,
      installedDate: map['installed_date'] as int,
      fileSize: map['file_size'] as int,
      recordCount: (map['record_count'] as num?)?.toInt(),
      isDefault: (map['is_default'] as int) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': _typeToString(type),
      'code': code,
      'display_name': displayName,
      'language': language,
      'installed_date': installedDate,
      'file_size': fileSize,
      'record_count': recordCount,
      'is_default': isDefault ? 1 : 0,
    };
  }

  InstalledDatabase copyWith({bool? isDefault, int? recordCount}) {
    return InstalledDatabase(
      id: id,
      type: type,
      code: code,
      displayName: displayName,
      language: language,
      installedDate: installedDate,
      fileSize: fileSize,
      recordCount: recordCount ?? this.recordCount,
      isDefault: isDefault ?? this.isDefault,
    );
  }

  static DbType _parseType(String type) {
    switch (type) {
      case 'BIBLE':
        return DbType.bible;
      case 'SERMON':
        return DbType.sermon;
      case 'CHURCH_AGES':
        return DbType.churchAges;
      case 'QUOTE':
        return DbType.quote;
      case 'PRAYER_QUOTE':
        return DbType.prayerQuote;
      default:
        return DbType.bible;
    }
  }

  static String _typeToString(DbType type) {
    switch (type) {
      case DbType.bible:
        return 'BIBLE';
      case DbType.sermon:
        return 'SERMON';
      case DbType.churchAges:
        return 'CHURCH_AGES';
      case DbType.quote:
        return 'QUOTE';
      case DbType.prayerQuote:
        return 'PRAYER_QUOTE';
    }
  }
}
