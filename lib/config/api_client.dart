import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/auth_session_manager.dart';

class ApiClient {
  static final http.Client _defaultClient = http.Client();
  static http.Client? _clientForTesting;

  static http.Client get _client => _clientForTesting ?? _defaultClient;

  @visibleForTesting
  static void setClientForTesting(http.Client? client) {
    _clientForTesting = client;
  }

  static Future<http.Response> _send(
    Future<http.Response> Function(Map<String, String> headers) request,
    Map<String, String>? originalHeaders,
  ) async {
    final headers = Map<String, String>.from(originalHeaders ?? const {});
    final session = AuthSessionManager.instance;
    if (headers.containsKey('Authorization') && session.accessToken != null) {
      headers['Authorization'] = 'Bearer ${session.accessToken}';
    }
    if (session.shouldRefreshSoon && await session.hasRefreshToken()) {
      try {
        final token = await session.refresh();
        headers['Authorization'] = 'Bearer $token';
      } on SessionRefreshException catch (error) {
        if (error.sessionInvalid) rethrow;
      }
    }

    var response = await request(headers);
    if (response.statusCode != 401 || !headers.containsKey('Authorization')) {
      return response;
    }

    try {
      final token = await session.refresh(force: true);
      headers['Authorization'] = 'Bearer $token';
      response = await request(headers);
      return response;
    } on SessionRefreshException catch (error) {
      if (error.sessionInvalid) rethrow;
      return response;
    }
  }

  static Future<http.Response> get(Uri url, {Map<String, String>? headers}) =>
      _send((resolved) => _client.get(url, headers: resolved), headers);

  static Future<http.Response> post(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _send(
          (resolved) => _client.post(url,
              headers: resolved, body: body, encoding: encoding),
          headers);

  static Future<http.Response> put(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _send(
          (resolved) => _client.put(url,
              headers: resolved, body: body, encoding: encoding),
          headers);

  static Future<http.Response> patch(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _send(
          (resolved) => _client.patch(url,
              headers: resolved, body: body, encoding: encoding),
          headers);

  static Future<http.Response> delete(Uri url,
          {Map<String, String>? headers, Object? body, Encoding? encoding}) =>
      _send(
          (resolved) => _client.delete(url,
              headers: resolved, body: body, encoding: encoding),
          headers);
}
