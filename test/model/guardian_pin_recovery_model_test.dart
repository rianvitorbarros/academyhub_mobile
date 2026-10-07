import 'package:academyhub_mobile/model/guardian_auth_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a PIN recovery challenge ready for completion', () {
    final result = GuardianPinRecoveryStartResult.fromJson({
      'challengeId': 'challenge-1',
      'verificationToken': 'token-1',
      'expiresInSeconds': 900,
      'schoolSelectionRequired': false,
    });

    expect(result.isReadyForPin, isTrue);
    expect(result.expiresInSeconds, 900);
    expect(result.options, isEmpty);
  });

  test('parses school selection without exposing guardian data', () {
    final result = GuardianPinRecoveryStartResult.fromJson({
      'schoolSelectionRequired': true,
      'options': [
        {
          'schoolPublicId': 'sementinha',
          'schoolName': 'Escola Sementinha',
        },
      ],
    });

    expect(result.isReadyForPin, isFalse);
    expect(result.options, hasLength(1));
    expect(result.options.single.schoolPublicId, 'sementinha');
    expect(result.options.single.schoolName, 'Escola Sementinha');
  });

  test('classifies recovery errors without exposing recovery credentials', () {
    const limited = GuardianPinRecoveryException(
      'limit',
      code: 'pin_recovery_rate_limited',
      statusCode: 429,
    );
    const expired = GuardianPinRecoveryException(
      'expired',
      code: 'pin_recovery_challenge_expired',
      statusCode: 410,
    );
    const consumed = GuardianPinRecoveryException(
      'used',
      code: 'pin_recovery_challenge_used',
      statusCode: 409,
    );
    const unavailable = GuardianPinRecoveryException(
      'unavailable',
      code: 'guardian_audit_transaction_unavailable',
      statusCode: 503,
    );

    expect(limited.isRateLimited, isTrue);
    expect(limited.isExpired, isFalse);
    expect(expired.isExpired, isTrue);
    expect(consumed.requiresRestart, isTrue);
    expect(unavailable.requiresRestart, isFalse);
    expect(unavailable.isTemporarilyUnavailable, isTrue);
  });

  test('parses successful PIN recovery without credential data', () {
    final result = GuardianPinRecoveryResult.fromJson({
      'status': 'pin_updated',
      'identifierType': 'cpf',
      'identifierMasked': '***.***.***-09',
      'message': 'PIN atualizado.',
    });

    expect(result.isSuccess, isTrue);
    expect(result.identifierMasked, '***.***.***-09');
    expect(result.toString(), isNot(contains('654321')));
  });
}
