import 'package:academyhub_mobile/util/report_card_filter_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('cache antigo é ignorado e filtros ficam isolados por sessão', () async {
    SharedPreferences.setMockInitialValues({
      'report_cards.filters.v1.school-1.teacher-1':
          '{"classId":"obsolete-class"}',
    });

    expect(
      await ReportCardFilterStore.load(
        userId: 'teacher-1',
        schoolId: 'school-1',
      ),
      isEmpty,
    );

    await ReportCardFilterStore.save(
      userId: 'teacher-1',
      schoolId: 'school-1',
      year: '2026',
      term: '2º Bimestre',
      classId: 'class-8',
      status: 'Todos',
    );

    final restored = await ReportCardFilterStore.load(
      userId: 'teacher-1',
      schoolId: 'school-1',
    );
    expect(restored['classId'], 'class-8');
    expect(restored['term'], '2º Bimestre');
    expect(
      await ReportCardFilterStore.load(
        userId: 'teacher-2',
        schoolId: 'school-1',
      ),
      isEmpty,
    );
    expect(
      await ReportCardFilterStore.load(
        userId: 'teacher-1',
        schoolId: 'school-2',
      ),
      isEmpty,
    );
  });
}
