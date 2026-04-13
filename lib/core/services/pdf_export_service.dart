import 'dart:typed_data';
import 'dart:convert';

import 'package:dio/dio.dart';

class PdfExportException implements Exception {
  const PdfExportException(this.message, {this.isNetworkIssue = false});

  final String message;
  final bool isNetworkIssue;

  @override
  String toString() => message;
}

class PdfExportService {
  PdfExportService({Dio? dio}) : _dio = dio ?? Dio();

  final Dio _dio;

  static const String _baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.endtimebride.in',
  );

  Future<Uint8List> export(Map<String, dynamic> payload) async {
    try {
      final response = await _dio.post<List<int>>(
        '$_baseUrl/pdf/export',
        data: payload,
        options: Options(
          responseType: ResponseType.bytes,
          sendTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(seconds: 60),
          headers: const {'Content-Type': 'application/json'},
        ),
      );

      final bytes = response.data;
      if (bytes == null || bytes.isEmpty) {
        throw const PdfExportException('Empty PDF response from server.');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      final isNetworkIssue =
          e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout;

      final serverMessage = _extractServerMessage(e.response?.data);
      final statusCode = e.response?.statusCode;
      if (statusCode == 400) {
        throw PdfExportException(
          serverMessage ?? 'Invalid PDF export request.',
          isNetworkIssue: false,
        );
      }
      if (statusCode == 500) {
        throw PdfExportException(
          serverMessage ?? 'PDF generation failed on server.',
          isNetworkIssue: false,
        );
      }

      if (isNetworkIssue) {
        throw const PdfExportException(
          'PDF export requires internet connection.',
          isNetworkIssue: true,
        );
      }

      throw PdfExportException(
        serverMessage ?? 'Failed to export PDF. ${e.message ?? ''}'.trim(),
        isNetworkIssue: false,
      );
    } on PdfExportException {
      rethrow;
    } catch (_) {
      throw const PdfExportException('Failed to export PDF.');
    }
  }

  String? _extractServerMessage(dynamic data) {
    if (data == null) return null;
    if (data is Map) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) return message;
      return null;
    }
    if (data is List<int>) {
      try {
        final decoded = utf8.decode(data);
        final parsed = jsonDecode(decoded);
        if (parsed is Map && parsed['message'] is String) {
          final message = parsed['message'] as String;
          if (message.trim().isNotEmpty) return message;
        }
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}
