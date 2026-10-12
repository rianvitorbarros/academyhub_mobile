import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/evento_model.dart';
import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/model/subject_model.dart';
import 'package:academyhub_mobile/model/term_model.dart';
import 'package:academyhub_mobile/model/user_model.dart';
import 'package:academyhub_mobile/util/teacher_class_context_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final today = DateTime(2026, 7, 3);
  final currentTerm = _term(
    id: 'term-current',
    start: DateTime(2026, 7, 1),
    end: DateTime(2026, 8, 31),
  );
  final previousTerm = _term(
    id: 'term-previous',
    start: DateTime(2026, 3, 1),
    end: DateTime(2026, 6, 30),
  );
  final nextTerm = _term(
    id: 'term-next',
    start: DateTime(2026, 9, 1),
    end: DateTime(2026, 10, 31),
  );
  final teacher = _user(id: 'teacher-1', schoolId: 'school-1');

  group('política de período do professor', () {
    test('usa o período atual para a agenda', () {
      final current = _schedule(
        id: 'schedule-current',
        termId: currentTerm.id,
      );
      final previous = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
      );

      final agenda = TeacherClassContextHelper.agendaHorarios(
        [previous, current],
        [previousTerm, currentTerm],
        user: teacher,
        now: today,
      );

      expect(agenda.map((item) => item.id), ['schedule-current']);
    });

    test('resolve o último período encerrado quando não há período atual', () {
      final reference = TeacherClassContextHelper.getReferenceTerm(
        [nextTerm, previousTerm],
        now: today,
      );

      expect(reference?.id, previousTerm.id);
    });

    test('usa o próximo período quando não existe período encerrado', () {
      final reference = TeacherClassContextHelper.getReferenceTerm(
        [nextTerm],
        now: today,
      );

      expect(reference?.id, nextTerm.id);
    });

    test('mantém turmas por período de referência fora do período letivo', () {
      final schedule = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
      );

      final assigned = TeacherClassContextHelper.assignedHorarios(
        [schedule],
        [previousTerm, nextTerm],
        user: teacher,
        now: today,
      );

      expect(assigned, [schedule]);
    });

    test('fora do período letivo a agenda de hoje continua vazia', () {
      final schedule = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
      );

      final agenda = TeacherClassContextHelper.agendaHorarios(
        [schedule],
        [previousTerm, nextTerm],
        user: teacher,
        now: today,
      );

      expect(agenda, isEmpty);
    });

    test('grade vazia no período atual usa grade anterior para vínculos', () {
      final previous = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
      );

      final assigned = TeacherClassContextHelper.assignedHorarios(
        [previous],
        [previousTerm, currentTerm, nextTerm],
        user: teacher,
        now: today,
      );

      expect(assigned, [previous]);
    });
  });

  group('isolamento e deduplicação dos vínculos', () {
    test('boletim mantém dez turmas quando só uma tem horário no período atual',
        () {
      final previousSchedules = List.generate(
        10,
        (index) => _schedule(
          id: 'previous-$index',
          termId: previousTerm.id,
          classId: 'class-$index',
        ),
      );
      final currentSchedule = _schedule(
        id: 'current',
        termId: currentTerm.id,
        classId: 'class-0',
      );
      final schedules = [...previousSchedules, currentSchedule];
      final classes = List.generate(10, (index) => _class(id: 'class-$index'));

      final periodOnly = TeacherClassContextHelper.getAvailableClasses(
        classes: classes,
        horarios: schedules,
        user: teacher,
        terms: [previousTerm, currentTerm],
      );
      final reportCardOptions = TeacherClassContextHelper.getAvailableClasses(
        classes: classes,
        horarios: schedules,
        user: teacher,
        terms: [previousTerm, currentTerm],
        sharedAcrossPeriods: true,
      );

      expect(periodOnly, hasLength(1));
      expect(reportCardOptions.map((item) => item.id).toSet(), hasLength(10));
    });
    test(
        'modo compartilhado preserva sete turmas quando o período atual tem duas',
        () {
      final previousSchedules = List.generate(
        7,
        (index) => _schedule(
          id: 'previous-${index + 1}',
          termId: previousTerm.id,
          classId: 'class-${index + 1}',
        ),
      );
      final currentSchedules = [
        _schedule(
          id: 'current-1',
          termId: currentTerm.id,
          classId: 'class-1',
        ),
        _schedule(
          id: 'current-2',
          termId: currentTerm.id,
          classId: 'class-2',
        ),
      ];

      final assigned = TeacherClassContextHelper.assignedHorarios(
        [...previousSchedules, ...currentSchedules],
        [previousTerm, currentTerm],
        user: teacher,
        now: today,
        sharedAcrossPeriods: true,
      );
      final classes = TeacherClassContextHelper.getAvailableClasses(
        classes: List.generate(7, (index) => _class(id: 'class-${index + 1}')),
        horarios: [...previousSchedules, ...currentSchedules],
        user: teacher,
        terms: [previousTerm, currentTerm],
        sharedAcrossPeriods: true,
      );

      expect(assigned.map((item) => item.classId).toSet(), hasLength(7));
      expect(classes, hasLength(7));
    });

    test('modo compartilhado preserva várias matérias sem duplicar a turma',
        () {
      final schedules = [
        _schedule(
          id: 'math',
          termId: previousTerm.id,
          classId: 'class-1',
          subjectId: 'subject-math',
        ),
        _schedule(
          id: 'science',
          termId: previousTerm.id,
          classId: 'class-1',
          subjectId: 'subject-science',
        ),
      ];

      final classes = TeacherClassContextHelper.getAvailableClasses(
        classes: [_class(id: 'class-1')],
        horarios: schedules,
        user: teacher,
        terms: [previousTerm],
        sharedAcrossPeriods: true,
      );
      final subjects = TeacherClassContextHelper.subjectsForClass(
        classId: 'class-1',
        horarios: schedules,
        user: teacher,
        terms: [previousTerm],
        sharedAcrossPeriods: true,
      );

      expect(classes, hasLength(1));
      expect(subjects.map((item) => item.id).toSet(),
          {'subject-math', 'subject-science'});
    });

    test('modo compartilhado continua isolando escola e professor', () {
      final schedules = [
        _schedule(id: 'mine', termId: previousTerm.id),
        _schedule(
          id: 'other-teacher',
          termId: previousTerm.id,
          teacherId: 'teacher-2',
          classId: 'class-2',
        ),
        _schedule(
          id: 'other-school',
          termId: previousTerm.id,
          schoolId: 'school-2',
          classId: 'class-3',
        ),
      ];

      final assigned = TeacherClassContextHelper.assignedHorarios(
        schedules,
        [previousTerm],
        user: teacher,
        now: today,
        sharedAcrossPeriods: true,
      );

      expect(assigned.map((item) => item.id), ['mine']);
    });

    test('não inclui horários de outro professor', () {
      final mine = _schedule(id: 'mine', termId: previousTerm.id);
      final other = _schedule(
        id: 'other',
        termId: previousTerm.id,
        teacherId: 'teacher-2',
      );

      final assigned = TeacherClassContextHelper.assignedHorarios(
        [mine, other],
        [previousTerm],
        user: teacher,
        now: today,
      );

      expect(assigned.map((item) => item.id), ['mine']);
    });

    test('não inclui horários de outra escola', () {
      final mine = _schedule(id: 'mine', termId: previousTerm.id);
      final otherSchool = _schedule(
        id: 'other-school',
        termId: previousTerm.id,
        schoolId: 'school-2',
      );

      final assigned = TeacherClassContextHelper.assignedHorarios(
        [mine, otherSchool],
        [previousTerm],
        user: teacher,
        now: today,
      );

      expect(assigned.map((item) => item.id), ['mine']);
    });

    test('deduplica a mesma turma presente em vários horários', () {
      final first = _schedule(
        id: 'first',
        termId: previousTerm.id,
        classId: 'class-1',
      );
      final second = _schedule(
        id: 'second',
        termId: previousTerm.id,
        classId: 'class-1',
      );

      final classes = TeacherClassContextHelper.getAvailableClasses(
        classes: [_class(id: 'class-1')],
        horarios: [first, second],
        user: teacher,
        terms: [previousTerm],
      );

      expect(classes.map((item) => item.id), ['class-1']);
    });

    test('deriva a turma do vínculo mesmo sem lista de turmas em cache', () {
      final schedule = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
        classId: 'class-from-schedule',
      );

      final classes = TeacherClassContextHelper.getAvailableClasses(
        classes: const [],
        horarios: [schedule],
        user: teacher,
        terms: [previousTerm],
      );

      expect(classes.map((item) => item.id), ['class-from-schedule']);
    });

    test('relevantHorarios não zera vínculos por ausência de período atual',
        () {
      final schedule = _schedule(
        id: 'schedule-previous',
        termId: previousTerm.id,
      );

      final relevant = TeacherClassContextHelper.relevantHorarios(
        [schedule],
        [previousTerm, nextTerm],
        user: teacher,
        now: today,
      );

      expect(relevant, [schedule]);
    });

    test('sem vínculos reais continua retornando vazio', () {
      final classes = TeacherClassContextHelper.getAvailableClasses(
        classes: [_class(id: 'class-1')],
        horarios: const [],
        user: teacher,
        terms: [previousTerm],
      );

      expect(classes, isEmpty);
    });
  });
}

