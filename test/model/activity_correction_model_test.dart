import 'package:academyhub_mobile/model/activity_correction_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses an activity print run with pending and corrected students', () {
    final run = ActivityCorrectionPrintRun.fromJson({
      'id': 'run-1',
      'activityPageId': 'page-1',
      'bookTitle': 'Caderno de Ava. Gleice',
      'activityTitle': 'Pagina 1',
      'subject': 'Multidisciplinar',
      'totalStudents': 2,
      'pendingCount': 1,
      'correctedCount': 1,
      'students': [
        {
          'studentId': 'student-1',
          'studentName': 'Alessa Duarte Lima',
          'qrCodePayload': 'AH-ACTIVITY-1:one',
          'status': 'pending',
        },
        {
          'studentId': 'student-2',
          'studentName': 'Amanda Sousa Melo',
          'qrCodePayload': 'AH-ACTIVITY-1:two',
          'status': 'corrected',
        },
      ],
    });

    expect(run.bookTitle, 'Caderno de Ava. Gleice');
    expect(run.pendingCount, 1);
    expect(run.correctedCount, 1);
    expect(run.students.first.isPending, isTrue);
    expect(run.students.last.isPending, isFalse);
  });
}
