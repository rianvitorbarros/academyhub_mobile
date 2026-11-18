import 'dart:convert';

import 'package:academyhub_mobile/config/api_config.dart';
import 'package:academyhub_mobile/model/early_payment_offer_model.dart';
import 'package:http/http.dart' as http;

class EarlyPaymentOfferService {
  EarlyPaymentOfferService({http.Client? client})
      : _client = client ?? http.Client();
  final http.Client _client;

  Map<String, String> _headers([String? token]) => {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  dynamic _decode(http.Response response, String fallback) {
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {}
    if (response.statusCode >= 200 && response.statusCode < 300) return data;
    throw Exception(
        data is Map && data['message'] != null ? data['message'] : fallback);
  }

  List<EarlyPaymentOffer> _items(dynamic data) => data is Map
      ? ((data['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => EarlyPaymentOffer.fromJson(Map<String, dynamic>.from(e)))
          .toList()
      : const [];

  /// Ofertas visíveis no link público de matrícula.
  Future<List<EarlyPaymentOffer>> publicOffers(String schoolId) async {
    final response = await _client
        .get(
            Uri.parse(
                    '${ApiConfig.apiUrl}/public/early-payment-offers/$schoolId')
                .replace(queryParameters: {'audience': 'NEW_ENROLLMENT'}),
            headers: _headers())
        .timeout(const Duration(seconds: 12));
    return _items(_decode(response, 'Não foi possível carregar as ofertas.'));
  }

  /// Price of the chosen class with the discount, when the school already
  /// published next year's fees. Returns null amounts otherwise.
  Future<EarlyPaymentQuote> publicQuote(String schoolId, String offerId,
      {required String level,
      required String grade,
      required String shift}) async {
    final response = await _client
        .get(
            Uri.parse(
                    '${ApiConfig.apiUrl}/public/early-payment-offers/$schoolId/$offerId/simulate')
                .replace(queryParameters: {
              'level': level,
              'grade': grade,
              'shift': shift,
            }),
            headers: _headers())
        .timeout(const Duration(seconds: 12));
    final data = _decode(response, 'Não foi possível calcular o desconto.');
    return EarlyPaymentQuote.fromJson(
        data is Map ? Map<String, dynamic>.from(data) : const {});
  }

  Future<void> publicAdhesion(
      String schoolId, String offerId, Map<String, dynamic> payload) async {
    final response = await _client
        .post(
            Uri.parse(
                '${ApiConfig.apiUrl}/public/early-payment-offers/$schoolId/$offerId/adhesions'),
            headers: _headers(),
            body: jsonEncode(payload))
        .timeout(const Duration(seconds: 20));
    _decode(response, 'Não foi possível registrar o interesse.');
  }

  /// Ofertas da rematrícula, já com o valor calculado por aluno.
  Future<List<EarlyPaymentOffer>> guardianOffers(String token) async {
    final response = await _client
        .get(Uri.parse('${ApiConfig.apiUrl}/guardian/early-payment-offers'),
            headers: _headers(token))
        .timeout(const Duration(seconds: 15));
    return _items(_decode(response, 'Não foi possível carregar as ofertas.'));
  }

  Future<void> guardianAdhesion(
      String token, String offerId, String studentId) async {
    final response = await _client
        .post(
            Uri.parse(
                '${ApiConfig.apiUrl}/guardian/early-payment-offers/$offerId/adhesions'),
            headers: _headers(token),
            body: jsonEncode({'studentId': studentId}))
        .timeout(const Duration(seconds: 20));
    _decode(response, 'Não foi possível registrar a adesão.');
  }
}
