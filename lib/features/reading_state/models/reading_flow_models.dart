import '../../reader/models/reader_tab.dart';

enum FlowType { bible, sermon }

extension FlowTypeX on FlowType {
  String get dbValue => name;

  static FlowType fromDbValue(String raw) {
    return FlowType.values.firstWhere(
      (item) => item.name == raw,
      orElse: () => FlowType.bible,
    );
  }
}

Map<String, dynamic> readerTabToJson(ReaderTab tab) {
  return {
    'id': tab.id,
    'type': tab.type.name,
    'title': tab.title,
    'book': tab.book,
    'chapter': tab.chapter,
    'verse': tab.verse,
    'sermonId': tab.sermonId,
    'bibleLang': tab.bibleLang,
    // Note: initialSearchQuery is NOT persisted - it's only for immediate search result navigation
  };
}

ReaderTab? readerTabFromJson(Map<String, dynamic> json) {
  final typeString = json['type'] as String?;
  if (typeString == null) return null;
  final type = ReaderContentType.values.firstWhere(
    (item) => item.name == typeString,
    orElse: () => ReaderContentType.bible,
  );

  return ReaderTab(
    id: (json['id'] as String?)?.trim().isNotEmpty == true
        ? json['id'] as String
        : null,
    type: type,
    title: (json['title'] as String?) ?? 'Reader',
    book: json['book'] as String?,
    chapter: (json['chapter'] as num?)?.toInt(),
    verse: (json['verse'] as num?)?.toInt(),
    sermonId: json['sermonId'] as String?,
    bibleLang: json['bibleLang'] as String?,
    initialSearchQuery: null, // CRITICAL: Never deserialize from persistence
  );
}

class ReadingFlowPayloadV1 {
  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final FlowType flowType;
  final String? name;
  final List<Map<String, dynamic>> tabs;
  final int activeTabIndex;
  final Map<String, dynamic>? meta;

  const ReadingFlowPayloadV1({
    required this.schemaVersion,
    required this.flowType,
    required this.tabs,
    required this.activeTabIndex,
    this.name,
    this.meta,
  });

  factory ReadingFlowPayloadV1.fromReaderTabs({
    required FlowType flowType,
    required List<ReaderTab> tabs,
    required int activeTabIndex,
    String? name,
    Map<String, dynamic>? meta,
  }) {
    return ReadingFlowPayloadV1(
      schemaVersion: currentSchemaVersion,
      flowType: flowType,
      tabs: tabs.map(readerTabToJson).toList(),
      activeTabIndex: activeTabIndex,
      name: name,
      meta: meta,
    );
  }

  List<ReaderTab> toReaderTabs() {
    return tabs
        .map(readerTabFromJson)
        .whereType<ReaderTab>()
        .toList(growable: false);
  }

  Map<String, dynamic> toJson() {
    return {
      'schemaVersion': schemaVersion,
      'flowType': flowType.name,
      'name': name,
      'tabs': tabs,
      'activeTabIndex': activeTabIndex,
      'meta': meta,
    };
  }

  factory ReadingFlowPayloadV1.fromJson(Map<String, dynamic> json) {
    final schemaVersion = (json['schemaVersion'] as num?)?.toInt() ?? 1;
    final flowTypeRaw = (json['flowType'] as String?) ?? FlowType.bible.name;
    final flowType = FlowTypeX.fromDbValue(flowTypeRaw);
    final tabsRaw = json['tabs'];
    final tabs = tabsRaw is List
        ? tabsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : <Map<String, dynamic>>[];

    return ReadingFlowPayloadV1(
      schemaVersion: schemaVersion,
      flowType: flowType,
      name: json['name'] as String?,
      tabs: tabs,
      activeTabIndex: (json['activeTabIndex'] as num?)?.toInt() ?? 0,
      meta: json['meta'] is Map
          ? Map<String, dynamic>.from(json['meta'] as Map)
          : null,
    );
  }
}

class RecentReadItem {
  final String entryKey;
  final FlowType flowType;
  final String title;
  final String subtitle;
  final ReadingFlowPayloadV1 snapshot;
  final int updatedAt;

  const RecentReadItem({
    required this.entryKey,
    required this.flowType,
    required this.title,
    required this.subtitle,
    required this.snapshot,
    required this.updatedAt,
  });
}
