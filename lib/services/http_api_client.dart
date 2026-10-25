import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class HttpApiClient {
  static const String _defaultUrl = kIsWeb
      ? 'http://localhost:4000'
      : (kDebugMode && !kIsWeb)
          // 10.0.2.2 is Android emulator loopback to host; localhost for desktop/iOS
          ? 'http://10.0.2.2:4000'
          : 'http://localhost:4000';

  final String baseUrl;
  final http.Client _client;

  HttpApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ??
            const String.fromEnvironment('API_BASE_URL', defaultValue: _defaultUrl),
        _client = client ?? http.Client();

  Map<String, String> get _headers {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
  }

  Future<dynamic> get(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final res = await _client.get(uri, headers: _headers).timeout(const Duration(seconds: 10));
      return _handleResponse(res);
    } on SocketException catch (e) {
      debugPrint('[API] Socket error on GET $path: $e');
      throw Exception('Gagal terhubung ke server backend ($baseUrl).');
    }
  }

  Future<dynamic> post(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl$path');
    try {
      final res = await _client
          .post(uri, headers: _headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 10));
      return _handleResponse(res);
    } on SocketException catch (e) {
      debugPrint('[API] Socket error on POST $path: $e');
      throw Exception('Gagal terhubung ke server backend ($baseUrl).');
    }
  }

  dynamic _handleResponse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    debugPrint('[API] Error ${res.statusCode}: ${res.body}');
    throw HttpException('Server error: ${res.statusCode} - ${res.body}', uri: res.request?.url);
  }

  void close() {
    _client.close();
  }
}
