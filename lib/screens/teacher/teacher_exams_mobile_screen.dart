import 'dart:async';
import 'dart:convert';

import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/activity_correction_model.dart';
import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/model/report_card_exam_import_model.dart';
import 'package:academyhub_mobile/model/term_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/class_provider.dart';
import 'package:academyhub_mobile/providers/horario_provider.dart';
import 'package:academyhub_mobile/providers/report_card_provider.dart';
import 'package:academyhub_mobile/screens/teacher/exam_scanner_screen.dart';
import 'package:academyhub_mobile/screens/teacher/activity_correction_screen.dart';
import 'package:academyhub_mobile/screens/teacher/physical_education_grade_screen.dart';
import 'package:academyhub_mobile/services/exam_service.dart';
import 'package:academyhub_mobile/services/activity_correction_service.dart';
import 'package:academyhub_mobile/services/websocket.dart';
import 'package:academyhub_mobile/widgets/report_card_operation_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

void _logExamImport(String tag, Map<String, Object?> data) {
  if (!kDebugMode) return;
  debugPrint('[ExamImport][$tag] ${jsonEncode(data)}');
}

void _logExamMobile(String tag, Map<String, Object?> data) {
  if (!kDebugMode) return;
  debugPrint('[ExamMobile][$tag] ${jsonEncode(data)}');
}

void _logExamPerfMobile(String tag, Map<String, Object?> data) {
  if (!kDebugMode) return;
  debugPrint('[ExamPerfMobile][$tag] ${jsonEncode(data)}');
}

class _ExamListCacheEntry {
  _ExamListCacheEntry({
    required this.items,
    required this.activityPrintRuns,
    required this.createdAt,
  });

  final List<ImportableExamModel> items;
  final List<ActivityCorrectionPrintRun> activityPrintRuns;
  final DateTime createdAt;
}

class _RecentExamListRequest {
  _RecentExamListRequest({
    required this.requestId,
    required this.at,
  });

  final int requestId;
  final DateTime at;
}

class TeacherExamsMobileScreen extends StatefulWidget {
  const TeacherExamsMobileScreen({
    super.key,
    this.navigateStartedAt,
  });

  final DateTime? navigateStartedAt;

  @override
  State<TeacherExamsMobileScreen> createState() =>
      _TeacherExamsMobileScreenState();
}

class _TeacherExamsMobileScreenState extends State<TeacherExamsMobileScreen> {
  final TextEditingController _searchController = TextEditingController();
  StreamSubscription? _socketSubscription;
  int _examListRequestSeq = 0;
  int _activeExamListRequestId = 0;
  final Map<String, _ExamListCacheEntry> _examListCache = {};
  final Map<String, _RecentExamListRequest> _recentExamListRequests = {};

  bool _loading = true;
  bool _loadingExams = false;
  String? _error;

  List<ClassModel> _classes = [];
  List<TermModel> _terms = [];
  List<HorarioModel> _schedules = [];
  List<ImportableExamModel> _exams = [];
  List<ActivityCorrectionPrintRun> _activityPrintRuns = [];
  final ActivityCorrectionService _activityCorrectionService =
      ActivityCorrectionService();

  ClassModel? _selectedClass;
  TermModel? _selectedTerm;
  String? _selectedSubjectId;
  String _statusFilter = 'Todos';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _logExamPerfMobile('FirstFrame', {
        'screen': 'TeacherExams',
        'durationSinceNavigateMs': widget.navigateStartedAt == null
            ? null
            : DateTime.now()
                .difference(widget.navigateStartedAt!)
                .inMilliseconds,
      });
      _bootstrap();
      _listenSocket();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _listenSocket() {
    _socketSubscription?.cancel();
    _socketSubscription = WebSocketService().stream.listen((event) {
      final type = event['type']?.toString();
      final payload = event['payload'] is Map
          ? Map<String, dynamic>.from(event['payload'])
          : event;
      if (type == 'REPORT_CARD_EXAM_IMPORTED' ||
          type == 'REPORT_CARD_UPDATED' ||
          type == 'exam:sheet-corrected' ||
          type == 'activity:correction-updated') {
        final classId = payload['classId']?.toString();
        final examId = payload['examId']?.toString();
        if (classId == null ||
            classId == _selectedClass?.id ||
            examId != null) {
          unawaited(_loadImportableExams(
            silent: true,
            reason: 'realtime_update',
            forceRefresh: true,
          ));
        }
      }
    });
  }

  Future<void> _bootstrap() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final token = auth.token;
      if (token == null) throw Exception('Faça login novamente.');

      final academic = context.read<AcademicCalendarProvider>();
      final classesProvider = context.read<ClassProvider>();
      final horariosProvider = context.read<HorarioProvider>();
      final reportCardService = context.read<ReportCardProvider>().service;

      if (academic.schoolYears.isEmpty) {
        await academic.fetchSchoolYears();
      }
      if (academic.selectedSchoolYear == null &&
          academic.schoolYears.isNotEmpty) {
        academic.selectSchoolYear(academic.schoolYears.first);
      }
      if (academic.selectedSchoolYear != null && academic.terms.isEmpty) {
        await academic.fetchTermsForSelectedYear();
      }
      if (classesProvider.classes.isEmpty) {
        await classesProvider.fetchClasses(token);
      }
      if (horariosProvider.horarios.isEmpty) {
        await horariosProvider.fetchHorarios(token, filter: {
          'resolveInherited': 'true',
        });
      }

      _terms = academic.terms;
      _schedules = horariosProvider.horarios;
      _classes = _resolveTeacherClasses(
        classesProvider.classes,
        _schedules,
        auth.user?.id,
      );
      _selectedTerm = _resolveCurrentTerm(_terms) ??
          (_terms.isNotEmpty ? _terms.first : null);
      _selectedClass = _classes.isNotEmpty ? _classes.first : null;
      _selectedSubjectId = null;

      _logExamPerfMobile('ScreenOpen', {
        'screen': 'TeacherExams',
        'baseUrl': reportCardService.baseUrl,
        'teacherId': auth.user?.id,
        'schoolId': auth.user?.schoolId,
        'initialClassId': _selectedClass?.id,
        'initialClassName': _selectedClass?.name,
        'initialTermId': _selectedTerm?.id,
        'initialTermName': _selectedTerm?.titulo,
        'initialSubjectId': _selectedSubjectId ?? 'all',
      });

