import 'package:academyhub_mobile/model/re_enrollment_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GuardianReEnrollmentItem item(String state,
          {Map<String, dynamic>? request}) =>
      GuardianReEnrollmentItem.fromJson({
        'student': {'id': 'student-1', 'fullName': 'Maria Eduarda'},
        'targetAcademicYear': 2027,
        'eligibility': state,
        'currentEnrollment': {
          'class': {'name': '5º Ano A', 'grade': '5º Ano'}
        },
        'suggestedNextGrade': {'grade': '6º Ano'},
        'request': request,
      });

  test('maps the eligible, financial-block and missing-progression states', () {
    expect(item('ELIGIBLE').canRequest, isTrue);
    expect(item('FINANCIAL_BLOCK').financialBlocked, isTrue);
    expect(item('NO_ACADEMIC_PROGRESSION').progressionMissing, isTrue);
  });

  test('preserves an approved/rejected request and public rejection reason',
      () {
    final rejected = item('REJECTED', request: {
      'status': 'REJECTED',
      'rejectionReason': 'Documentação pendente'
    });
    expect(rejected.rejectionReason, 'Documentação pendente');
    expect(rejected.targetLabel, '6º Ano');
  });
}
