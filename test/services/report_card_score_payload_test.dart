import 'dart:convert';

import 'package:academyhub_mobile/config/api_client.dart';
import 'package:academyhub_mobile/services/report_card_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  tearDown(() => ApiClient.setClientForTesting(null));

  test('atividade isolada envia null explícito e lê nota persistida', () async {
    ApiClient.setClientForTesting(MockClient((request) async {
      expect(request.method, 'PATCH');
      expect(request.url.path,
          '/api/report-cards/card-1/subjects/subject-1/score');
      expect(jsonDecode(request.body), {
        'observation': '',
        'testScore': null,
        'activityScore': 7.5,
        'participationScore': null,
      });
      return http.Response(
          jsonEncode({
            'data': {
              '_id': 'card-1',
              'subjects': [
                {
                  'subjectId': 'subject-1',
                  'subjectNameSnapshot': 'Educação Física',
                  'testScore': null,
                  'activityScore': 7.5,
                  'participationScore': null,
                  'score': 7.5,
                }
              ],
            }
          }),
          200);
    }));

    final card = await ReportCardService(baseUrl: 'https://example.test')
        .updateTeacherSubjectScore(
      token: 'test',
      reportCardId: 'card-1',
      subjectId: 'subject-1',
      activityScore: 7.5,
    );
    expect(card.subjects.single.activityScore, 7.5);
    expect(card.subjects.single.testScore, isNull);
    expect(card.subjects.single.score, 7.5);
  });
}
