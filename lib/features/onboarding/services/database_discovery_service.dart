import 'dart:convert';
import 'package:dio/dio.dart';
import 'dart:developer' as developer;

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
    try {
      return DatabaseInfo(
        id: json['id']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? '',
        version: json['version']?.toString() ?? '',
        isMandatory: json['isMandatory'] == true,
        installStrategy: json['installStrategy']?.toString() ?? 'generic',
        downloadUrl: json['downloadUrl']?.toString() ?? '',
        sha256: json['sha256']?.toString() ?? '',
        fileSize: (json['fileSize'] is num) ? (json['fileSize'] as num).toInt() : (int.tryParse(json['fileSize']?.toString() ?? '0') ?? 0),
        publishedAt: json['publishedAt']?.toString() ?? '',
        bundledVersion: (json['bundledVersion'] is num) ? (json['bundledVersion'] as num).toInt() : (int.tryParse(json['bundledVersion']?.toString() ?? '1') ?? 1),
        isSingleDatabase: json['isSingleDatabase'] == true || json['isSingleDatabase'] == 1,
      );
    } catch (e, stack) {
      developer.log('Error parsing DatabaseInfo JSON: $e', error: e, stackTrace: stack);
      rethrow;
    }
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
    final cleanBaseUrl = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    final url = '$cleanBaseUrl/admin/database/available';
    
    try {
      developer.log('Fetching available databases from: $url');
      final response = await _dio.get(
        url,
        options: Options(validateStatus: (status) => status != null),
      );

      if (response.statusCode != 200) {
        throw Exception('Server returned ${response.statusCode} for $url');
      }

      dynamic responseData = response.data;
      if (responseData is String && responseData.trim().startsWith('{')) {
        try {
          responseData = jsonDecode(responseData);
        } catch (e) {
          developer.log('Failed to decode JSON string: $e');
        }
      }

      if (responseData is! Map) {
        throw FormatException('Expected JSON object response, but got ${responseData.runtimeType}');
      }

      final data = Map<String, dynamic>.from(responseData);
      if (data['success'] != true) {
        throw FormatException(data['message']?.toString() ?? 'API error');
      }

      final databasesList = data['databases'] as List?;
      if (databasesList == null) {
        return [];
      }

      return databasesList
          .whereType<Map<String, dynamic>>()
          .map(DatabaseInfo.fromJson)
          .toList();
    } on DioException catch (e) {
      developer.log('Network error fetching databases: ${e.message}', error: e);
      throw Exception('Network error: ${e.message}');
    } catch (e, stack) {
      developer.log('Error fetching available databases: $e', error: e, stackTrace: stack);
      rethrow;
    }
  }

  /// Gets info for a specific database
  /// Throws if database not found or network error
  Future<DatabaseInfo> databaseInfo(
    String apiBaseUrl,
    String databaseId,
  ) async {
    final cleanBaseUrl = apiBaseUrl.endsWith('/') ? apiBaseUrl.substring(0, apiBaseUrl.length - 1) : apiBaseUrl;
    final url = '$cleanBaseUrl/admin/database/$databaseId';

    try {
      final response = await _dio.get(
        url,
        options: Options(validateStatus: (status) => status != null),
      );

      if (response.statusCode == 404) {
        throw Exception('Database not found: $databaseId');
      }

      if (response.statusCode != 200) {
        throw Exception('Failed to fetch database info: ${response.statusCode}');
      }

      dynamic responseData = response.data;
      if (responseData is String && responseData.trim().startsWith('{')) {
        try {
          responseData = jsonDecode(responseData);
        } catch (_) {}
      }

      if (responseData is! Map) {
        throw FormatException('Expected JSON object response');
      }

      final data = Map<String, dynamic>.from(responseData);
      if (data['success'] != true) {
        throw FormatException(data['message']?.toString() ?? 'API error');
      }

      return DatabaseInfo.fromJson(data);
    } on DioException catch (e) {
      throw Exception('Network error: ${e.message}');
    }
  }
}
