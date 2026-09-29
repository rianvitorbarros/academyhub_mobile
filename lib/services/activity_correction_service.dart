import 'dart:convert';

import 'package:academyhub_mobile/config/api_config.dart';
import 'package:academyhub_mobile/model/activity_correction_model.dart';
import 'package:http/http.dart' as http;

class ActivityCorrectionException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const ActivityCorrectionException(
    this.message, {
    this.code,
    this.statusCode,
  });

  @override
  String toString() => message;
}

class ActivityCorrectionService {
  final String _baseUrl = '${ApiConfig.apiUrl}/school/activity-corrections';

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  ActivityCorrectionException _buildException(http.Response response) {
    try {
      final body = json.decode(utf8.decode(response.bodyBytes));
      if (body is Map<String, dynamic>) {
        return ActivityCorrectionException(
          '${body['message'] ?? 'Erro ao processar correção da atividade.'}',
          code: body['code']?.toString(),
          statusCode: response.statusCode,
        );
      }
    } catch (_) {}

    return ActivityCorrectionException(
      'Erro ao processar correção da atividade.',
      statusCode: response.statusCode,
    );
  }

  Future<ActivityQrResolveResult> resolveQr({
    required String token,
    required String qrCodePayload,
  }) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/resolve'),
      headers: _headers(token),
      body: jsonEncode({'qrCodePayload': qrCodePayload}),
    );

    if (response.statusCode == 200) {
      return ActivityQrResolveResult.fromJson(
        Map<String, dynamic>.from(
          json.decode(utf8.decode(response.bodyBytes)) as Map,
        ),
      );
    }

    throw _buildException(response);
  }

  Future<List<ActivityCorrectionPrintRun>> listPrintRunsForCorrection({
    required String token,
    required String classId,
    required String termId,
    String? subject,
  }) async {
    final query = <String, String>{
      'classId': classId,
      'termId': termId,
      if ((subject ?? '').trim().isNotEmpty) 'subject': subject!.trim(),
    };
    final response = await http.get(
      Uri.parse('$_baseUrl/print-runs').replace(queryParameters: query),
      headers: _headers(token),
    );

    if (response.statusCode == 200) {
      final body = Map<String, dynamic>.from(
        json.decode(utf8.decode(response.bodyBytes)) as Map,
      );
      return (body['items'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ActivityCorrectionPrintRun.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false);
    }

    throw _buildException(response);
  }

  Future<ActivityCorrectionRecord> createCorrection({
    required String token,
    required String qrCodePayload,
    required List<ActivityCorrectionCriterionValue> criteria,
    String? generalObservation,
  }) async {
    final response = await http.post(
      Uri.parse(_baseUrl),
      headers: _headers(token),
      body: jsonEncode({
        'qrCodePayload': qrCodePayload,
        'criteria': criteria.map((item) => item.toRequestJson()).toList(),
        'generalObservation': generalObservation ?? '',
      }),
    );

    if (response.statusCode == 201 || response.statusCode == 200) {
      final body = Map<String, dynamic>.from(
        json.decode(utf8.decode(response.bodyBytes)) as Map,
      );
      return ActivityCorrectionRecord.fromJson(
        Map<String, dynamic>.from(body['correction'] as Map? ?? const {}),
      );
    }

    throw _buildException(response);
  }

  Future<ActivityCorrectionRecord> updateCorrection({
    required String token,
    required String correctionId,
    required List<ActivityCorrectionCriterionValue> criteria,
    String? generalObservation,
  }) async {
    final response = await http.patch(
      Uri.parse('$_baseUrl/$correctionId'),
      headers: _headers(token),
      body: jsonEncode({
        'criteria': criteria.map((item) => item.toRequestJson()).toList(),
        'generalObservation': generalObservation ?? '',
      }),
    );

    if (response.statusCode == 200) {
      final body = Map<String, dynamic>.from(
        json.decode(utf8.decode(response.bodyBytes)) as Map,
      );
      return ActivityCorrectionRecord.fromJson(
        Map<String, dynamic>.from(body['correction'] as Map? ?? const {}),
      );
    }

    throw _buildException(response);
  }
}
