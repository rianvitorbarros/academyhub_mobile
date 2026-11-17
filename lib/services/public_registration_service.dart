import 'dart:convert';

import 'package:academyhub_mobile/config/api_config.dart';
import 'package:academyhub_mobile/model/public_enrollment_offer_model.dart';
import 'package:academyhub_mobile/model/public_registration_class_model.dart';
import 'package:http/http.dart' as http;

const bool _visualMockEnabled =
    bool.fromEnvironment('PUBLIC_REGISTRATION_VISUAL_MOCK');

class PublicRegistrationException implements Exception {
  final String message;

  const PublicRegistrationException(this.message);

  @override
  String toString() => message;
}

class PublicRegistrationService {
  Future<PublicRegistrationSchoolContext> fetchPublicContext(
    String schoolId,
  ) async {
    if (_visualMockEnabled) {
      return PublicRegistrationSchoolContext.fromJson(
        {
          'school': {
            'id': schoolId,
            'name': 'Escola Sossego da Mamãe',
            'logoUrl': null,
          },
        },
        fallbackId: schoolId,
      );
    }

    final url = Uri.parse(
      '${ApiConfig.apiUrl}/registration-requests/public/$schoolId/context',
    );

    try {
      final response = await http.get(
        url,
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw PublicRegistrationException(_extractErrorMessage(
          response.body,
          fallback: 'Não foi possível carregar os dados da escola.',
        ));
      }

      final decoded = json.decode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const PublicRegistrationException(
          'Os dados da escola não vieram no formato esperado.',
        );
      }

      final rawLogoUrl = decoded['school'] is Map<String, dynamic>
          ? (decoded['school'] as Map<String, dynamic>)['logoUrl']?.toString()
          : decoded['logoUrl']?.toString();

      return PublicRegistrationSchoolContext.fromJson(
        decoded,
        fallbackId: schoolId,
        resolvedLogoUrl: _resolveLogoUrl(rawLogoUrl),
      );
    } on PublicRegistrationException {
      rethrow;
    } catch (_) {
      throw const PublicRegistrationException(
        'Não conseguimos conectar agora. Tente novamente em instantes.',
      );
    }
  }

  Future<List<PublicRegistrationClassModel>> fetchPublicClasses(
    String schoolId,
  ) async {
    if (_visualMockEnabled) {
      return [
        PublicRegistrationClassModel.fromJson({
          'id': 'mock-class-infantil-1b',
          'name': '1ºB',
          'educationLevel': 'Educação Infantil',
          'grade': '1',
          'shift': 'Matutino',
          'startTime': '07:30',
          'endTime': '12:00',
          'monthlyFee': 350,
          'availabilityStatus': 'available',
        }),
        PublicRegistrationClassModel.fromJson({
          'id': 'mock-class-fundamental-2a',
          'name': '2ºA',
          'educationLevel': 'Ensino Fundamental I',
          'grade': '2',
          'shift': 'Matutino',
          'startTime': '07:30',
          'endTime': '15:20',
          'monthlyFee': 420,
          'availabilityStatus': 'few_slots',
        }),
        PublicRegistrationClassModel.fromJson({
          'id': 'mock-class-fundamental-3c',
          'name': '3ºC',
          'educationLevel': 'Ensino Fundamental I',
          'grade': '3',
          'shift': 'Vespertino',
          'startTime': '13:00',
          'endTime': '17:30',
          'monthlyFee': 390,
          'availabilityStatus': 'unavailable',
        }),
        PublicRegistrationClassModel.fromJson({
          'id': '',
          'name': 'Ensino Médio',
          'educationLevel': 'Ensino Médio',
          'availabilityStatus': 'unavailable',
        }),
      ];
    }

    final url = Uri.parse(
      '${ApiConfig.apiUrl}/registration-requests/public/$schoolId/classes',
    );

    try {
      final response = await http.get(
        url,
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw PublicRegistrationException(_extractErrorMessage(
          response.body,
          fallback: 'Não foi possível carregar as turmas desta escola.',
        ));
      }

      final decoded = json.decode(response.body);
      if (decoded is! List) {
        throw const PublicRegistrationException(
          'A lista de turmas não veio no formato esperado.',
        );
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PublicRegistrationClassModel.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
    } on PublicRegistrationException {
      rethrow;
    } catch (_) {
      throw const PublicRegistrationException(
        'Não conseguimos conectar agora. Tente novamente em instantes.',
      );
    }
  }

  Future<List<PublicEnrollmentOfferModel>> fetchPublicEnrollmentOffers({
    required String schoolId,
    required String classId,
  }) async {
    if (_visualMockEnabled) {
      if (classId == 'mock-class-infantil-1b') {
        return [
          PublicEnrollmentOfferModel.fromJson({
            'id': 'mock-offer-full-time',
            'name': 'Período integral',
            'type': 'full_time',
            'description': 'Rotina ampliada com acompanhamento pedagógico.',
            'startTime': '07:30',
            'endTime': '17:30',
            'monthlyFee': 680,
            'pricingMode': 'total',
            'permanenceClassMode': 'optional',
          }),
        ];
      }
      return const [];
    }

    final url = Uri.parse(
      '${ApiConfig.apiUrl}/registration-requests/public/$schoolId/offers',
    ).replace(queryParameters: {'classId': classId});

    try {
      final response = await http.get(
        url,
        headers: const {'Content-Type': 'application/json'},
      );

      if (response.statusCode != 200) {
        throw PublicRegistrationException(_extractErrorMessage(
          response.body,
          fallback:
              'Não foi possível carregar as opções de permanência desta turma.',
        ));
      }

      final decoded = json.decode(response.body);
      if (decoded is! List) {
        throw const PublicRegistrationException(
          'A lista de opções de permanência não veio no formato esperado.',
        );
      }

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(PublicEnrollmentOfferModel.fromJson)
          .where((item) => item.id.isNotEmpty)
          .toList();
    } on PublicRegistrationException {
      rethrow;
    } catch (_) {
      throw const PublicRegistrationException(
        'Não conseguimos conectar agora. Você pode continuar com meio período ou tentar novamente.',
      );
    }
  }

  /// Sends the request and returns its id (used to attach optional offers).
  Future<String?> submitRegistrationRequest(Map<String, dynamic> data) async {
    if (_visualMockEnabled) {
      // Used only by manual visual validation with --dart-define.
      // ignore: avoid_print
      print('[PublicRegistrationVisualMock] payload=$data');
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return null;
    }

    final url = Uri.parse(
      '${ApiConfig.apiUrl}/registration-requests/public/submit',
    );

    try {
      final response = await http.post(
        url,
        headers: const {'Content-Type': 'application/json'},
        body: json.encode(data),
      );

      if (response.statusCode != 201) {
        throw PublicRegistrationException(_extractErrorMessage(
          response.body,
          fallback: 'Não foi possível enviar a solicitação.',
        ));
      }
      try {
        final decoded = json.decode(response.body);
        return decoded is Map ? decoded['requestId']?.toString() : null;
      } catch (_) {
        return null;
      }
    } on PublicRegistrationException {
      rethrow;
    } catch (_) {
      throw const PublicRegistrationException(
        'Falha de conexão. Confira sua internet e tente novamente.',
      );
    }
  }

  String _extractErrorMessage(
    String responseBody, {
    required String fallback,
  }) {
    try {
      final decoded = json.decode(responseBody);
      if (decoded is Map && decoded['message'] != null) {
        final message = decoded['message'].toString().trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {
      return fallback;
    }

    return fallback;
  }

  String? _resolveLogoUrl(String? rawLogoUrl) {
    final value = rawLogoUrl?.trim();
    if (value == null || value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return value;
    }
    if (value.startsWith('/')) {
      return '${ApiConfig.baseUrl}$value';
    }
    return value;
  }
}