      await _loadImportableExams(silent: true, reason: 'screen_open');
    } catch (e) {
      _error = _cleanError(e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<ClassModel> _resolveTeacherClasses(
    List<ClassModel> allClasses,
    List<HorarioModel> schedules,
    String? teacherId,
  ) {
    if (teacherId == null || teacherId.isEmpty) return allClasses;
    final classIds = schedules
        .where((item) => item.teacherId == teacherId)
        .map((item) => item.classId)
        .toSet();
    final filtered =
        allClasses.where((item) => classIds.contains(item.id)).toList();
    return filtered.isEmpty ? allClasses : filtered;
  }

  TermModel? _resolveCurrentTerm(List<TermModel> terms) {
    final now = DateTime.now();
    for (final term in terms) {
      if (term.tipo != 'Letivo') continue;
      final starts = !now.isBefore(term.startDate);
      final ends = !now.isAfter(term.endDate);
      if (starts && ends) return term;
    }
    return null;
  }

  List<HorarioModel> _subjectsForSelection() {
    final classId = _selectedClass?.id;
    final termId = _selectedTerm?.id;
    final seen = <String>{};
    return _schedules.where((schedule) {
      final sameClass = classId == null || schedule.classId == classId;
      final sameTerm = termId == null ||
          schedule.termId == termId ||
          schedule.targetTermId == termId ||
          schedule.isInherited;
      final first = seen.add(schedule.subjectId);
      return sameClass && sameTerm && first;
    }).toList();
  }

  String? _selectedSubjectName() {
    final selectedId = _selectedSubjectId;
    if (selectedId == null) return null;
    for (final schedule in _subjectsForSelection()) {
      if (schedule.subjectId == selectedId) return schedule.subject.name;
    }
    return null;
  }

  String _examListCacheKey(AuthProvider auth) {
    return [
      auth.user?.schoolId ?? 'no-school',
      auth.user?.id ?? 'no-teacher',
      _selectedClass?.id ?? 'no-class',
      _selectedTerm?.id ?? 'no-term',
      _selectedSubjectId ?? 'all',
      _searchController.text.trim().toLowerCase(),
    ].join('|');
  }

  Future<void> _loadImportableExams({
    bool silent = false,
    String reason = 'manual_refresh',
    bool forceRefresh = false,
  }) async {
    final totalStopwatch = Stopwatch()..start();
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    final classId = _selectedClass?.id;
    if (token == null || classId == null) return;
    final service = context.read<ReportCardProvider>().service;
    final requestId = ++_examListRequestSeq;
    _activeExamListRequestId = requestId;
    final cacheKey = _examListCacheKey(auth);
    final now = DateTime.now();
    final recent = _recentExamListRequests[cacheKey];

    if (recent != null) {
      final deltaMs = now.difference(recent.at).inMilliseconds;
      if (deltaMs < 3000) {
        _logExamPerfMobile('DuplicateRequest', {
          'url': '/api/report-cards/import/exams',
          'cacheKey': cacheKey,
          'previousRequestId': recent.requestId,
          'currentRequestId': requestId,
          'deltaMs': deltaMs,
        });
      }
    }
    _recentExamListRequests[cacheKey] =
        _RecentExamListRequest(requestId: requestId, at: now);

    _logExamPerfMobile('LoadStart', {
      'requestId': requestId,
      'reason': reason,
      'classId': classId,
      'className': _selectedClass?.name,
      'termId': _selectedTerm?.id,
      'termName': _selectedTerm?.titulo,
      'subjectId': _selectedSubjectId ?? 'all',
      'search': _searchController.text.trim(),
      'timestamp': now.toIso8601String(),
    });

    final cached = _examListCache[cacheKey];
    if (!forceRefresh &&
        cached != null &&
        now.difference(cached.createdAt).inSeconds < 45) {
      _exams = cached.items;
      _activityPrintRuns = cached.activityPrintRuns;
      totalStopwatch.stop();
      _logExamPerfMobile('LoadEnd', {
        'requestId': requestId,
        'reason': reason,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
        'httpRequestCount': 0,
        'totalResponseBytes': 0,
        'examCount': _exams.length,
        'activityPrintRunCount': _activityPrintRuns.length,
        'usedCache': true,
      });
      _logExamPerfMobile('RenderReady', {
        'screen': 'TeacherExams',
        'requestId': requestId,
        'items': _exams.length,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
      });
      if (mounted) setState(() => _loadingExams = false);
      return;
    }

    if (!silent) {
      setState(() {
        _loadingExams = true;
        _error = null;
      });
    }

    try {
      _logExamMobile('ExamListRequest', {
        'schoolId': auth.user?.schoolId,
        'teacherId': auth.user?.id,
        'classId': classId,
        'termId': _selectedTerm?.id,
        'subjectId': _selectedSubjectId ?? 'all',
        'search': _searchController.text.trim(),
        'page': 1,
        'baseUrl': service.baseUrl,
      });
      final selectedSubject = _selectedSubjectName();
      final results = await Future.wait([
        service.listImportableExams(
          token: token,
          classId: classId,
          termId: _selectedTerm?.id,
          subjectId: _selectedSubjectId,
          requestId: requestId,
        ),
        _selectedTerm?.id == null
            ? Future.value(const <ActivityCorrectionPrintRun>[])
            : _activityCorrectionService.listPrintRunsForCorrection(
                token: token,
                classId: classId,
                termId: _selectedTerm!.id,
                subject: selectedSubject,
              ),
      ]);
      final items = results[0] as List<ImportableExamModel>;
      final activityPrintRuns = results[1] as List<ActivityCorrectionPrintRun>;
      if (requestId != _activeExamListRequestId) {
        _logExamPerfMobile('StaleResponseIgnored', {
          'requestId': requestId,
          'currentRequestId': _activeExamListRequestId,
          'url': '/api/report-cards/import/exams',
        });
        return;
      }
      _exams = items;
      _activityPrintRuns = activityPrintRuns;
      _examListCache[cacheKey] = _ExamListCacheEntry(
        items: items,
        activityPrintRuns: activityPrintRuns,
        createdAt: DateTime.now(),
      );
    } catch (e) {
      _error = _cleanError(e);
    } finally {
      totalStopwatch.stop();
      _logExamMobile('Performance', {
        'action': 'load_exam_list',
        'durationMs': totalStopwatch.elapsedMilliseconds,
        'requestCount': 1,
      });
      _logExamPerfMobile('LoadEnd', {
        'requestId': requestId,
        'reason': reason,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
        'httpRequestCount': service.lastExamListHttpDurationMs > 0 ? 1 : 0,
        'totalResponseBytes': service.lastExamListResponseBytes,
        'examCount': _exams.length,
        'activityPrintRunCount': _activityPrintRuns.length,
        'usedCache': false,
      });
      _logExamPerfMobile('RenderReady', {
        'screen': 'TeacherExams',
        'requestId': requestId,
        'items': _exams.length,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
      });
      if (mounted) {
        setState(() {
          _loadingExams = false;
        });
      }
    }
  }

  List<ImportableExamModel> get _filteredExams {
    final search = _searchController.text.trim().toLowerCase();
    return _exams.where((exam) {
      final matchesSearch = search.isEmpty ||
          exam.title.toLowerCase().contains(search) ||
          exam.subjectName.toLowerCase().contains(search);
      final matchesStatus = _statusFilter == 'Todos' ||
          (_statusFilter == 'Com conflito' && exam.hasConflicts) ||
          (_statusFilter == 'Importáveis' && exam.importableCount > 0) ||
          (_statusFilter == 'Bloqueadas' && exam.blockedCount > 0);
      return matchesSearch && matchesStatus;
    }).toList();
  }

  List<ActivityCorrectionPrintRun> get _filteredActivityPrintRuns {
    final search = _searchController.text.trim().toLowerCase();
    return _activityPrintRuns.where((run) {
      return search.isEmpty ||
          run.bookTitle.toLowerCase().contains(search) ||
          run.activityTitle.toLowerCase().contains(search) ||
          run.subject.toLowerCase().contains(search) ||
          run.students.any(
            (student) => student.studentName.toLowerCase().contains(search),
          );
    }).toList();
  }

  Future<void> _openExam(ImportableExamModel exam) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherExamResultMobileScreen(exam: exam),
      ),
    );
    if (mounted) {
      unawaited(_loadImportableExams(
        silent: true,
        reason: 'return_from_exam_result',
        forceRefresh: true,
      ));
    }
  }

  Future<void> _openActivityCorrection(
    ActivityCorrectionPrintRunStudent student,
  ) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;

    try {
      final resolved = await _activityCorrectionService.resolveQr(
        token: token,
        qrCodePayload: student.qrCodePayload,
      );
      if (!mounted) return;
      final saved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => ActivityCorrectionScreen(resolveResult: resolved),
        ),
      );
      if (saved == true && mounted) {
        await _loadImportableExams(
          silent: true,
          reason: 'activity_correction_saved',
          forceRefresh: true,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(_cleanError(error)), backgroundColor: Colors.red),
      );
    }
  }

  void _openScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ExamScannerScreen()),
    );
  }

  void _openPhysicalEducation() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PhysicalEducationGradeScreen()),
    );
  }

  String _cleanError(Object error) =>
      error.toString().replaceAll('Exception: ', '');

  @override
  Widget build(BuildContext context) {
    final p = _ExamPalette(Theme.of(context).brightness == Brightness.dark);
    return Scaffold(
      backgroundColor: p.page,
      appBar: AppBar(
        backgroundColor: p.page,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Provas',
          style: GoogleFonts.inter(
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: p.title,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Educação Física',
            onPressed: _openPhysicalEducation,
            icon: Icon(PhosphorIcons.person_simple_run, color: p.accentGreen),
          ),
          IconButton(
            tooltip: 'Corrigir prova',
            onPressed: _openScanner,
            icon: Icon(PhosphorIcons.scan, color: p.accentBlue),
          ),
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => _loadImportableExams(
              reason: 'manual_refresh',
              forceRefresh: true,
            ),
            icon: Icon(PhosphorIcons.arrow_clockwise, color: p.title),
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.accentBlue))
          : RefreshIndicator(
              onRefresh: () => _loadImportableExams(
                reason: 'manual_refresh',
                forceRefresh: true,
              ),
              child: ListView(
                padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
                children: [
                  _buildFilters(p),
                  SizedBox(height: 14.h),
                  if (_error != null) _ErrorBox(message: _error!, palette: p),
                  if (_loadingExams)
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 18.h),
                      child: Center(
                          child:
                              CircularProgressIndicator(color: p.accentBlue)),
                    )
                  else if (_filteredExams.isEmpty &&
                      _filteredActivityPrintRuns.isEmpty)
                    _EmptyBox(
                      palette: p,
                      title: _exams.isEmpty && _activityPrintRuns.isEmpty
                          ? 'Nenhuma prova encontrada'
                          : 'Nenhuma prova com esses filtros',
                      message: _exams.isEmpty && _activityPrintRuns.isEmpty
                          ? 'As avaliações impressas e provas desta turma, disciplina e bimestre aparecerão aqui.'
                          : 'Ajuste os filtros para ver outras provas.',
                    )
                  else ...[
                    if (_filteredActivityPrintRuns.isNotEmpty) ...[
                      Text(
                        'Atividades impressas',
                        style: GoogleFonts.inter(
                          fontSize: 16.sp,
                          fontWeight: FontWeight.w800,
                          color: p.title,
                        ),
                      ),
                      SizedBox(height: 10.h),
                      ..._filteredActivityPrintRuns.map(
                        (run) => Padding(
                          padding: EdgeInsets.only(bottom: 12.h),
                          child: _ActivityPrintRunCard(
                            run: run,
                            palette: p,
                            onStudentTap: _openActivityCorrection,
                          ),
                        ),
                      ),
                    ],
                    if (_filteredExams.isNotEmpty &&
                        _filteredActivityPrintRuns.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: 6.h, bottom: 10.h),
                        child: Text(
                          'Provas objetivas',
                          style: GoogleFonts.inter(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: p.title,
                          ),
                        ),
                      ),
                    ..._filteredExams.map((exam) => Padding(
                          padding: EdgeInsets.only(bottom: 12.h),
                          child: _ExamImportCard(
                            exam: exam,
                            palette: p,
                            onTap: () => _openExam(exam),
                          ),
                        )),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildFilters(_ExamPalette p) {
    final subjects = _subjectsForSelection();
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            hintText: 'Buscar prova por título ou disciplina',
            prefixIcon: Icon(PhosphorIcons.magnifying_glass, color: p.subtitle),
            filled: true,
            fillColor: p.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide(color: p.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14.r),
              borderSide: BorderSide(color: p.border),
            ),
          ),
        ),
        SizedBox(height: 12.h),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _DropdownChip<ClassModel>(
                value: _selectedClass,
                items: _classes,
                label: (item) => item.name,
                hint: 'Turma',
                palette: p,
                onChanged: (value) {
                  setState(() {
                    _selectedClass = value;
                    _selectedSubjectId = null;
                  });
                  _loadImportableExams(
                    reason: 'filter_change',
                    forceRefresh: true,
                  );
                },
              ),
              SizedBox(width: 8.w),
              _DropdownChip<TermModel>(
                value: _selectedTerm,
                items: _terms,
                label: (item) => item.titulo,
                hint: 'Bimestre',
                palette: p,
                onChanged: (value) {
                  setState(() {
                    _selectedTerm = value;
                    _selectedSubjectId = null;
                  });
                  _loadImportableExams(
                    reason: 'filter_change',
                    forceRefresh: true,
                  );
                },
              ),
              SizedBox(width: 8.w),
              _DropdownChip<String?>(
                value: _selectedSubjectId,
                items: <String?>[null, ...subjects.map((e) => e.subjectId)],
                label: (id) => id == null
                    ? 'Todas'
                    : subjects
                        .firstWhere((item) => item.subjectId == id)
                        .subject
                        .name,
                hint: 'Disciplina',
                palette: p,
                onChanged: (value) {
                  setState(() => _selectedSubjectId = value);
                  _loadImportableExams(
                    reason: 'filter_change',
                    forceRefresh: true,
                  );
                },
              ),
              SizedBox(width: 8.w),
              _DropdownChip<String>(
                value: _statusFilter,
                items: const [
                  'Todos',
                  'Importáveis',
                  'Com conflito',
                  'Bloqueadas',
                ],
                label: (item) => item,
                hint: 'Status',
                palette: p,
                onChanged: (value) =>
                    setState(() => _statusFilter = value ?? 'Todos'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class TeacherExamResultMobileScreen extends StatefulWidget {
  final ImportableExamModel exam;

  const TeacherExamResultMobileScreen({
    super.key,
    required this.exam,
  });

  @override
  State<TeacherExamResultMobileScreen> createState() =>
      _TeacherExamResultMobileScreenState();
}

class _TeacherExamResultMobileScreenState
    extends State<TeacherExamResultMobileScreen> {
  final ExamApiService _examService = ExamApiService();
  StreamSubscription? _socketSubscription;
  int _resultRequestSeq = 0;
  int _previewRequestSeq = 0;

  bool _loading = true;
  bool _loadingPreview = false;
  String? _error;
  ExamResultsMobileData? _results;
  ReportCardExamImportPreview? _importPreview;
  TermModel? _targetTerm;

  @override
  void initState() {
    super.initState();
    _logExamPerfMobile('ExamResultOpen', {
      'examId': widget.exam.examId,
      'title': widget.exam.title,
      'timestamp': DateTime.now().toIso8601String(),
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _resolveInitialTargetTerm();
      _loadResults();
      _listenSocket();
    });
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _resolveInitialTargetTerm() {
    final academic = context.read<AcademicCalendarProvider>();
    if (academic.terms.isEmpty) return;
    final now = DateTime.now();
    TermModel? current;
    for (final term in academic.terms) {
      final starts = !now.isBefore(term.startDate);
      final ends = !now.isAfter(term.endDate);
      if (term.tipo == 'Letivo' && starts && ends) {
        current = term;
        break;
      }
    }

    TermModel? examTerm;
    for (final term in academic.terms) {
      if (term.id == widget.exam.termId) {
        examTerm = term;
        break;
      }
    }

    _targetTerm = current ?? examTerm ?? academic.terms.first;
  }

  TermModel? _selectedTargetTerm() {
    if (_targetTerm != null) return _targetTerm;
    final academic = context.read<AcademicCalendarProvider>();
    if (academic.terms.isEmpty) return null;
    _resolveInitialTargetTerm();
    return _targetTerm;
  }

  String _targetYearLabel(TermModel? term) {
    if (term == null) return 'Nao definido';
    final academic = context.read<AcademicCalendarProvider>();
    for (final year in academic.schoolYears) {
      if (year.id == term.schoolYearId) return year.year.toString();
    }
    return term.schoolYearId.isEmpty ? 'Nao definido' : term.schoolYearId;
  }

  void _changeTargetTerm(TermModel? term) {
    if (term == null || term.id == _targetTerm?.id) return;
    setState(() {
      _targetTerm = term;
      _importPreview = null;
    });
    unawaited(_loadImportPreview());
  }

  void _listenSocket() {
    _socketSubscription?.cancel();
    _socketSubscription = WebSocketService().stream.listen((event) {
      final type = event['type']?.toString();
      final payload = event['payload'] is Map
          ? Map<String, dynamic>.from(event['payload'])
          : event;
      if ((type == 'REPORT_CARD_EXAM_IMPORTED' ||
              type == 'REPORT_CARD_UPDATED' ||
              type == 'exam:sheet-corrected') &&
          payload['examId']?.toString() == widget.exam.examId) {
        unawaited(_loadResults(silent: true));
      }
    });
  }

  Future<void> _loadResults({bool silent = false}) async {
    final totalStopwatch = Stopwatch()..start();
    final requestId = ++_resultRequestSeq;
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    var loadedResults = false;
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      _logExamMobile('ExamResultRequest', {
        'examId': widget.exam.examId,
        'classId': widget.exam.classId,
        'termId': widget.exam.termId,
        'subjectId': widget.exam.subjectId,
        'baseUrl': context.read<ReportCardProvider>().service.baseUrl,
      });
      _results = await _examService.getExamResults(
        examId: widget.exam.examId,
        token: token,
        requestId: requestId,
      );
      loadedResults = true;
      _logExamPerfMobile('ExamResultRenderReady', {
        'examId': widget.exam.examId,
        'students': _results?.students.length ?? 0,
        'hasResults': _results != null,
        'hasPreview': _importPreview != null,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
      });
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      totalStopwatch.stop();
      _logExamMobile('Performance', {
        'action': 'open_exam_result',
        'durationMs': totalStopwatch.elapsedMilliseconds,
        'requestCount': 1,
      });
      if (mounted) setState(() => _loading = false);
      if (loadedResults) {
        unawaited(_loadImportPreview());
      }
    }
  }

  String _scoreModeForExam() {
    if (widget.exam.scoreMode.isNotEmpty && widget.exam.scoreMode != 'raw') {
      return widget.exam.scoreMode;
    }
    final totalValue = widget.exam.totalValue;
    if (totalValue != null && totalValue > 10) {
      return 'normalize_to_component';
    }
    return 'raw';
  }

  Future<void> _loadImportPreview({bool silent = false}) async {
    final totalStopwatch = Stopwatch()..start();
    final requestId = ++_previewRequestSeq;
    final token = context.read<AuthProvider>().token;
    final targetTerm = _selectedTargetTerm();
    if (token == null || targetTerm == null || targetTerm.id.isEmpty) return;
    if (!silent && mounted) setState(() => _loadingPreview = true);

    try {
      final service = context.read<ReportCardProvider>().service;
      final scoreMode = _scoreModeForExam();
      _logExamMobile('PreviewRequest', {
        'examId': widget.exam.examId,
        'examTitle': widget.exam.title,
        'examClassId': widget.exam.classId,
        'examClassName': widget.exam.className,
        'examSubjectId': widget.exam.subjectId,
        'examSubjectName': widget.exam.subjectName,
        'examTermId': widget.exam.termId,
        'examTermName': widget.exam.termName,
        'targetClassId': widget.exam.classId,
        'targetClassName': widget.exam.className,
        'targetSubjectId': widget.exam.subjectId,
        'targetSubjectName': widget.exam.subjectName,
        'targetTermId': targetTerm.id,
        'targetTermName': targetTerm.titulo,
        'targetAcademicYearId': targetTerm.schoolYearId,
        'scoreMode': scoreMode,
        'baseUrl': service.baseUrl,
      });
      final preview = await service.previewExamImport(
        token: token,
        examId: widget.exam.examId,
        classId: widget.exam.classId,
        subjectId: widget.exam.subjectId,
        termId: targetTerm.id,
        targetAcademicYearId: targetTerm.schoolYearId,
        scoreMode: scoreMode,
        requestId: requestId,
      );
      _importPreview = preview;
      _logExamImport('EligibilitySummary', {
        'examId': preview.exam.examId,
        'title': preview.exam.title,
        'className': preview.exam.className,
        'subjectName': preview.exam.subjectName,
        'termName': preview.exam.termName,
        'sheets': widget.exam.totalSheets,
        'corrected': widget.exam.correctedSheets,
        'pending': widget.exam.pendingSheets,
        'importable': preview.summary.importableCount,
        'blocked': preview.summary.blockedCount,
        'conflicts': preview.summary.conflictCount,
        'alreadyImported': preview.summary.noopCount,
        'buttonEnabled': _isImportButtonEnabled(preview),
        'buttonDisabledReason': _importButtonDisabledReason(preview),
        'scoreMode': preview.target.scoreMode,
      });
      _logExamMobile('ImportButtonState', {
        'examId': widget.exam.examId,
        'enabled': _isImportButtonEnabled(preview),
        'reason': _isImportButtonEnabled(preview)
            ? 'importable_results'
            : _importButtonDisabledReason(preview),
        'importableCount': preview.summary.importableCount,
        'correctedCount': widget.exam.correctedSheets,
        'blockedCount': preview.summary.blockedCount,
        'conflictsCount': preview.summary.conflictCount,
        'pendingCount': preview.summary.pendingCount,
      });
      for (final item in preview.items) {
        _logExamImport('EligibilityStudent', {
          'examId': preview.exam.examId,
          'studentId': item.studentId,
          'studentName': item.studentName,
          'score': item.examGrade,
          'maxScore': item.examMaxGrade,
          'isCorrected': item.correctionStatus == 'corrected',
          'isImportable': item.isImportable,
          'isBlocked': item.isBlocked,
          'blockReason': item.isBlocked ? item.blockReason : null,
          'isAlreadyImported': item.isAlreadyImported,
          'gradebookEntryId': item.reportCardId,
          'assessmentId': null,
          'missingReportCardDiagnosis': item.missingReportCardDiagnosis,
          'targetClassId': preview.target.classId,
          'targetClassName': preview.target.className,
          'targetSubjectId': preview.target.subjectId,
          'targetSubjectName': preview.target.subjectName,
          'targetTermId': preview.target.termId,
          'targetTermName': preview.target.termName,
        });
      }
    } catch (e) {
      _logExamMobile('ExamResultPreviewError', {
        'examId': widget.exam.examId,
        'error': e.toString().replaceAll('Exception: ', ''),
      });
    } finally {
      totalStopwatch.stop();
      _logExamPerfMobile('ExamResultRenderReady', {
        'examId': widget.exam.examId,
        'students': _results?.students.length ?? 0,
        'hasResults': _results != null,
        'hasPreview': _importPreview != null,
        'totalDurationMs': totalStopwatch.elapsedMilliseconds,
      });
      if (mounted) setState(() => _loadingPreview = false);
    }
  }

  bool _isImportButtonEnabled([ReportCardExamImportPreview? preview]) {
    final currentPreview = preview ?? _importPreview;
    if (_loading || _loadingPreview || currentPreview == null) return false;
    return currentPreview.summary.importableCount > 0;
  }

  bool _canOpenImportDetails() {
    return !_loading && !_loadingPreview && _importPreview != null;
  }

  String _importButtonDisabledReason([ReportCardExamImportPreview? preview]) {
    if (_loading || _loadingPreview) return 'loading';
    final currentPreview = preview ?? _importPreview;
    if (currentPreview == null) {
      final targetTerm = _selectedTargetTerm();
      if (targetTerm == null || targetTerm.id.isEmpty) {
        return 'missing_target_term';
      }
      return 'preview_not_loaded';
    }
    if (currentPreview.termBlocked) return 'term_blocked';
    if (currentPreview.summary.conflictCount > 0) return 'has_conflicts';
    if (currentPreview.summary.blockedCount > 0) {
      final reasons = currentPreview.items
          .where((item) => item.isBlocked)
          .map((item) => item.blockReason)
          .toSet()
          .join(' | ');
      return reasons.isEmpty ? 'blocked' : reasons;
    }
    if (currentPreview.summary.noopCount > 0) return 'already_imported';
    if (currentPreview.summary.pendingCount > 0) return 'pending_correction';
    return 'no_importable_results';
  }

  String _importButtonHelperText() {
    final preview = _importPreview;
    if (_loadingPreview) return 'Verificando elegibilidade das notas...';
    if (preview == null) return 'Aguardando dados de importacao.';
    if (_isImportButtonEnabled(preview)) {
      if (preview.target.scoreMode == 'normalize_to_component') {
        return 'As notas serao normalizadas para a escala 0 a 10 do boletim.';
      }
      return '${preview.summary.importableCount} nota(s) pronta(s) para importar.';
    }
    final reason = _importButtonDisabledReason(preview);
    if (reason == 'already_imported') {
      return 'As notas ja estao importadas ou iguais no boletim.';
    }
    if (reason == 'has_conflicts') {
      return 'Existem conflitos que precisam de decisao no preview.';
    }
    if (reason == 'pending_correction') {
      return '${preview.summary.pendingCount} nota(s) pendente(s) de correcao.';
    }
    return reason;
  }

  ImportPreviewItem? _importItemForStudent(String studentId) {
    final items = _importPreview?.items ?? const <ImportPreviewItem>[];
    for (final item in items) {
      if (item.studentId == studentId) return item;
    }
    return null;
  }

  Future<void> _openImportPreview() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    final targetTerm = _selectedTargetTerm();
    if (targetTerm == null || targetTerm.id.isEmpty) {
      _showMessage('Selecione um bimestre de destino para importar.');
      return;
    }

    try {
      final service = context.read<ReportCardProvider>().service;
      final preview = _importPreview ??
          await service.previewExamImport(
            token: token,
            examId: widget.exam.examId,
            classId: widget.exam.classId,
            subjectId: widget.exam.subjectId,
            termId: targetTerm.id,
            targetAcademicYearId: targetTerm.schoolYearId,
            scoreMode: _scoreModeForExam(),
          );
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => _ImportPreviewSheet(
          preview: preview,
          onCommit: _commitImport,
        ),
      );
      await _loadResults(silent: true);
    } catch (e) {
      _showMessage(e.toString().replaceAll('Exception: ', ''), error: true);
    }
  }

  Future<ReportCardExamImportCommitResult> _commitImport({
    required ReportCardExamImportPreview preview,
    required List<String> selectedStudentIds,
    required Map<String, dynamic> conflictDecisions,
    required String reason,
  }) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) throw Exception('Faça login novamente.');
    final service = context.read<ReportCardProvider>().service;
    final result = await service.commitExamImport(
      token: token,
      examId: preview.exam.examId,
      classId: preview.target.classId,
      subjectId: preview.target.subjectId,
      termId: preview.target.termId,
      targetAcademicYearId: preview.target.academicYearId,
      selectedStudentIds: selectedStudentIds,
      conflictDecisions: conflictDecisions,
      reason: reason,
      scoreMode: preview.target.scoreMode,
    );
    if (mounted) {
      _showMessage(result.reused
          ? 'Importação já aplicada anteriormente.'
          : 'Notas importadas para o boletim.');
    }
    return result;
  }

  void _showMessage(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _ExamPalette(Theme.of(context).brightness == Brightness.dark);
    final results = _results;
    final academic = context.watch<AcademicCalendarProvider>();
    final targetTerm = _selectedTargetTerm();
    return Scaffold(
      backgroundColor: p.page,
      appBar: AppBar(
        backgroundColor: p.page,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Resultado da Prova',
          style: GoogleFonts.inter(
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: p.title,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: () => _loadResults(),
            icon: Icon(PhosphorIcons.arrow_clockwise, color: p.title),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                onPressed: _isImportButtonEnabled() ? _openImportPreview : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accentGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 14.h),
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                icon: Icon(PhosphorIcons.upload_simple, size: 18.sp),
                label: const Text('Importar para boletim'),
              ),
              SizedBox(height: 8.h),
              Text(
                _importButtonHelperText(),
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w600,
                  color: p.subtitle,
                ),
              ),
              if (!_isImportButtonEnabled() && _canOpenImportDetails())
                TextButton(
                  onPressed: _openImportPreview,
                  child: const Text('Ver motivos'),
                ),
            ],
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.accentBlue))
          : _error != null
              ? Center(child: _ErrorBox(message: _error!, palette: p))
              : results == null
                  ? Center(
                      child: _EmptyBox(
                        palette: p,
                        title: 'Sem dados',
                        message: 'Não foi possível carregar esta prova.',
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
                      children: [
                        _ExamResultHeader(
                          exam: widget.exam,
                          results: results,
                          palette: p,
                        ),
                        SizedBox(height: 14.h),
                        _TargetDestinationCard(
                          palette: p,
                          terms: academic.terms
                              .where((term) => term.tipo == 'Letivo')
                              .toList(),
                          selectedTerm: targetTerm,
                          yearLabel: _targetYearLabel(targetTerm),
                          className: widget.exam.className,
                          subjectName: widget.exam.subjectName,
                          loading: _loadingPreview,
                          onTermChanged: _changeTargetTerm,
                        ),
                        SizedBox(height: 14.h),
                        Text(
                          'Alunos e resultados',
                          style: GoogleFonts.inter(
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w800,
                            color: p.title,
                          ),
                        ),
                        SizedBox(height: 10.h),
                        ...results.students.map((student) => Padding(
                              padding: EdgeInsets.only(bottom: 10.h),
                              child: _StudentResultTile(
                                student: student,
                                importItem:
                                    _importItemForStudent(student.studentId),
                                palette: p,
                              ),
                            )),
                      ],
                    ),
    );
  }
}

