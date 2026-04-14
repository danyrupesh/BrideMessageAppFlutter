import 'package:dio/dio.dart';

/// Represents metadata for an available database stream
class DatabaseInfo {
  final String id;
  final String displayName;
  final String version;
  final bool isMandatory;
  final String installStrategy;
  final String downloadUrl;
  final String sha256;
  final int fileSize;
  final String publishedAt;
  final int bundledVersion;
  final bool isSingleDatabase;

  const DatabaseInfo({
    required this.id,
    required this.displayName,
    required this.version,
    required this.isMandatory,
    required this.installStrategy,
    required this.downloadUrl,
    required this.sha256,
    required this.fileSize,
    required this.publishedAt,
    required this.bundledVersion,
    required this.isSingleDatabase,
  });

  factory DatabaseInfo.fromJson(Map<String, dynamic> json) {
    return DatabaseInfo(
      id: json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? '',
      version: json['version'] as String? ?? '',
      isMandatory: json['isMandatory'] as bool? ?? false,
      installStrategy: json['installStrategy'] as String? ?? 'generic',
      downloadUrl: json['downloadUrl'] as String? ?? '',
      sha256: json['sha256'] as String? ?? '',
      fileSize: json['fileSize'] as int? ?? 0,
      publishedAt: json['publishedAt'] as String? ?? '',
      bundledVersion: json['bundledVersion'] as int? ?? 1,
      isSingleDatabase: json['isSingleDatabase'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'version': version,
    'isMandatory': isMandatory,
    'installStrategy': installStrategy,
    'downloadUrl': downloadUrl,
    'sha256': sha256,
    'fileSize': fileSize,
    'publishedAt': publishedAt,
    'bundledVersion': bundledVersion,
    'isSingleDatabase': isSingleDatabase,
  };

  @override
  String toString() => 'DatabaseInfo($id v$version)';
}

/// Discovers available database streams from the server
class DatabaseDiscoveryService {
  final Dio _dio;

  DatabaseDiscoveryService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 30),
              ),
            );

  /// Gets list of all available databases
  /// Throws on network error
  Future<List<DatabaseInfo>> availableDatabases(String apiBaseUrl) async {
    try {
      final response = await _dio.get(
        '$apiBaseUrl/api/database/available',
        options: Options(validateStatus: (status) => status == 200),
      );

      if (response.data is! Map) {
        throw FormatException('Expected JSON object response');
      }

      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true) {
        throw FormatException(data['message'] as String? ?? 'API error');
      }

      final databases = data['databases'] as List?;
      if (databases == null) {
        return [];
      }

      return databases
          .whereType<Map<String, dynamic>>()
          .map(DatabaseInfo.fromJson)
          .toList();
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }

  /// Gets info for a specific database
  /// Throws if database not found or network error
  Future<DatabaseInfo> databaseInfo(
    String apiBaseUrl,
    String databaseId,
  ) async {
    try {
      final response = await _dio.get(
        '$apiBaseUrl/api/database/$databaseId',
        options: Options(validateStatus: (status) => status != null),
      );

      if (response.statusCode == 404) {
        throw Exception('Database not found: $databaseId');
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch database info: ${response.statusCode}');
      }

      if (response.data is! Map) {
        throw FormatException('Expected JSON object response');
      }

      final data = response.data as Map<String, dynamic>;
      if (data['success'] != true) {
        throw FormatException(data['message'] as String? ?? 'API error');
      }

      return DatabaseInfo.fromJson(data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }
}
