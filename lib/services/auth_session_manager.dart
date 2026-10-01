import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';

class SessionRefreshException implements Exception {
  final String message;
  final bool sessionInvalid;
  const SessionRefreshException(this.message, {this.sessionInvalid = false});
  @override
  String toString() => message;
}

class AuthSessionManager {
  AuthSessionManager._();
  static final instance = AuthSessionManager._();

  static const _accessKey = 'authToken';
  static const _expiryKey = 'authTokenExpiresAt';
  static const _refreshKey = 'staffRefreshToken';
  static const _pendingLogoutKey = 'pendingStaffLogoutTokens';
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  String? _accessToken;
  DateTime? _expiresAt;
  Future<String>? _refreshInFlight;
  Future<void>? _pendingLogoutRetry;
  Future<String> Function({bool force})? _refreshForTesting;
  Future<bool> Function()? _hasRefreshTokenForTesting;
  void Function(String?)? onAccessTokenChanged;
  void Function()? onSessionInvalid;
  void Function()? onSessionRenewed;

  String? get accessToken => _accessToken;

  Future<void> restore() async {
    final prefs = await SharedPreferences.getInstance();
    _accessToken = prefs.getString(_accessKey);
    _expiresAt = DateTime.tryParse(prefs.getString(_expiryKey) ?? '');
    _expiresAt ??= _readJwtExpiry(_accessToken);
    unawaited(retryPendingLogouts());
  }

  Future<void> saveLogin(Map<String, dynamic> response) async {
    unawaited(retryPendingLogouts());
    final token = response['token']?.toString();
    final refreshToken = response['refreshToken']?.toString();
    if (token == null || token.isEmpty) {
      throw const SessionRefreshException(
          'Resposta de autenticacao sem token.');
    }
    _accessToken = token;
    _expiresAt =
        DateTime.tryParse(response['accessTokenExpiresAt']?.toString() ?? '') ??
            _readJwtExpiry(token);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_accessKey, token);
    if (_expiresAt != null) {
      await prefs.setString(_expiryKey, _expiresAt!.toIso8601String());
    }
    if (refreshToken != null && refreshToken.isNotEmpty) {
      await _secureStorage.write(key: _refreshKey, value: refreshToken);
    } else {
      await _secureStorage.delete(key: _refreshKey);
    }
    onAccessTokenChanged?.call(token);
  }

  bool get shouldRefreshSoon {
    final expiry = _expiresAt;
    return expiry != null &&
        expiry.isBefore(DateTime.now().add(const Duration(minutes: 2)));
  }

  Future<bool> hasRefreshToken() async =>
      _hasRefreshTokenForTesting?.call() ??
      (await _secureStorage.read(key: _refreshKey))?.isNotEmpty == true;

  Future<String> refresh({bool force = false}) {
    final refreshForTesting = _refreshForTesting;
    if (refreshForTesting != null) return refreshForTesting(force: force);
    if (!force && !shouldRefreshSoon && _accessToken != null) {
      return Future.value(_accessToken!);
    }
    return _refreshInFlight ??=
        _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  @visibleForTesting
  void configureForTesting({
    String? accessToken,
    DateTime? expiresAt,
    Future<String> Function({bool force})? refresh,
    Future<bool> Function()? hasRefreshToken,
  }) {
    _accessToken = accessToken;
    _expiresAt = expiresAt;
    _refreshForTesting = refresh;
    _hasRefreshTokenForTesting = hasRefreshToken;
  }

  @visibleForTesting
  void resetTestingConfiguration() {
    _accessToken = null;
    _expiresAt = null;
    _refreshForTesting = null;
    _hasRefreshTokenForTesting = null;
  }

  Future<String> _performRefresh() async {
    final refreshToken = await _secureStorage.read(key: _refreshKey);
    if (refreshToken == null || refreshToken.isEmpty) {
      throw const SessionRefreshException(
          'Sua sessão expirou. Entre novamente para continuar. '
          'Suas alterações já salvas foram preservadas.',
          sessionInvalid: true);
    }
    http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('${ApiConfig.apiUrl}/auth/refresh'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw const SessionRefreshException('Sem conexao para renovar a sessao.');
    }
    if (response.statusCode == 200) {
      final data = Map<String, dynamic>.from(
          jsonDecode(utf8.decode(response.bodyBytes)));
      await saveLogin(data);
      onSessionRenewed?.call();
      return _accessToken!;
    }
    if (response.statusCode == 400 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      await clearTokens();
      onSessionInvalid?.call();
      throw const SessionRefreshException(
          'Sua sessão expirou. Entre novamente para continuar. '
          'Suas alterações já salvas foram preservadas.',
          sessionInvalid: true);
    }
    throw const SessionRefreshException(
        'Servidor temporariamente indisponivel.');
  }

  Future<void> logoutRemote() async {
    final refreshToken = await _secureStorage.read(key: _refreshKey);
    if (refreshToken == null) return;
    try {
      final response = await http
          .post(
            Uri.parse('${ApiConfig.apiUrl}/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              if (_accessToken != null) 'Authorization': 'Bearer $_accessToken',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(const Duration(seconds: 5));
      if (response.statusCode < 200 || response.statusCode >= 500) {
        await _rememberPendingLogout(refreshToken);
      }
    } catch (_) {
      await _rememberPendingLogout(refreshToken);
    }
  }

  Future<void> retryPendingLogouts() =>
      _pendingLogoutRetry ??= _performPendingLogoutRetry()
          .whenComplete(() => _pendingLogoutRetry = null);

  Future<void> _performPendingLogoutRetry() async {
    final pending = await _readPendingLogouts();
    if (pending.isEmpty) return;
    final remaining = <String>[];
    for (final token in pending) {
      try {
        final response = await http
            .post(
              Uri.parse('${ApiConfig.apiUrl}/auth/logout'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'refreshToken': token}),
            )
            .timeout(const Duration(seconds: 5));
        if (response.statusCode >= 500) remaining.add(token);
      } catch (_) {
        remaining.add(token);
      }
    }
    await _secureStorage.write(
      key: _pendingLogoutKey,
      value: jsonEncode(remaining),
    );
  }

  Future<void> _rememberPendingLogout(String token) async {
    final retry = _pendingLogoutRetry;
    if (retry != null) await retry;
    final pending = await _readPendingLogouts();
    if (!pending.contains(token)) pending.add(token);
    await _secureStorage.write(
      key: _pendingLogoutKey,
      value: jsonEncode(pending),
    );
  }

  Future<List<String>> _readPendingLogouts() async {
    try {
      final raw = await _secureStorage.read(key: _pendingLogoutKey);
      if (raw == null) return [];
      return (jsonDecode(raw) as List).map((item) => item.toString()).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> clearTokens() async {
    _accessToken = null;
    _expiresAt = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessKey);
    await prefs.remove(_expiryKey);
    await _secureStorage.delete(key: _refreshKey);
    onAccessTokenChanged?.call(null);
  }

  DateTime? _readJwtExpiry(String? token) {
    try {
      if (token == null) return null;
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final exp = payload['exp'];
      return exp is num
          ? DateTime.fromMillisecondsSinceEpoch(exp.toInt() * 1000)
          : null;
    } catch (_) {
      return null;
    }
  }
}