class _ImportPreviewSheet extends StatefulWidget {
  final ReportCardExamImportPreview preview;
  final Future<ReportCardExamImportCommitResult> Function({
    required ReportCardExamImportPreview preview,
    required List<String> selectedStudentIds,
    required Map<String, dynamic> conflictDecisions,
    required String reason,
  }) onCommit;

  const _ImportPreviewSheet({
    required this.preview,
    required this.onCommit,
  });

  @override
  State<_ImportPreviewSheet> createState() => _ImportPreviewSheetState();
}

class _ImportPreviewSheetState extends State<_ImportPreviewSheet> {
  final TextEditingController _reasonController = TextEditingController(
    text: 'Importação de notas da prova para o boletim',
  );
  final Set<String> _selected = {};
  final Map<String, String> _conflictActions = {};
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.preview.items
        .where((item) => item.status == 'will_fill')
        .map((item) => item.studentId));
    for (final item in widget.preview.items.where((item) => item.isConflict)) {
      _conflictActions[item.studentId] = 'ignore';
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final overwriteIds = _conflictActions.entries
        .where((entry) => entry.value == 'overwrite')
        .map((entry) => entry.key)
        .toList();
    final reason = _reasonController.text.trim();
    if (overwriteIds.isNotEmpty && reason.isEmpty) {
      _showError('Informe um motivo para substituir notas existentes.');
      return;
    }

    setState(() => _saving = true);
    try {
      final conflictDecisions = <String, dynamic>{};
      for (final entry in _conflictActions.entries) {
        conflictDecisions[entry.key] = {
          'action': entry.value == 'overwrite' ? 'overwrite' : 'ignore',
          'reason': reason,
        };
      }
      final selected = {..._selected, ...overwriteIds}.toList();
      ReportCardExamImportCommitResult? result;
      final completed = await showReportCardOperationDialog(
        context: context,
        loadingTitle: 'Importando notas para boletim',
        loadingMessage:
            'Atualizando os boletins dos alunos com as notas da prova.',
        loadingDetail:
            'Sincronizando notas da prova com a central de boletins.',
        successTitle: 'Importacao concluida',
        successMessage:
            'As notas da prova foram sincronizadas com os boletins.',
        errorTitle: 'Falha na importacao',
        errorFallbackMessage:
            'Nao foi possivel importar as notas para o boletim.',
        operation: () async {
          result = await widget.onCommit(
            preview: widget.preview,
            selectedStudentIds: selected,
            conflictDecisions: conflictDecisions,
            reason: reason,
          );
        },
      );
      if (!mounted || completed != true || result == null) return;
      Navigator.pop(context);
      await showDialog<void>(
        context: context,
        builder: (_) => _CommitResultDialog(result: result!),
      );
    } catch (e) {
      _showError(e.toString().replaceAll('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _ExamPalette(Theme.of(context).brightness == Brightness.dark);
    final preview = widget.preview;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.55,
      maxChildSize: 0.96,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: p.page,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22.r)),
          ),
          child: ListView(
            controller: scrollController,
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 24.h),
            children: [
              Center(
                child: Container(
                  width: 44.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(20.r),
                  ),
                ),
              ),
              SizedBox(height: 16.h),
              Text(
                'Importar para boletim',
                style: GoogleFonts.inter(
                  fontSize: 20.sp,
                  fontWeight: FontWeight.w900,
                  color: p.title,
                ),
              ),
              SizedBox(height: 4.h),
              Text(
                preview.exam.title,
                style: GoogleFonts.inter(color: p.subtitle),
              ),
              SizedBox(height: 6.h),
              Text(
                'Destino: ${preview.target.className} • ${preview.target.subjectName} • ${preview.target.termName}',
                style: GoogleFonts.inter(
                  color: p.title,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 14.h),
              Wrap(
                spacing: 8.w,
                runSpacing: 8.h,
                children: [
                  _MetricPill('Preencher', preview.summary.importableCount,
                      p.accentGreen, p),
                  _MetricPill(
                      'Iguais', preview.summary.noopCount, p.accentBlue, p),
                  _MetricPill('Conflitos', preview.summary.conflictCount,
                      p.accentRed, p),
                  _MetricPill('Pendentes', preview.summary.pendingCount,
                      p.accentOrange, p),
                  _MetricPill(
                      'Bloqueados', preview.summary.blockedCount, p.muted, p),
                ],
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: _reasonController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: 'Motivo',
                  filled: true,
                  fillColor: p.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide(color: p.border),
                  ),
                ),
              ),
              SizedBox(height: 14.h),
              ...preview.items.map((item) => Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: _PreviewItemCard(
                      item: item,
                      palette: p,
                      selected: _selected.contains(item.studentId),
                      conflictAction: _conflictActions[item.studentId],
                      onSelectedChanged: item.status == 'will_fill'
                          ? (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(item.studentId);
                                } else {
                                  _selected.remove(item.studentId);
                                }
                              });
                            }
                          : null,
                      onConflictActionChanged: item.isConflict
                          ? (value) {
                              setState(() {
                                _conflictActions[item.studentId] =
                                    value ?? 'ignore';
                              });
                            }
                          : null,
                    ),
                  )),
              SizedBox(height: 8.h),
              ElevatedButton.icon(
                onPressed:
                    _saving || !preview.canCommit ? null : () => _commit(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accentGreen,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: 15.h),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                ),
                icon: _saving
                    ? SizedBox(
                        width: 18.w,
                        height: 18.w,
                        child: const CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(PhosphorIcons.check_circle, size: 18.sp),
                label: Text(_saving ? 'Importando...' : 'Confirmar importação'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ExamPalette {
  final bool isDark;
  _ExamPalette(this.isDark);

  Color get page => isDark ? const Color(0xFF0F1217) : const Color(0xFFF5F7FB);
  Color get surface => isDark ? const Color(0xFF171B22) : Colors.white;
  Color get surfaceAlt =>
      isDark ? const Color(0xFF20242C) : const Color(0xFFF8FAFD);
  Color get border =>
      isDark ? const Color(0xFF2B3038) : const Color(0xFFE5EAF2);
  Color get title => isDark ? Colors.white : const Color(0xFF172033);
  Color get subtitle =>
      isDark ? const Color(0xFFA1A9B7) : const Color(0xFF687386);
  Color get muted => isDark ? const Color(0xFF7B8494) : const Color(0xFF98A2B3);
  Color get accentBlue => const Color(0xFF2F80ED);
  Color get accentGreen => const Color(0xFF2DBE60);
  Color get accentOrange => const Color(0xFFF2994A);
  Color get accentRed => const Color(0xFFE05555);
}

class _DropdownChip<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T value) label;
  final String hint;
  final _ExamPalette palette;
  final ValueChanged<T?> onChanged;

  const _DropdownChip({
    required this.value,
    required this.items,
    required this.label,
    required this.hint,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42.h,
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : null,
          hint: Text(hint),
          items: items
              .map((item) => DropdownMenuItem<T>(
                    value: item,
                    child: Text(label(item)),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _ActivityPrintRunCard extends StatelessWidget {
  const _ActivityPrintRunCard({
    required this.run,
    required this.palette,
    required this.onStudentTap,
  });

  final ActivityCorrectionPrintRun run;
  final _ExamPalette palette;
  final ValueChanged<ActivityCorrectionPrintRunStudent> onStudentTap;

  @override
  Widget build(BuildContext context) {
    final title =
        run.bookTitle.isNotEmpty ? run.bookTitle : 'Atividade impressa';
    final subtitle = [
      if (run.activityTitle.isNotEmpty) run.activityTitle,
      if (run.subject.isNotEmpty) run.subject,
    ].join(' • ');

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: palette.border),
      ),
      child: ExpansionTile(
        tilePadding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 10.h),
        childrenPadding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 12.h),
        leading: Container(
          padding: EdgeInsets.all(9.w),
          decoration: BoxDecoration(
            color: palette.accentBlue.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(11.r),
          ),
          child: Icon(PhosphorIcons.clipboard_text, color: palette.accentBlue),
        ),
        title: Text(
          title,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            fontSize: 14.sp,
            color: palette.title,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (subtitle.isNotEmpty) ...[
              SizedBox(height: 4.h),
              Text(subtitle,
                  style: GoogleFonts.inter(
                      fontSize: 12.sp, color: palette.subtitle)),
            ],
            SizedBox(height: 7.h),
            Wrap(
              spacing: 6.w,
              runSpacing: 5.h,
              children: [
                _ActivityStatusPill(
                  label: '${run.pendingCount} pendente(s)',
                  color: Colors.orange.shade700,
                ),
                _ActivityStatusPill(
                  label: '${run.correctedCount} corrigida(s)',
                  color: palette.accentGreen,
                ),
                _ActivityStatusPill(
                  label: '${run.totalStudents} aluno(s)',
                  color: palette.accentBlue,
                ),
              ],
            ),
          ],
        ),
        children: run.students
            .map(
              (student) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  student.isPending
                      ? PhosphorIcons.clock
                      : PhosphorIcons.check_circle,
                  color: student.isPending
                      ? Colors.orange.shade700
                      : palette.accentGreen,
                ),
                title: Text(
                  student.studentName.isNotEmpty
                      ? student.studentName
                      : 'Aluno',
                  style: GoogleFonts.inter(
                      fontSize: 13.sp, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  student.isPending ? 'Pendente' : 'Corrigida',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    color: student.isPending
                        ? Colors.orange.shade700
                        : palette.accentGreen,
                  ),
                ),
                trailing:
                    Icon(PhosphorIcons.caret_right, color: palette.subtitle),
                onTap: () => onStudentTap(student),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

class _ActivityStatusPill extends StatelessWidget {
  const _ActivityStatusPill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
            fontSize: 10.sp, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }
}

class _ExamImportCard extends StatelessWidget {
  final ImportableExamModel exam;
  final _ExamPalette palette;
  final VoidCallback onTap;

  const _ExamImportCard({
    required this.exam,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final date = exam.applicationDate == null
        ? 'Sem data'
        : DateFormat('dd/MM/yyyy').format(exam.applicationDate!);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: exam.hasConflicts
                ? palette.accentOrange.withValues(alpha: 0.45)
                : palette.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.w,
                  decoration: BoxDecoration(
                    color: palette.accentBlue.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(PhosphorIcons.exam,
                      color: palette.accentBlue, size: 20.sp),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exam.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w800,
                          color: palette.title,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      Text(
                        '${exam.subjectName} • ${exam.className}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.sp,
                          color: palette.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(PhosphorIcons.caret_right, color: palette.muted),
              ],
            ),
            SizedBox(height: 12.h),
            Wrap(
              spacing: 7.w,
              runSpacing: 7.h,
              children: [
                _InfoChip('$date • ${exam.termName ?? 'Bimestre'}', palette),
                _InfoChip(
                    '${exam.correctedSheets}/${exam.totalSheets} corrigidas',
                    palette),
                _InfoChip('${exam.totalValue?.toStringAsFixed(1) ?? '--'} pts',
                    palette),
              ],
            ),
            SizedBox(height: 10.h),
            Row(
              children: [
                Expanded(
                    child: _SmallCounter(
                        'Importáveis',
                        exam.importableCount.toString(),
                        palette.accentGreen,
                        palette)),
                SizedBox(width: 8.w),
                Expanded(
                    child: _SmallCounter(
                        'Importadas',
                        exam.alreadyImportedCount.toString(),
                        palette.accentBlue,
                        palette)),
                SizedBox(width: 8.w),
                Expanded(
                    child: _SmallCounter(
                        'Conflitos',
                        exam.conflictCount.toString(),
                        palette.accentOrange,
                        palette)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamResultHeader extends StatelessWidget {
  final ImportableExamModel exam;
  final ExamResultsMobileData results;
  final _ExamPalette palette;

  const _ExamResultHeader({
    required this.exam,
    required this.results,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exam.title,
            style: GoogleFonts.inter(
              fontSize: 18.sp,
              fontWeight: FontWeight.w900,
              color: palette.title,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            '${exam.subjectName} • ${exam.className} • ${exam.termName ?? 'Bimestre'}',
            style: GoogleFonts.inter(color: palette.subtitle),
          ),
          SizedBox(height: 14.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _MetricPill(
                  'Folhas', exam.totalSheets, palette.accentBlue, palette),
              _MetricPill('Corrigidas', exam.correctedSheets,
                  palette.accentGreen, palette),
              _MetricPill('Pendentes', exam.pendingSheets, palette.accentOrange,
                  palette),
              _MetricPill('Importáveis', exam.importableCount,
                  palette.accentGreen, palette),
              _MetricPill(
                  'Conflitos', exam.conflictCount, palette.accentRed, palette),
              _MetricPill(
                  'Bloqueadas', exam.blockedCount, palette.muted, palette),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetDestinationCard extends StatelessWidget {
  final _ExamPalette palette;
  final List<TermModel> terms;
  final TermModel? selectedTerm;
  final String yearLabel;
  final String className;
  final String subjectName;
  final bool loading;
  final ValueChanged<TermModel?> onTermChanged;

  const _TargetDestinationCard({
    required this.palette,
    required this.terms,
    required this.selectedTerm,
    required this.yearLabel,
    required this.className,
    required this.subjectName,
    required this.loading,
    required this.onTermChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selectedValue =
        terms.any((term) => term.id == selectedTerm?.id) ? selectedTerm : null;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.target,
                  size: 18.sp, color: palette.accentBlue),
              SizedBox(width: 8.w),
              Expanded(
                child: Text(
                  'Destino da nota',
                  style: GoogleFonts.inter(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w900,
                    color: palette.title,
                  ),
                ),
              ),
              if (loading)
                SizedBox(
                  width: 16.w,
                  height: 16.w,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: palette.accentBlue,
                  ),
                ),
            ],
          ),
          SizedBox(height: 12.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _InfoPill('Ano letivo', yearLabel, palette),
              _InfoPill('Turma', className, palette),
              _InfoPill('Disciplina', subjectName, palette),
            ],
          ),
          SizedBox(height: 12.h),
          DropdownButtonFormField<TermModel>(
            initialValue: selectedValue,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Bimestre',
              filled: true,
              fillColor: palette.surfaceAlt,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(color: palette.border),
              ),
            ),
            items: terms
                .map(
                  (term) => DropdownMenuItem<TermModel>(
                    value: term,
                    child: Text(
                      term.titulo,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: loading ? null : onTermChanged,
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;
  final String value;
  final _ExamPalette palette;

  const _InfoPill(this.label, this.value, this.palette);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: palette.border),
      ),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.inter(
            fontSize: 11.sp,
            color: palette.subtitle,
            fontWeight: FontWeight.w600,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value.isEmpty ? 'Nao definido' : value,
              style: TextStyle(
                color: palette.title,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StudentResultTile extends StatelessWidget {
  final ExamStudentResultMobile student;
  final ImportPreviewItem? importItem;
  final _ExamPalette palette;

  const _StudentResultTile({
    required this.student,
    this.importItem,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    final importStatus = importItem?.status;
    final isBlocked = importItem?.isBlocked == true;
    final isImportable = importItem?.isImportable == true;
    final isAlreadyImported = importItem?.isAlreadyImported == true;
    final color = isBlocked
        ? palette.accentRed
        : isImportable
            ? palette.accentGreen
            : isAlreadyImported
                ? palette.accentBlue
                : student.isCorrected
                    ? palette.accentGreen
                    : palette.accentOrange;
    return Container(
      padding: EdgeInsets.all(13.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14.r),
        border:
            Border.all(color: isBlocked ? palette.accentRed : palette.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(student.studentName,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, color: palette.title)),
                SizedBox(height: 4.h),
                Text(
                  _studentStatusText(importStatus),
                  style: GoogleFonts.inter(fontSize: 12.sp, color: color),
                ),
                if (importItem?.message?.trim().isNotEmpty == true) ...[
                  SizedBox(height: 4.h),
                  Text(
                    importItem!.message!.trim(),
                    style: GoogleFonts.inter(
                      fontSize: 11.sp,
                      color: palette.subtitle,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            student.score == null
                ? '--'
                : '${student.score!.toStringAsFixed(1)} / ${student.maxScore?.toStringAsFixed(1) ?? '--'}',
            style: GoogleFonts.sairaCondensed(
              fontSize: 20.sp,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _studentStatusText(String? importStatus) {
    if (importStatus != null && importStatus.isNotEmpty) {
      return switch (importStatus) {
        'will_fill' => 'Importavel',
        'already_imported' => 'Ja importado',
        'already_same' => 'Ja igual no boletim',
        'conflict_existing_test_score' => 'Conflito',
        'missing_exam_sheet' => 'Sem folha',
        'pending_exam_result' => 'Pendente de correcao',
        'score_scale_conflict' => 'Bloqueado: escala',
        'final_score_exceeds_10' => 'Bloqueado: media acima de 10',
        'report_card_locked' => 'Bloqueado: boletim fechado',
        'subject_not_found' => 'Bloqueado: disciplina nao encontrada',
        'missing_report_card' => 'Bloqueado: boletim nao encontrado',
        'permission_required' => 'Bloqueado: permissao',
        _ => importStatus,
      };
    }
    return student.sheetId == null
        ? 'Sem folha'
        : (student.isCorrected ? 'Corrigido' : 'Pendente');
  }
}

class _PreviewItemCard extends StatelessWidget {
  final ImportPreviewItem item;
  final _ExamPalette palette;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;
  final String? conflictAction;
  final ValueChanged<String?>? onConflictActionChanged;

  const _PreviewItemCard({
    required this.item,
    required this.palette,
    required this.selected,
    this.onSelectedChanged,
    this.conflictAction,
    this.onConflictActionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (item.status) {
      'will_fill' => palette.accentGreen,
      'already_same' || 'already_imported' => palette.accentBlue,
      'conflict_existing_test_score' => palette.accentOrange,
      _ => palette.muted,
    };
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(
            color: item.blocked ? palette.accentRed : palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (onSelectedChanged != null)
                Checkbox(value: selected, onChanged: onSelectedChanged),
              Expanded(
                child: Text(item.studentName,
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800, color: palette.title)),
              ),
              _StatusDot(label: _statusLabel(item.status), color: color),
            ],
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _InfoChip('Prova: ${_score(item.examGrade)}', palette),
              _InfoChip('Atual: ${_score(item.currentTestScore)}', palette),
              _InfoChip('Ativ.: ${_score(item.activityScore)}', palette),
              _InfoChip('Partic.: ${_score(item.participationScore)}', palette),
              _InfoChip('Média: ${_score(item.predictedFinalScore)}', palette),
            ],
          ),
          if (item.message?.isNotEmpty == true) ...[
            SizedBox(height: 8.h),
            Text(item.message!,
                style: GoogleFonts.inter(
                    fontSize: 12.sp, color: palette.subtitle)),
          ],
          if (onConflictActionChanged != null) ...[
            SizedBox(height: 8.h),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ignore', label: Text('Manter')),
                ButtonSegment(value: 'overwrite', label: Text('Substituir')),
              ],
              selected: {conflictAction ?? 'ignore'},
              onSelectionChanged: (values) =>
                  onConflictActionChanged!(values.first),
            ),
          ],
        ],
      ),
    );
  }

  String _score(double? value) =>
      value == null ? '--' : value.toStringAsFixed(1);

  String _statusLabel(String status) {
    return switch (status) {
      'will_fill' => 'Preencher',
      'already_same' || 'already_imported' => 'Igual',
      'conflict_existing_test_score' => 'Conflito',
      'final_score_exceeds_10' => 'Acima de 10',
      'report_card_locked' => 'Bloqueado',
      'term_mismatch' => 'Bimestre',
      'missing_exam_sheet' => 'Sem folha',
      'pending_exam_result' => 'Pendente',
      _ => status,
    };
  }
}

class _CommitResultDialog extends StatelessWidget {
  final ReportCardExamImportCommitResult result;

  const _CommitResultDialog({required this.result});

  @override
  Widget build(BuildContext context) {
    final summary = result.summary;
    return AlertDialog(
      title: const Text('Importação concluída'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Lote: ${result.batchId}'),
          const SizedBox(height: 8),
          Text('Atualizados: ${summary['updatedCount'] ?? 0}'),
          Text('Ignorados: ${summary['ignoredCount'] ?? 0}'),
          Text('Conflitos: ${summary['conflictCount'] ?? 0}'),
          Text('Bloqueados: ${summary['blockedCount'] ?? 0}'),
          Text('No-op: ${summary['noopCount'] ?? 0}'),
          if (result.reused) const Text('Este lote já havia sido processado.'),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String text;
  final _ExamPalette palette;

  const _InfoChip(this.text, this.palette);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(9.r),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          color: palette.subtitle,
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final int value;
  final Color color;
  final _ExamPalette palette;

  const _MetricPill(this.label, this.value, this.color, this.palette);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Text(
        '$label $value',
        style: GoogleFonts.inter(
          fontSize: 12.sp,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _SmallCounter extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final _ExamPalette palette;

  const _SmallCounter(this.label, this.value, this.color, this.palette);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(8.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Column(
        children: [
          Text(value,
              style: GoogleFonts.sairaCondensed(
                  fontSize: 20.sp, fontWeight: FontWeight.w900, color: color)),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style:
                  GoogleFonts.inter(fontSize: 10.sp, color: palette.subtitle)),
        ],
      ),
    );
  }
}

class _StatusDot extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusDot({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 5.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11.sp, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  final String message;
  final _ExamPalette palette;

  const _ErrorBox({required this.message, required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: Colors.red.withValues(alpha: 0.20)),
      ),
      child: Text(message, style: TextStyle(color: Colors.red.shade700)),
    );
  }
}

class _EmptyBox extends StatelessWidget {
  final _ExamPalette palette;
  final String title;
  final String message;

  const _EmptyBox({
    required this.palette,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(PhosphorIcons.exam, size: 38.sp, color: palette.muted),
          SizedBox(height: 10.h),
          Text(title,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900, color: palette.title)),
          SizedBox(height: 4.h),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(color: palette.subtitle)),
        ],
      ),
    );
  }
}
