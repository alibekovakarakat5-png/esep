import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_service.dart';
import 'base_url_stub.dart'
    if (dart.library.html) 'base_url_web.dart';

class ApiClient {
  static String get _base => detectApiBase();

  // ── Public helpers ────────────────────────────────────────────────────────

  static Future<dynamic> get(String path) async {
    final res = await http.get(_uri(path), headers: await _headers());
    return _parse(res);
  }

  static Future<dynamic> post(String path, Object body) async {
    final res = await http.post(
      _uri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _parse(res);
  }

  static Future<dynamic> put(String path, Object body) async {
    final res = await http.put(
      _uri(path),
      headers: await _headers(),
      body: jsonEncode(body),
    );
    return _parse(res);
  }

  static Future<void> delete(String path) async {
    final res = await http.delete(_uri(path), headers: await _headers());
    _parse(res);
  }

  // ── Private ───────────────────────────────────────────────────────────────

  static Uri _uri(String path) => Uri.parse('$_base$path');

  static Future<Map<String, String>> _headers() async {
    final token = await AuthService.getToken();
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  static dynamic _parse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    String message = 'Ошибка сервера (${res.statusCode})';
    try {
      final body = jsonDecode(res.body) as Map;
      message = body['error'] as String? ?? message;
    } catch (_) {}
    throw ApiException(res.statusCode, message);
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  const ApiException(this.statusCode, this.message);

  @override
  String toString() => message;
}
