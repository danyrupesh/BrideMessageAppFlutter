/// Equivalent to Android's DatabaseType enum and InstalledDatabaseEntity.
enum DbType { bible, sermon }

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
  String get dbFileName =>
      type == DbType.bible ? 'bible_$code.db' : 'sermons_$code.db';

  factory InstalledDatabase.fromMap(Map<String, dynamic> map) {
    return InstalledDatabase(
      id: map['id'] as int?,
      type: map['type'] == 'BIBLE' ? DbType.bible : DbType.sermon,
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
      'type': type == DbType.bible ? 'BIBLE' : 'SERMON',
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
}