TermModel _term({
  required String id,
  required DateTime start,
  required DateTime end,
}) {
  return TermModel(
    id: id,
    schoolYearId: 'year-2026',
    titulo: id,
    startDate: start,
    endDate: end,
    tipo: 'Letivo',
    schoolId: 'school-1',
  );
}

User _user({
  required String id,
  required String schoolId,
}) {
  return User(
    id: id,
    fullName: 'Professor',
    email: 'professor@example.test',
    username: 'professor',
    roles: const ['Professor'],
    status: 'Ativo',
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
    schoolId: schoolId,
    staffProfiles: const [],
  );
}

HorarioModel _schedule({
  required String id,
  required String termId,
  String teacherId = 'teacher-1',
  String schoolId = 'school-1',
  String classId = 'class-1',
  String subjectId = 'subject-1',
}) {
  return HorarioModel(
    id: id,
    termId: termId,
    schoolId: schoolId,
    classInfo: ClassReference(
      id: classId,
      name: classId,
      schoolYear: 2026,
      grade: '1º ano',
      shift: 'Manhã',
      schoolId: schoolId,
    ),
    subject: SubjectModel(
      id: subjectId,
      name: 'Disciplina',
      level: 'Fundamental',
      schoolId: schoolId,
    ),
    teacher: TeacherReference(
      id: teacherId,
      fullName: 'Professor',
    ),
    dayOfWeek: DateTime.monday,
    startTime: '08:00',
    endTime: '09:00',
  );
}

ClassModel _class({required String id}) {
  return ClassModel(
    id: id,
    name: id,
    schoolYear: 2026,
    grade: '1º ano',
    shift: 'Manhã',
    monthlyFee: 0,
    status: 'Ativa',
    studentCount: 0,
    schoolId: 'school-1',
  );
}
