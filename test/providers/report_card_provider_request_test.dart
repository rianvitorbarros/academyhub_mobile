import 'dart:async';

import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:academyhub_mobile/providers/report_card_provider.dart';
import 'package:academyhub_mobile/services/report_card_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resposta antiga não substitui boletins da turma mais recente',
      () async {
    final service = _ControlledReportCardService();
    final provider = ReportCardProvider(service: service);

    final first = provider.generateClassReportCards(
      token: 'test',
      classId: 'class-1',
      termId: 'term-1',
      schoolYear: 2026,
    );
    final second = provider.generateClassReportCards(
      token: 'test',
      classId: 'class-2',
      termId: 'term-1',
      schoolYear: 2026,
    );
    service.requests['class-2']!.complete([_card('class-2')]);
    await second;
    service.requests['class-1']!.complete([_card('class-1')]);
    await first;

    expect(provider.classReportCards.map((item) => item.classId), ['class-2']);
    expect(provider.isGenerating, isFalse);
  });

  test('falha de API aparece como erro e não mantém boletins de outra turma',
      () async {
    final service = _ControlledReportCardService();
    final provider = ReportCardProvider(service: service);

    final first = provider.generateClassReportCards(
      token: 'test',
      classId: 'class-1',
      termId: 'term-1',
      schoolYear: 2026,
    );
    service.requests['class-1']!.complete([_card('class-1')]);
    await first;

    final second = provider.generateClassReportCards(
      token: 'test',
      classId: 'class-2',
      termId: 'term-1',
      schoolYear: 2026,
    );
    expect(provider.classReportCards, isEmpty);
    service.requests['class-2']!.completeError(Exception('HTTP 500'));
    await expectLater(second, throwsException);
    expect(provider.errorMessage, contains('HTTP 500'));
    expect(provider.classReportCards, isEmpty);
  });
}

class _ControlledReportCardService extends ReportCardService {
  _ControlledReportCardService() : super(baseUrl: 'https://example.test');

  final requests = <String, Completer<List<ReportCardModel>>>{};

  @override
  Future<List<ReportCardModel>> generateClassReportCards({
    required String token,
    required String classId,
    required String termId,
    required int schoolYear,
  }) {
    final request = Completer<List<ReportCardModel>>();
    requests[classId] = request;
    return request.future;
  }
}

ReportCardModel _card(String classId) => ReportCardModel(
      id: 'card-$classId',
      schoolId: 'school-1',
      schoolYear: 2026,
      termId: 'term-1',
      classId: classId,
      studentId: 'student-1',
      enrollmentId: 'enrollment-1',
      gradingType: 'numeric',
      minimumAverage: 6,
      status: 'Rascunho',
      responsibleNameSnapshot: '',
      generalObservation: '',
      subjects: const [],
      releasedForPrint: false,
    );
