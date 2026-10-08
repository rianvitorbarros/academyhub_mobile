import 'dart:convert';
import 'package:academyhub_mobile/config/api_config.dart';
import 'package:academyhub_mobile/model/re_enrollment_model.dart';
import 'package:http/http.dart' as http;

class ReEnrollmentService {
  final http.Client _client;
  ReEnrollmentService({http.Client? client})
      : _client = client ?? http.Client();
  Future<GuardianReEnrollmentEligibility> getEligibility(String token) async {
    final response = await _client.get(
        Uri.parse('${ApiConfig.apiUrl}/guardian/re-enrollments/eligibility'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        });
    final payload = jsonDecode(utf8.decode(response.bodyBytes).isEmpty
        ? '{}'
        : utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    if (response.statusCode >= 200 && response.statusCode < 300)
      return GuardianReEnrollmentEligibility.fromJson(payload);
    throw Exception(payload['message']?.toString() ??
        'Não foi possível consultar as rematrículas.');
  }

  Future<void> createRequest(
      {required String token, required String studentId}) async {
    final response = await _client.post(
        Uri.parse('${ApiConfig.apiUrl}/guardian/re-enrollments'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token'
        },
        body: jsonEncode({'studentId': studentId}));
    if (response.statusCode >= 200 && response.statusCode < 300) return;
    final payload = jsonDecode(utf8.decode(response.bodyBytes).isEmpty
        ? '{}'
        : utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
    throw Exception(payload['message']?.toString() ??
        'Não foi possível enviar a solicitação.');
  }
}
