import 'dart:async';

import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/providers/class_provider.dart';
import 'package:academyhub_mobile/providers/horario_provider.dart';
import 'package:academyhub_mobile/services/class_service.dart';
import 'package:academyhub_mobile/services/horario_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resposta tardia de turmas não restaura dados da sessão anterior',
      () async {
    final service = _DelayedClassService();
    final provider = ClassProvider(classService: service);
    final oldFetch = provider.fetchClasses('old');
    provider.clear();
    final newFetch = provider.fetchClasses('new');
    service.requests['new']!.complete(const []);
    await newFetch;
    service.requests['old']!.complete([
      ClassModel.fromJson({
        '_id': 'old-class',
        'name': 'Turma antiga',
        'schoolYear': 2026,
        'grade': '1º ano',
        'shift': 'Manhã',
        'monthlyFee': 0,
        'status': 'Ativa',
        'school_id': 'old-school',
      }),
    ]);
    await oldFetch;
    expect(provider.classes, isEmpty);
  });
  test('resposta tardia de horários não restaura dados da sessão anterior',
      () async {
    final service = _DelayedHorarioService();
    final provider = HorarioProvider(horarioService: service);
    final oldFetch =
        provider.fetchHorarios('old', filter: const {'teacherId': 'old'});
    provider.clear();
    final newFetch =
        provider.fetchHorarios('new', filter: const {'teacherId': 'new'});
    service.requests['new']!.complete(const []);
    await newFetch;
    service.requests['old']!.complete([
      HorarioModel.fromJson({
        '_id': 'old-schedule',
        'termId': 'term-1',
        'school_id': 'old-school',
        'classId': {'_id': 'old-class', 'name': 'Antiga', 'schoolYear': 2026},
        'subjectId': {'_id': 'subject-1', 'name': 'Disciplina'},
        'teacherId': {'_id': 'old', 'fullName': 'Professor'},
        'dayOfWeek': 1,
        'startTime': '08:00',
        'endTime': '09:00',
      }),
    ]);
    await oldFetch;

    expect(provider.horarios, isEmpty);
    expect(provider.hasCanonicalTeacherSchedules('new'), isTrue);
  });
  test('erro HTTP de horários permanece distinguível de lista vazia', () async {
    final provider = HorarioProvider(horarioService: _FailingHorarioService());

    await provider.fetchHorarios(
      'token-de-teste',
      filter: const {'teacherId': 'teacher-1'},
      debugScreen: 'provider_test',
    );

    expect(provider.horarios, isEmpty);
    expect(provider.error, isNotNull);
    expect(provider.isLoading, isFalse);
  });

  test('refresh com erro preserva a última lista completa', () async {
    final service = _SuccessThenFailHorarioService();
    final provider = HorarioProvider(horarioService: service);

    await provider.fetchHorarios('token-de-teste');
    await provider.fetchHorarios('token-de-teste');

    expect(provider.horarios.map((item) => item.id), ['schedule-1']);
    expect(provider.error, isNotNull);
  });

  test('consulta parcial não é marcada como contexto canônico do professor',
      () async {
    final provider = HorarioProvider(
      horarioService: _StaticHorarioService(),
    );

    await provider.fetchHorarios(
      'token-de-teste',
      filter: const {'teacherId': 'teacher-1'},
    );
    expect(provider.hasCanonicalTeacherSchedules('teacher-1'), isTrue);

    await provider.fetchHorarios(
      'token-de-teste',
      filter: const {
        'teacherId': 'teacher-1',
        'termId': 'term-current',
      },
    );
    expect(provider.hasCanonicalTeacherSchedules('teacher-1'), isFalse);
  });

  test('logout invalida o contexto canônico do usuário anterior', () async {
    final provider = HorarioProvider(
      horarioService: _StaticHorarioService(),
    );
    await provider.fetchHorarios(
      'token-de-teste',
      filter: const {'teacherId': 'teacher-1'},
    );

    provider.clear();

    expect(provider.hasCanonicalTeacherSchedules('teacher-1'), isFalse);
    expect(provider.horarios, isEmpty);
  });

  test('erro HTTP de turmas permanece distinguível de lista vazia', () async {
    final provider = ClassProvider(classService: _FailingClassService());

    await provider.fetchClasses('token-de-teste');

    expect(provider.classes, isEmpty);
    expect(provider.error, isNotNull);
    expect(provider.isLoading, isFalse);
  });

  test('resposta vazia válida de turmas não cria estado de erro', () async {
    final provider = ClassProvider(classService: _EmptyClassService());

    await provider.fetchClasses('token-de-teste');

    expect(provider.classes, isEmpty);
    expect(provider.error, isNull);
  });
}

class _DelayedClassService extends ClassService {
  final requests = <String, Completer<List<ClassModel>>>{};

  @override
  Future<List<ClassModel>> getAllClasses(
    String? token, {
    Map<String, String>? filter,
  }) {
    final request = Completer<List<ClassModel>>();
    requests[token!] = request;
    return request.future;
  }
}

class _DelayedHorarioService extends HorarioService {
  final requests = <String, Completer<List<HorarioModel>>>{};

  @override
  Future<List<HorarioModel>> getHorarios(
    String token, {
    Map<String, String>? filter,
    String debugScreen = 'unknown',
  }) {
    final request = Completer<List<HorarioModel>>();
    requests[token] = request;
    return request.future;
  }
}

class _FailingHorarioService extends HorarioService {
  @override
  Future<List<HorarioModel>> getHorarios(
    String token, {
    Map<String, String>? filter,
    String debugScreen = 'unknown',
  }) {
    throw Exception('HTTP 500');
  }
}

class _SuccessThenFailHorarioService extends HorarioService {
  var _calls = 0;

  @override
  Future<List<HorarioModel>> getHorarios(
    String token, {
    Map<String, String>? filter,
    String debugScreen = 'unknown',
  }) async {
    _calls += 1;
    if (_calls > 1) throw Exception('HTTP 500');
    return [
      HorarioModel.fromJson({
        '_id': 'schedule-1',
        'termId': 'term-1',
        'school_id': 'school-1',
        'classId': {
          '_id': 'class-1',
          'name': 'Turma 1',
          'schoolYear': 2026,
          'grade': '1º ano',
        },
        'subjectId': {'_id': 'subject-1', 'name': 'Disciplina'},
        'teacherId': {'_id': 'teacher-1', 'fullName': 'Professor'},
        'dayOfWeek': 1,
        'startTime': '08:00',
        'endTime': '09:00',
      }),
    ];
  }
}

class _StaticHorarioService extends HorarioService {
  @override
  Future<List<HorarioModel>> getHorarios(
    String token, {
    Map<String, String>? filter,
    String debugScreen = 'unknown',
  }) async {
    return const [];
  }
}

class _FailingClassService extends ClassService {
  @override
  Future<List<ClassModel>> getAllClasses(
    String? token, {
    Map<String, String>? filter,
  }) {
    throw Exception('HTTP 403');
  }
}

class _EmptyClassService extends ClassService {
  @override
  Future<List<ClassModel>> getAllClasses(
    String? token, {
    Map<String, String>? filter,
  }) async {
    return const [];
  }
}
