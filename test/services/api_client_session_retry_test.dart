import 'package:academyhub_mobile/config/api_client.dart';
import 'package:academyhub_mobile/services/auth_session_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final session = AuthSessionManager.instance;

  tearDown(() {
    ApiClient.setClientForTesting(null);
    session.resetTestingConfiguration();
  });

  test('uses a valid access token without refreshing the request', () async {
    var refreshCalls = 0;
    ApiClient.setClientForTesting(MockClient((request) async {
      expect(request.headers['authorization'], 'Bearer valid-access-token');
      return http.Response('{"ok":true}', 200);
    }));
    session.configureForTesting(
      accessToken: 'valid-access-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      hasRefreshToken: () async => true,
      refresh: ({bool force = false}) async {
        refreshCalls++;
        return 'unexpected-refresh';
      },
    );

    final response = await ApiClient.patch(
      Uri.parse(
          'https://example.test/api/report-cards/report-1/recalculate-status'),
      headers: const {'Authorization': 'Bearer stale-token'},
    );

    expect(response.statusCode, 200);
    expect(refreshCalls, 0);
  });

  test('refreshes once and retries a rejected report-card request once',
      () async {
    var requestCalls = 0;
    var refreshCalls = 0;
    final authorizationHeaders = <String?>[];
    ApiClient.setClientForTesting(MockClient((request) async {
      requestCalls++;
      authorizationHeaders.add(request.headers['authorization']);
      return requestCalls == 1
          ? http.Response('{"message":"Sessao invalida ou expirada."}', 401)
          : http.Response('{"ok":true}', 200);
    }));
    session.configureForTesting(
      accessToken: 'expired-access-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      hasRefreshToken: () async => true,
      refresh: ({bool force = false}) async {
        expect(force, isTrue);
        refreshCalls++;
        return 'renewed-access-token';
      },
    );

    final response = await ApiClient.patch(
      Uri.parse(
          'https://example.test/api/report-cards/report-1/recalculate-status'),
      headers: const {'Authorization': 'Bearer expired-access-token'},
    );

    expect(response.statusCode, 200);
    expect(refreshCalls, 1);
    expect(requestCalls, 2);
    expect(authorizationHeaders,
        ['Bearer expired-access-token', 'Bearer renewed-access-token']);
  });

  test('does not retry when refresh token is invalid', () async {
    var requestCalls = 0;
    ApiClient.setClientForTesting(MockClient((_) async {
      requestCalls++;
      return http.Response('{"message":"Sessao invalida ou expirada."}', 401);
    }));
    session.configureForTesting(
      accessToken: 'expired-access-token',
      expiresAt: DateTime.now().add(const Duration(minutes: 10)),
      hasRefreshToken: () async => true,
      refresh: ({bool force = false}) async =>
          throw const SessionRefreshException(
        'Sessao expirada.',
        sessionInvalid: true,
      ),
    );

    await expectLater(
      () => ApiClient.patch(
        Uri.parse(
            'https://example.test/api/report-cards/report-1/recalculate-status'),
        headers: const {'Authorization': 'Bearer expired-access-token'},
      ),
      throwsA(isA<SessionRefreshException>()),
    );
    expect(requestCalls, 1);
  });
}
