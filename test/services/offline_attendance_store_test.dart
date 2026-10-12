import 'package:academyhub_mobile/model/attendance_model.dart';
import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/services/offline_attendance_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AttendanceSheet _sheet(String classId) => AttendanceSheet(
      classId: classId,
      date: DateTime(2026, 8, 13),
      version: 4,
      records: [
        AttendanceRecord(
          studentId: 'student-1',
          studentName: 'Aluno Teste',
          status: 'ABSENT',
          observation: 'Teste offline',
        ),
      ],
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    OfflineAttendanceStore.instance.deactivate();
  });

  test('persists complete operation and advances optimistic queue versions',
      () async {
    final store = OfflineAttendanceStore.instance;
    store.activate(userId: 'teacher-1', schoolId: 'school-1');

    final first = await store.enqueue(_sheet('class-1'));
    final second = await store.enqueue(_sheet('class-1'));
    final pending = await store.pendingOperations();

    expect(first.operationId, isNot(second.operationId));
    expect(first.baseVersion, 4);
    expect(second.baseVersion, 5);
    expect(pending, hasLength(2));
    expect(pending.first.userId, 'teacher-1');
    expect(pending.first.schoolId, 'school-1');
    expect(pending.first.records.single['status'], 'ABSENT');
  });

  test('isolates cached attendance by user and school', () async {
    final store = OfflineAttendanceStore.instance;
    store.activate(userId: 'teacher-1', schoolId: 'school-1');
    await store.saveSheet(_sheet('class-1'));
    final restored = await store.loadSheet('class-1', DateTime(2026, 8, 13));
    expect(restored, isNotNull);
    expect(restored!.records.single.studentName, 'Aluno Teste');

    final futureDay = await store.loadSheet('class-1', DateTime(2026, 8, 14));
    expect(futureDay, isNotNull);
    expect(futureDay!.version, 0);
    expect(futureDay.records.single.status, 'PRESENT');

    store.activate(userId: 'teacher-2', schoolId: 'school-1');
    expect(await store.loadSheet('class-1', DateTime(2026, 8, 13)), isNull);

    store.activate(userId: 'teacher-1', schoolId: 'school-2');
    expect(await store.loadSheet('class-1', DateTime(2026, 8, 13)), isNull);
  });

  test('explicit resubmission replaces a local conflict', () async {
    final store = OfflineAttendanceStore.instance;
    store.activate(userId: 'teacher-1', schoolId: 'school-1');
    final original = await store.enqueue(_sheet('class-1'));
    await store.markFailure(original.operationId, 'Conflito', conflict: true);

    final replacement = await store.enqueue(_sheet('class-1'));
    final pending = await store.pendingOperations();

    expect(pending, hasLength(1));
    expect(pending.single.operationId, replacement.operationId);
    expect(replacement.baseVersion, 4);
  });

  test('isolates teacher class cache by academic year and user', () async {
    final store = OfflineAttendanceStore.instance;
    store.activate(userId: 'teacher-1', schoolId: 'school-1');
    await store.saveClasses(
      [_class('class-2026')],
      scope: 'teacher_year-2026',
    );

    expect(
      (await store.loadClasses(scope: 'teacher_year-2026')).single.id,
      'class-2026',
    );
    expect(await store.loadClasses(scope: 'teacher_year-2025'), isEmpty);

    store.activate(userId: 'teacher-2', schoolId: 'school-1');
    expect(await store.loadClasses(scope: 'teacher_year-2026'), isEmpty);
  });
}

ClassModel _class(String id) => ClassModel(
      id: id,
      name: id,
      schoolYear: 2026,
      grade: '1º ano',
      shift: 'Matutino',
      monthlyFee: 0,
      status: 'Ativa',
      studentCount: 0,
      schoolId: 'school-1',
    );
