import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/model_alunos.dart';
import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:academyhub_mobile/model/schoolyear_model.dart';
import 'package:academyhub_mobile/model/term_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/class_provider.dart';
import 'package:academyhub_mobile/providers/report_card_provider.dart';
import 'package:academyhub_mobile/providers/student_provider.dart';
import 'package:academyhub_mobile/providers/horario_provider.dart'; // NOVO IMPORT
import 'package:academyhub_mobile/screens/teacher/screen_report_card_detail.dart';
import 'package:academyhub_mobile/util/early_childhood_criteria_helper.dart';
import 'package:academyhub_mobile/util/report_card_evaluation_mode_helper.dart';
import 'package:academyhub_mobile/util/report_card_filter_store.dart';
import 'package:academyhub_mobile/util/teacher_class_context_helper.dart';
import 'package:academyhub_mobile/widgets/report_card_operation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class ScreenReportCards extends StatefulWidget {
  const ScreenReportCards({super.key});

  @override
  State<ScreenReportCards> createState() => _ScreenReportCardsState();
}

class _ScreenReportCardsState extends State<ScreenReportCards> {
  final TextEditingController _searchController = TextEditingController();

  bool _initialLoading = true;
  String? _error;
  String? _loadedSignature;
  int _cardRequest = 0;
  String? _filterScope;

  String _schoolYear = '';
  String _term = '';
  String _className = '';
  String _classId = '';
  String _status = 'Todos';

  _ReportCardRowData? _selectedDetail;

  final List<String> _statusItems = const [
    'Todos',
    'Rascunho',
    'Parcial',
    'Completo',
    'Aguardando Conferência',
    'Liberado',
  ];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      if (mounted) setState(() {});
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _bootstrap();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ClassModel> _getAvailableClasses(
    BuildContext context,
    List<ClassModel> allClasses,
    dynamic user,
  ) {
    if (user == null) return [];

    try {
      String role = '';
      try {
        role = user.role?.toString() ?? '';
      } catch (_) {}
      if (role.isEmpty) {
        try {
          role = user.type?.toString() ?? '';
        } catch (_) {}
      }
      if (role.isEmpty) {
        try {
          role = user.perfil?.toString() ?? '';
        } catch (_) {}
      }

      final isGestor = role.toLowerCase() == 'admin' ||
          role.toLowerCase() == 'diretor' ||
          role.toLowerCase() == 'administrador';

      if (isGestor) {
        return allClasses;
      }

      final horariosProvider = context.read<HorarioProvider>();
      final academicProvider = context.read<AcademicCalendarProvider>();
      return TeacherClassContextHelper.getAvailableClasses(
        classes: allClasses,
        horarios: horariosProvider.horarios,
        user: user,
        terms: academicProvider.terms,
        sharedAcrossPeriods: true,
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _bootstrap({bool forceReload = false}) async {
    if (mounted) {
      setState(() {
        _initialLoading = true;
        _error = null;
      });
    }

    try {
      if (!mounted) return;
      var auth = context.read<AuthProvider>();
      var academic = context.read<AcademicCalendarProvider>();
      var classesProvider = context.read<ClassProvider>();
      var students = context.read<StudentProvider>();
      var horarios = context.read<HorarioProvider>(); // NOVO

      if (auth.token != null) {
        final userId = auth.user?.id ?? '';
        final schoolId = auth.user?.schoolId ?? '';
        final scope = '$schoolId|$userId';
        if (_filterScope != scope) {
          final saved = await ReportCardFilterStore.load(
            userId: userId,
            schoolId: schoolId,
          );
          if (!mounted) return;
          _filterScope = scope;
          _schoolYear = saved['year'] ?? '';
          _term = saved['term'] ?? '';
          _classId = saved['classId'] ?? '';
          _status = _statusItems.contains(saved['status'])
              ? saved['status']!
              : 'Todos';
        }
        if (academic.schoolYears.isEmpty) {
          await academic.fetchSchoolYears();
        }
        if (!mounted) return;

        // Atualizamos as referências logo após o await para evitar o erro "used after being disposed"
        academic = context.read<AcademicCalendarProvider>();
        classesProvider = context.read<ClassProvider>();

        if (classesProvider.classes.isEmpty) {
          await classesProvider.fetchClasses(auth.token!);
        }
        if (!mounted) return;

        students = context.read<StudentProvider>();

        if (students.students.isEmpty) {
          await students.fetchStudents(auth.token!);
        }
        if (!mounted) return;

        academic = context.read<AcademicCalendarProvider>();

        final matchingSavedYear = academic.schoolYears
            .where((year) => year.year.toString() == _schoolYear)
            .toList();
        final selectedYear = academic.selectedSchoolYear;
        final resolvedYear = matchingSavedYear.isNotEmpty
            ? matchingSavedYear.first
            : selectedYear != null &&
                    academic.schoolYears
                        .any((year) => year.id == selectedYear.id)
                ? selectedYear
                : _resolveSchoolYear(academic.schoolYears);
        if (resolvedYear != null) {
          if (academic.selectedSchoolYear?.id != resolvedYear.id) {
            academic.selectSchoolYear(resolvedYear);
          }
          if (academic.terms.isEmpty ||
              academic.selectedSchoolYear?.id != resolvedYear.id) {
            await academic.fetchTermsForSelectedYear();
          }
        }
        if (!mounted) return;

        horarios = context.read<HorarioProvider>();
        await TeacherClassContextHelper.ensureDataLoaded(
          authProvider: auth,
          classProvider: classesProvider,
          horarioProvider: horarios,
          academicProvider: academic,
          forceRefresh: forceReload || horarios.horarios.isEmpty,
          sharedAcrossPeriods: true,
          screen: 'report_cards',
        );
        if (classesProvider.error != null) {
          throw StateError(classesProvider.error!);
        }
        if (horarios.error != null) {
          throw StateError(horarios.error!);
        }
      }

      if (!mounted) return;

      // Garantimos que tudo está atualizado antes de construir a UI
      auth = context.read<AuthProvider>();
      academic = context.read<AcademicCalendarProvider>();
      classesProvider = context.read<ClassProvider>();
      final cards = context.read<ReportCardProvider>();

      final availableClasses =
          _getAvailableClasses(context, classesProvider.classes, auth.user);

      setState(() {
        _syncSelections(
          schoolYears: academic.schoolYears,
          terms: academic.terms,
          classes: availableClasses,
        );
      });

      final selectedYear = _selectedSchoolYearModel(academic.schoolYears);
      final selectedTerm = _selectedTermModel(academic.terms);
      final selectedClass = _selectedClassModel(availableClasses);

      if (auth.token != null &&
          selectedYear != null &&
          selectedTerm != null &&
          selectedClass != null) {
        await _loadCards(
          force: forceReload || cards.classReportCards.isEmpty,
          classesList: availableClasses,
        );
      } else if (cards.classReportCards.isEmpty) {
        _error = auth.token == null
            ? 'Faça login para carregar os boletins.'
            : 'Selecione o ano letivo, o período e a turma para visualizar os boletins.';
      }
    } catch (e) {
      if (!mounted) return;
      _error = _normalizeError(e);
    } finally {
      if (mounted) {
        setState(() => _initialLoading = false);
      }
    }
  }

  Future<void> _refresh() async {
    await showReportCardOperationDialog(
      context: context,
      operation: () => _bootstrap(forceReload: true),
      loadingTitle: 'Atualizando boletins',
      loadingMessage: 'Recarregando dados do ano letivo, turma e período.',
      loadingDetail: 'Sincronizando a central de boletins com a API.',
      successTitle: 'Atualização concluída',
      successMessage: 'Os boletins foram atualizados com sucesso.',
    );
  }

  Future<void> _generate() async {
    final auth = context.read<AuthProvider>();
    final classesProvider = context.read<ClassProvider>();
    final availableClasses =
        _getAvailableClasses(context, classesProvider.classes, auth.user);

    await showReportCardOperationDialog(
      context: context,
      operation: () => _loadCards(force: true, classesList: availableClasses),
      loadingTitle: 'Gerando boletins',
      loadingMessage: 'Montando os boletins consolidados da turma.',
      loadingDetail: 'A API está consolidando alunos, notas e status.',
      successTitle: 'Boletins prontos',
      successMessage: 'A turma foi processada com sucesso.',
    );
  }

  String _normalizeError(Object error) {
    final errStr = error.toString();
    if (errStr.contains('<!DOCTYPE html>') ||
        errStr.contains('Unexpected character')) {
      return 'O servidor retornou uma página inválida (HTML) em vez de dados (JSON). Verifique se a rota da API está correta ou se o servidor está online.';
    }
    return errStr.replaceFirst('Exception: ', '').trim();
  }

  SchoolYearModel? _resolveSchoolYear(List<SchoolYearModel> years) {
    if (years.isEmpty) return null;
    final current = DateTime.now().year;
    for (final year in years) {
      if (year.year == current) return year;
    }
    return years.first;
  }

  TermModel? _preferredTerm(List<TermModel> terms) {
    if (terms.isEmpty) return null;
    final now = DateTime.now();
    for (final term in terms) {
      final inRange =
          (now.isAfter(term.startDate) || _sameDay(now, term.startDate)) &&
              (now.isBefore(term.endDate) || _sameDay(now, term.endDate));
      if (inRange) return term;
    }
    return terms.first;
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  List<String> _yearItems(List<SchoolYearModel> years) =>
      years.map((e) => e.year.toString()).toList();

  List<String> _termItems(List<TermModel> terms) =>
      terms.map((e) => e.titulo).toList();

  List<String> _classItems(List<ClassModel> classes, String yearLabel) {
    final year = int.tryParse(yearLabel);
    final filtered = year == null
        ? classes
        : classes.where((c) => c.schoolYear == year).toList();
    final source = filtered.isNotEmpty ? filtered : classes;
    return source.map((e) => e.id).toSet().toList();
  }

  void _syncSelections({
    required List<SchoolYearModel> schoolYears,
    required List<TermModel> terms,
    required List<ClassModel> classes,
  }) {
    final years = _yearItems(schoolYears);
    if (_schoolYear.isEmpty || !years.contains(_schoolYear)) {
      _schoolYear = years.isNotEmpty ? years.first : '';
    }

    final termLabels = _termItems(terms);
    if (_term.isEmpty || !termLabels.contains(_term)) {
      _term = _preferredTerm(terms)?.titulo ??
          (termLabels.isNotEmpty ? termLabels.first : '');
    }

    final classLabels = _classItems(classes, _schoolYear);
    if (_classId.isEmpty || !classLabels.contains(_classId)) {
      _classId = classLabels.isNotEmpty ? classLabels.first : '';
    }
    _className = _selectedClassModel(classes)?.name ?? '';
  }

  SchoolYearModel? _selectedSchoolYearModel(List<SchoolYearModel> years) {
    if (years.isEmpty) return null;
    for (final year in years) {
      if (year.year.toString() == _schoolYear) return year;
    }
    return years.first;
  }

  TermModel? _selectedTermModel(List<TermModel> terms) {
    if (terms.isEmpty) return null;
    for (final term in terms) {
      if (term.titulo == _term) return term;
    }
    return terms.first;
  }

  ClassModel? _selectedClassModel(List<ClassModel> classes) {
    if (classes.isEmpty) return null;
    final year = int.tryParse(_schoolYear);
    final source = year == null
        ? classes
        : classes.where((c) => c.schoolYear == year).toList();
    final available = source.isNotEmpty ? source : classes;
    for (final classItem in available) {
      if (classItem.id == _classId) return classItem;
    }
    return available.first;
  }

  Future<void> _loadCards({
    required bool force,
    required List<ClassModel> classesList,
  }) async {
    final auth = context.read<AuthProvider>();
    final cards = context.read<ReportCardProvider>();
    final academic = context.read<AcademicCalendarProvider>();

    final year = _selectedSchoolYearModel(academic.schoolYears);
    final term = _selectedTermModel(academic.terms);
    final classItem = _selectedClassModel(classesList);

    if (auth.token == null ||
        year == null ||
        term == null ||
        classItem == null) {
      if (!mounted) return;
      setState(() {
        _error = auth.token == null
            ? 'Faça login para carregar os boletins.'
            : 'Selecione o ano letivo, o período e a turma para visualizar os boletins.';
      });
      return;
    }

    final signature =
        '${auth.user?.id}|${auth.user?.schoolId}|${year.id}|${term.id}|${classItem.id}';

    if (!force &&
        _loadedSignature == signature &&
        cards.classReportCards.isNotEmpty) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _error = null;
    });

    final request = ++_cardRequest;
    try {
      await cards.generateClassReportCards(
        token: auth.token!,
        classId: classItem.id,
        termId: term.id,
        schoolYear: year.year,
      );
      if (mounted && request == _cardRequest) _loadedSignature = signature;
    } catch (e) {
      if (!mounted || request != _cardRequest) return;
      setState(() {
        _loadedSignature = null;
        _error = _normalizeError(e);
      });
    }
  }

  String _statusFor(ReportCardModel card) {
    if (card.totalSubjectsCount == 0 || card.filledSubjectsCount == 0) {
      return 'Rascunho';
    }
    if (card.hasPendingSubjects) return 'Parcial';
    return 'Completo';
  }

  String _getGuardianName(ReportCardModel card, Map<String, Student> students) {
    if (card.responsibleNameSnapshot.isNotEmpty &&
        card.responsibleNameSnapshot != 'Responsável não informado') {
      return card.responsibleNameSnapshot;
    }

    final student = students[card.studentId];
    if (student != null && student.tutors.isNotEmpty) {
      return student.tutors.first.tutorInfo.fullName;
    }

    return 'Responsável não informado';
  }

  List<_ReportCardRowData> _rows({
    required List<ReportCardModel> cardsList,
    required List<Student> students,
    required List<ClassModel> classes,
    required List<TermModel> terms,
  }) {
    final studentMap = {for (final s in students) s.id: s};
    final classNames = {for (final c in classes) c.id: c.name};
    final classesById = {for (final c in classes) c.id: c};
    final termNames = {for (final t in terms) t.id: t.titulo};

    return cardsList.map((card) {
      final student = studentMap[card.studentId];
      final className = classNames[card.classId] ??
          (_className.isNotEmpty ? _className : 'Turma');
      final isDevelopmental = ReportCardEvaluationModeHelper.isDevelopmental(
        reportCard: card,
        classModel: classesById[card.classId],
        className: className,
      );
      final average = isDevelopmental ? null : card.averageScore;
      final hasPending = isDevelopmental
          ? EarlyChildhoodCriteriaHelper.hasPendingCriteria(card)
          : card.hasPendingSubjects;

      return _ReportCardRowData(
        reportCard: card,
        studentName: card.studentNameSnapshot.isNotEmpty
            ? card.studentNameSnapshot
            : (student?.fullName ?? 'Aluno não localizado'),
        guardianName: _getGuardianName(card, studentMap),
        className: className,
        schoolYearLabel: card.schoolYear.toString(),
        termLabel:
            termNames[card.termId] ?? (_term.isNotEmpty ? _term : 'Período'),
        progress: isDevelopmental
            ? EarlyChildhoodCriteriaHelper.completedAreasCount(card)
            : card.filledSubjectsCount,
        totalSubjects: card.totalSubjectsCount,
        average: average,
        status: card.status.isNotEmpty ? card.status : _statusFor(card),
        needsAttention: hasPending ||
            (!isDevelopmental &&
                average != null &&
                average < card.minimumAverage),
        isDevelopmental: isDevelopmental,
      );
    }).toList();
  }

  List<_ReportCardRowData> _filteredRows(List<_ReportCardRowData> rows) {
    final query = _searchController.text.trim().toLowerCase();

    return rows.where((row) {
      final matchesStatus = _status == 'Todos' || row.status == _status;
      final matchesClass =
          _classId.isEmpty || row.reportCard.classId == _classId;
      final matchesQuery = query.isEmpty ||
          row.studentName.toLowerCase().contains(query) ||
          row.guardianName.toLowerCase().contains(query);

      return matchesStatus && matchesClass && matchesQuery;
    }).toList();
  }

  void _openDetail(_ReportCardRowData row) {
    setState(() {
      _selectedDetail = row;
    });
  }

  void _closeDetail() {
    setState(() {
      _selectedDetail = null;
    });
  }

  Future<void> _openFiltersBottomSheet({
    required _Palette palette,
    required List<String> yearItems,
    required List<String> termItems,
    required List<String> classItems,
  }) async {
    String tempYear = _schoolYear;
    String tempTerm = _term;
    String tempClass = _classId;
    String tempStatus = _status;

    await showModalBottomSheet(
      context: context,
      backgroundColor: palette.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
      ),
      builder: (sheetContext) {
        final academic = context.read<AcademicCalendarProvider>();
        final classProvider = context.read<ClassProvider>();
        final auth = context.read<AuthProvider>();

        return StatefulBuilder(
          builder: (context, setModalState) {
            final currentTermItems = tempYear == _schoolYear
                ? termItems
                : _termItems(academic.terms);
            final currentClassItems = _classItems(
              _getAvailableClasses(context, classProvider.classes, auth.user),
              tempYear,
            );

            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20.w,
                  18.h,
                  20.w,
                  20.h + MediaQuery.of(context).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 42.w,
                      height: 5.h,
                      decoration: BoxDecoration(
                        color: palette.border,
                        borderRadius: BorderRadius.circular(99.r),
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Filtrar boletins',
                            style: GoogleFonts.sairaCondensed(
                              fontSize: 24.sp,
                              fontWeight: FontWeight.w700,
                              color: palette.title,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            setModalState(() {
                              tempYear =
                                  yearItems.isNotEmpty ? yearItems.first : '';
                              tempTerm = currentTermItems.isNotEmpty
                                  ? currentTermItems.first
                                  : '';
                              tempClass = currentClassItems.isNotEmpty
                                  ? currentClassItems.first
                                  : '';
                              tempStatus = 'Todos';
                            });
                          },
                          child: Text(
                            'Limpar',
                            style: GoogleFonts.inter(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w700,
                              color: palette.accentBlue,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 8.h),
                    _BottomSheetDropdown(
                      label: 'Ano letivo',
                      icon: PhosphorIcons.calendar_blank,
                      value: tempYear,
                      items: yearItems,
                      palette: palette,
                      onChanged: (value) async {
                        if (value == null || value.isEmpty) return;

                        final academicProvider =
                            context.read<AcademicCalendarProvider>();
                        final resolvedYear = academic.schoolYears.firstWhere(
                          (year) => year.year.toString() == value,
                          orElse: () => academic.schoolYears.first,
                        );

                        academicProvider.selectSchoolYear(resolvedYear);
                        await academicProvider.fetchTermsForSelectedYear();
                        if (!context.mounted) return;

                        final refreshedTerms =
                            _termItems(academicProvider.terms);
                        final refreshedClasses = _classItems(
                          _getAvailableClasses(
                            context,
                            classProvider.classes,
                            auth.user,
                          ),
                          value,
                        );

                        setModalState(() {
                          tempYear = value;
                          tempTerm = refreshedTerms.isNotEmpty
                              ? refreshedTerms.first
                              : '';
                          tempClass = refreshedClasses.isNotEmpty
                              ? refreshedClasses.first
                              : '';
                        });
                      },
                    ),
                    SizedBox(height: 12.h),
                    _BottomSheetDropdown(
                      label: 'Período',
                      icon: PhosphorIcons.clock_counter_clockwise,
                      value: tempTerm,
                      items: currentTermItems,
                      palette: palette,
                      onChanged: (value) {
                        if (value == null || value.isEmpty) return;
                        setModalState(() => tempTerm = value);
                      },
                    ),
                    SizedBox(height: 12.h),
                    _BottomSheetDropdown(
                      label: 'Turma',
                      icon: PhosphorIcons.chalkboard_teacher,
                      value: tempClass,
                      items: currentClassItems,
                      itemLabel: (id) {
                        for (final item in _getAvailableClasses(
                            context, classProvider.classes, auth.user)) {
                          if (item.id == id) return item.name;
                        }
                        return id;
                      },
                      palette: palette,
                      onChanged: (value) {
                        if (value == null || value.isEmpty) return;
                        setModalState(() => tempClass = value);
                      },
                    ),
                    SizedBox(height: 12.h),
                    _BottomSheetDropdown(
                      label: 'Situação',
                      icon: PhosphorIcons.funnel_simple,
                      value: tempStatus,
                      items: _statusItems,
                      palette: palette,
                      onChanged: (value) {
                        if (value == null || value.isEmpty) return;
                        setModalState(() => tempStatus = value);
                      },
                    ),
                    SizedBox(height: 18.h),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            style: OutlinedButton.styleFrom(
                              minimumSize: Size(double.infinity, 50.h),
                              side: BorderSide(color: palette.border),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r),
                              ),
                            ),
                            child: Text(
                              'Cancelar',
                              style: GoogleFonts.inter(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: palette.title,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(sheetContext).pop();

                              setState(() {
                                _schoolYear = tempYear;
                                _term = tempTerm;
                                _classId = tempClass;
                                _className = _selectedClassModel(
                                      _getAvailableClasses(context,
                                          classProvider.classes, auth.user),
                                    )?.name ??
                                    '';
                                _status = tempStatus;
                              });

                              await ReportCardFilterStore.save(
                                userId: auth.user?.id ?? '',
                                schoolId: auth.user?.schoolId ?? '',
                                year: _schoolYear,
                                term: _term,
                                classId: _classId,
                                status: _status,
                              );
                              if (!mounted) return;

                              await _loadCards(
                                force: true,
                                classesList: _getAvailableClasses(
                                  this.context,
                                  classProvider.classes,
                                  auth.user,
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: palette.accentGreen,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              minimumSize: Size(double.infinity, 50.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14.r),
                              ),
                            ),
                            child: Text(
                              'Aplicar filtros',
                              style: GoogleFonts.inter(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() {});
  }

  Widget _buildListContent(
      _Palette palette,
      List<_ReportCardRowData> filtered,
      int totalCount,
      int draftCount,
      int partialCount,
      int completeCount,
      bool isBusy,
      AcademicCalendarProvider academic,
      List<ClassModel> availableClasses) {
    return Scaffold(
      backgroundColor: palette.page,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: isBusy ? null : _generate,
        backgroundColor: palette.accentGreen,
        foregroundColor: Colors.white,
        icon: Icon(PhosphorIcons.magic_wand, size: 18.sp),
        label: Text(
          'Gerar',
          style: GoogleFonts.inter(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: palette.accentBlue,
          backgroundColor: palette.surface,
          onRefresh: _refresh,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(16.w, 14.h, 16.w, 110.h),
            children: [
              _MobileHeader(
                palette: palette,
                onRefresh: _refresh,
              ),
              SizedBox(height: 16.h),
              _HeroSummaryCard(
                palette: palette,
                selectedYear: _schoolYear,
                selectedTerm: _term,
                selectedClass: _className,
                totalCount: totalCount,
              ),
              SizedBox(height: 16.h),
              _SearchAndFilterBar(
                palette: palette,
                controller: _searchController,
                onClear: _clearSearch,
                onOpenFilters: () => _openFiltersBottomSheet(
                  palette: palette,
                  yearItems: _yearItems(academic.schoolYears),
                  termItems: _termItems(academic.terms),
                  classItems: _classItems(availableClasses, _schoolYear),
                ),
              ),
              SizedBox(height: 12.h),
              _ActiveFilterChips(
                palette: palette,
                year: _schoolYear,
                term: _term,
                className: _className,
                status: _status,
              ),
              SizedBox(height: 16.h),
              _MetricsHorizontal(
                palette: palette,
                totalCount: totalCount,
                draftCount: draftCount,
                partialCount: partialCount,
                completeCount: completeCount,
              ),
              SizedBox(height: 18.h),
              if (_error != null && filtered.isEmpty)
                _ErrorCardMobile(
                  palette: palette,
                  message: _error!,
                  onRetry: _refresh,
                )
              else if (isBusy && filtered.isEmpty)
                _LoadingState(palette: palette)
              else if (filtered.isEmpty)
                _EmptyState(palette: palette)
              else ...[
                Padding(
                  padding: EdgeInsets.only(bottom: 10.h),
                  child: Text(
                    'Alunos',
                    style: GoogleFonts.sairaCondensed(
                      fontSize: 24.sp,
                      fontWeight: FontWeight.w700,
                      color: palette.title,
                    ),
                  ),
                ),
                ...filtered.map(
                  (row) => Padding(
                    padding: EdgeInsets.only(bottom: 12.h),
                    child: _StudentReportCard(
                      data: row,
                      palette: palette,
                      onOpen: () => _openDetail(row),
                      onReview: () => _openDetail(row),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = _Palette(isDark);

    final cards = context.watch<ReportCardProvider>();
    final students = context.watch<StudentProvider>();
    final classesProvider = context.watch<ClassProvider>();
    final academic = context.watch<AcademicCalendarProvider>();
    final auth = context.watch<AuthProvider>();
    context.watch<HorarioProvider>();

    final availableClasses =
        _getAvailableClasses(context, classesProvider.classes, auth.user);

    final rows = _rows(
      cardsList: cards.classReportCards,
      students: students.students,
      classes: availableClasses,
      terms: academic.terms,
    );

    final filtered = _filteredRows(rows);
    final isBusy = _initialLoading || cards.isGenerating;

    final totalCount = filtered.length;
    final draftCount = filtered.where((e) => e.status == 'Rascunho').length;
    final partialCount = filtered.where((e) => e.status == 'Parcial').length;
    final completeCount = filtered.where((e) => e.status == 'Completo').length;

    Widget currentView;

    if (_selectedDetail != null) {
      currentView = PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _closeDetail();
          }
        },
        child: Padding(
          padding: EdgeInsets.only(
              bottom: 80.h), // Margem para respeitar o seu SpeedDialMenu
          child: ScreenReportCardDetail(
            key: const ValueKey('detail_view'),
            reportCard: _selectedDetail!.reportCard,
            studentName: _selectedDetail!.studentName,
            guardianName: _selectedDetail!.guardianName,
            className: _selectedDetail!.className,
            schoolYear: _selectedDetail!.schoolYearLabel,
            termLabel: _selectedDetail!.termLabel,
            isDevelopmental: _selectedDetail!.isDevelopmental,
            onClose: _closeDetail,
          ),
        ),
      );
    } else {
      currentView = KeyedSubtree(
        key: const ValueKey('list_view'),
        child: _buildListContent(palette, filtered, totalCount, draftCount,
            partialCount, completeCount, isBusy, academic, availableClasses),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: currentView,
    );
  }
}

class _Palette {
  final bool isDark;
  _Palette(this.isDark);

  Color get page => isDark ? const Color(0xFF111214) : const Color(0xFFF5F7FB);
  Color get surface => isDark ? const Color(0xFF17191C) : Colors.white;
  Color get surfaceAlt =>
      isDark ? const Color(0xFF1D2024) : const Color(0xFFF8FAFD);
  Color get input => isDark ? const Color(0xFF202328) : const Color(0xFFF4F6FA);
  Color get border =>
      isDark ? const Color(0xFF2A2E34) : const Color(0xFFE7EBF2);
  Color get divider =>
      isDark ? const Color(0xFF24282E) : const Color(0xFFEDF1F6);
  Color get title => isDark ? Colors.white : const Color(0xFF1A2230);
  Color get subtitle =>
      isDark ? const Color(0xFF9CA4B2) : const Color(0xFF7C889B);
  Color get muted => isDark ? const Color(0xFF7D8796) : const Color(0xFF98A2B3);
  Color get iconSurface =>
      isDark ? const Color(0xFF1F2328) : const Color(0xFFF2F6FD);

  Color get accentBlue => const Color(0xFF2F80ED);
  Color get accentGreen => const Color(0xFF2DBE60);
  Color get accentOrange => const Color(0xFFF2994A);
  Color get accentAmber => const Color(0xFFE9A23B);
  Color get accentRed => const Color(0xFFE05555);
  Color get accentPurple => const Color(0xFF7A5AF8);
}

class _ReportCardRowData {
  final ReportCardModel reportCard;
  final String studentName;
  final String guardianName;
  final String className;
  final String schoolYearLabel;
  final String termLabel;
  final int progress;
  final int totalSubjects;
  final double? average;
  final String status;
  final bool needsAttention;
  final bool isDevelopmental;

  const _ReportCardRowData({
    required this.reportCard,
    required this.studentName,
    required this.guardianName,
    required this.className,
    required this.schoolYearLabel,
    required this.termLabel,
    required this.progress,
    required this.totalSubjects,
    required this.average,
    required this.status,
    required this.needsAttention,
    required this.isDevelopmental,
  });
}

class _MobileHeader extends StatelessWidget {
  final _Palette palette;
  final VoidCallback onRefresh;

  const _MobileHeader({
    required this.palette,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Boletim Bimestral',
                style: GoogleFonts.sairaCondensed(
                  fontSize: 29.sp,
                  fontWeight: FontWeight.w700,
                  color: palette.title,
                  height: 1,
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                'Consulte a turma, revise pendências e abra o boletim do aluno.',
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: palette.subtitle,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 12.w),
        InkWell(
          onTap: onRefresh,
          borderRadius: BorderRadius.circular(14.r),
          child: Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(14.r),
              border: Border.all(color: palette.border),
            ),
            child: Icon(
              PhosphorIcons.arrow_clockwise,
              size: 20.sp,
              color: palette.accentBlue,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroSummaryCard extends StatelessWidget {
  final _Palette palette;
  final String selectedYear;
  final String selectedTerm;
  final String selectedClass;
  final int totalCount;

  const _HeroSummaryCard({
    required this.palette,
    required this.selectedYear,
    required this.selectedTerm,
    required this.selectedClass,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22.r),
        color: palette.surface,
        border: Border.all(color: palette.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(palette.isDark ? 0.12 : 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: palette.iconSurface,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(
              PhosphorIcons.file_text,
              size: 22.sp,
              color: palette.accentBlue,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            '$totalCount boletins encontrados',
            style: GoogleFonts.sairaCondensed(
              fontSize: 28.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
              height: 1,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Acompanhe o fechamento da turma e abra cada aluno para revisar os lançamentos.',
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
            ),
          ),
          SizedBox(height: 14.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: [
              _MiniTag(
                palette: palette,
                label: selectedYear.isEmpty ? 'Ano' : 'Ano $selectedYear',
                color: palette.accentBlue,
              ),
              _MiniTag(
                palette: palette,
                label: selectedClass.isEmpty ? 'Turma' : selectedClass,
                color: palette.accentGreen,
              ),
              _MiniTag(
                palette: palette,
                label: selectedTerm.isEmpty ? 'Período' : selectedTerm,
                color: palette.accentPurple,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilterBar extends StatelessWidget {
  final _Palette palette;
  final TextEditingController controller;
  final VoidCallback onClear;
  final VoidCallback onOpenFilters;

  const _SearchAndFilterBar({
    required this.palette,
    required this.controller,
    required this.onClear,
    required this.onOpenFilters,
  });

  @override
  Widget build(BuildContext context) {
    final hasText = controller.text.trim().isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: Container(
            height: 52.h,
            padding: EdgeInsets.symmetric(horizontal: 14.w),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.magnifying_glass,
                  size: 18.sp,
                  color: palette.muted,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: TextField(
                    controller: controller,
                    style: GoogleFonts.inter(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w600,
                      color: palette.title,
                    ),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Buscar aluno ou responsável',
                      hintStyle: GoogleFonts.inter(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w500,
                        color: palette.muted,
                      ),
                    ),
                  ),
                ),
                if (hasText)
                  InkWell(
                    onTap: onClear,
                    child: Icon(
                      PhosphorIcons.x_circle_fill,
                      size: 18.sp,
                      color: palette.muted,
                    ),
                  ),
              ],
            ),
          ),
        ),
        SizedBox(width: 10.w),
        InkWell(
          onTap: onOpenFilters,
          borderRadius: BorderRadius.circular(16.r),
          child: Container(
            width: 54.w,
            height: 52.h,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(16.r),
              border: Border.all(color: palette.border),
            ),
            child: Icon(
              PhosphorIcons.sliders_horizontal,
              size: 20.sp,
              color: palette.accentBlue,
            ),
          ),
        ),
      ],
    );
  }
}

class _ActiveFilterChips extends StatelessWidget {
  final _Palette palette;
  final String year;
  final String term;
  final String className;
  final String status;

  const _ActiveFilterChips({
    required this.palette,
    required this.year,
    required this.term,
    required this.className,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      if (year.isNotEmpty)
        _MiniTag(
          palette: palette,
          label: 'Ano $year',
          color: palette.accentBlue,
        ),
      if (term.isNotEmpty)
        _MiniTag(
          palette: palette,
          label: term,
          color: palette.accentPurple,
        ),
      if (className.isNotEmpty)
        _MiniTag(
          palette: palette,
          label: className,
          color: palette.accentGreen,
        ),
      if (status.isNotEmpty && status != 'Todos')
        _MiniTag(
          palette: palette,
          label: status,
          color: palette.accentOrange,
        ),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 8.w,
      runSpacing: 8.h,
      children: chips,
    );
  }
}

class _MetricsHorizontal extends StatelessWidget {
  final _Palette palette;
  final int totalCount;
  final int draftCount;
  final int partialCount;
  final int completeCount;

  const _MetricsHorizontal({
    required this.palette,
    required this.totalCount,
    required this.draftCount,
    required this.partialCount,
    required this.completeCount,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _MetricCardMobile(
            palette: palette,
            title: 'Boletins',
            value: totalCount.toString(),
            subtitle: 'Na lista atual',
            icon: PhosphorIcons.files,
            accent: palette.accentBlue,
          ),
          SizedBox(width: 10.w),
          _MetricCardMobile(
            palette: palette,
            title: 'Rascunho',
            value: draftCount.toString(),
            subtitle: 'Ainda incompletos',
            icon: PhosphorIcons.note_pencil,
            accent: palette.accentOrange,
          ),
          SizedBox(width: 10.w),
          _MetricCardMobile(
            palette: palette,
            title: 'Parcial',
            value: partialCount.toString(),
            subtitle: 'Dependem de outras notas',
            icon: PhosphorIcons.hourglass_medium,
            accent: palette.accentAmber,
          ),
          SizedBox(width: 10.w),
          _MetricCardMobile(
            palette: palette,
            title: 'Completo',
            value: completeCount.toString(),
            subtitle: 'Prontos para revisão',
            icon: PhosphorIcons.check_circle,
            accent: palette.accentGreen,
          ),
        ],
      ),
    );
  }
}

class _MetricCardMobile extends StatelessWidget {
  final _Palette palette;
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color accent;

  const _MetricCardMobile({
    required this.palette,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 168.w,
      margin: EdgeInsets.only(bottom: 8.h),
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: palette.iconSurface,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: accent, size: 18.sp),
          ),
          SizedBox(height: 10.h),
          Text(
            value,
            style: GoogleFonts.sairaCondensed(
              fontSize: 28.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
              height: 1,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
            ),
          ),
          SizedBox(height: 2.h),
          Expanded(
            child: Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w500,
                color: palette.subtitle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StudentReportCard extends StatelessWidget {
  final _ReportCardRowData data;
  final _Palette palette;
  final VoidCallback onOpen;
  final VoidCallback onReview;

  const _StudentReportCard({
    required this.data,
    required this.palette,
    required this.onOpen,
    required this.onReview,
  });

  Color _statusColor() {
    switch (data.status) {
      case 'Completo':
        return palette.accentGreen;
      case 'Parcial':
        return palette.accentOrange;
      case 'Rascunho':
        return palette.muted;
      case 'Aguardando Conferência':
        return palette.accentBlue;
      case 'Liberado':
        return palette.accentPurple;
      default:
        return palette.muted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress =
        data.totalSubjects == 0 ? 0.0 : data.progress / data.totalSubjects;

    final averageColor = data.isDevelopmental
        ? palette.accentBlue
        : data.average == null
            ? palette.muted
            : data.average! >= 7
                ? palette.accentGreen
                : palette.accentRed;

    final statusColor = _statusColor();

    final attentionColor = data.needsAttention
        ? (palette.isDark ? const Color(0xFF2B2318) : const Color(0xFFFFF6E8))
        : palette.surface;

    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        padding: EdgeInsets.all(16.w),
        decoration: BoxDecoration(
          color: attentionColor,
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: data.needsAttention
                ? statusColor.withOpacity(0.22)
                : palette.border,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(palette.isDark ? 0.10 : 0.03),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: palette.iconSurface,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.border),
                  ),
                  child: Center(
                    child: Text(
                      data.studentName.isNotEmpty
                          ? data.studentName.substring(0, 1).toUpperCase()
                          : '?',
                      style: GoogleFonts.inter(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w800,
                        color: palette.accentBlue,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data.studentName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: palette.title,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        data.guardianName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w500,
                          color: palette.subtitle,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 10.w),
                _StatusPill(
                  label: data.status,
                  color: statusColor,
                  palette: palette,
                ),
              ],
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: _InfoBox(
                    palette: palette,
                    label: 'Turma',
                    value: data.className,
                    icon: PhosphorIcons.chalkboard_teacher,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _InfoBox(
                    palette: palette,
                    label: data.isDevelopmental ? 'Modo' : 'Média',
                    value: data.isDevelopmental
                        ? 'Desenvolvimento'
                        : (data.average?.toStringAsFixed(1) ?? '--'),
                    icon: data.isDevelopmental
                        ? PhosphorIcons.tree_structure
                        : PhosphorIcons.chart_bar,
                    valueColor: averageColor,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(14.w),
              decoration: BoxDecoration(
                color: palette.surfaceAlt,
                borderRadius: BorderRadius.circular(16.r),
                border: Border.all(color: palette.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Progresso',
                        style: GoogleFonts.inter(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w700,
                          color: palette.title,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        data.isDevelopmental
                            ? '${data.progress}/${data.totalSubjects} áreas avaliadas'
                            : '${data.progress}/${data.totalSubjects} disciplinas',
                        style: GoogleFonts.inter(
                          fontSize: 12.sp,
                          fontWeight: FontWeight.w600,
                          color: palette.subtitle,
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 10.h),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(99.r),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 8.h,
                      backgroundColor: palette.border,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        progress >= 1
                            ? palette.accentGreen
                            : palette.accentBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 14.h),
            Row(
              children: [
                Expanded(
                  child: _ActionButtonMobile(
                    label: 'Abrir',
                    icon: PhosphorIcons.eye,
                    palette: palette,
                    onTap: onOpen,
                    foreground: palette.accentBlue,
                    background: palette.surfaceAlt,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _ActionButtonMobile(
                    label: 'Revisar',
                    icon: PhosphorIcons.pencil_simple_line,
                    palette: palette,
                    onTap: onReview,
                    foreground: Colors.white,
                    background: palette.accentGreen,
                    borderColor: palette.accentGreen,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  final _Palette palette;
  final String label;
  final String value;
  final IconData icon;
  final Color? valueColor;

  const _InfoBox({
    required this.palette,
    required this.label,
    required this.value,
    required this.icon,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(13.w),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34.w,
            height: 34.w,
            decoration: BoxDecoration(
              color: palette.iconSurface,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 16.sp, color: palette.accentBlue),
          ),
          SizedBox(width: 10.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w600,
                    color: palette.subtitle,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: valueColor ?? palette.title,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final _Palette palette;
  final String label;
  final Color color;

  const _MiniTag({
    required this.palette,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: color.withOpacity(palette.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withOpacity(0.18)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _BottomSheetDropdown extends StatelessWidget {
  final String label;
  final IconData icon;
  final String value;
  final List<String> items;
  final String Function(String)? itemLabel;
  final _Palette palette;
  final ValueChanged<String?> onChanged;

  const _BottomSheetDropdown({
    required this.label,
    required this.icon,
    required this.value,
    required this.items,
    this.itemLabel,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final hasItems = items.isNotEmpty;
    final safeValue = hasItems && items.contains(value)
        ? value
        : (hasItems ? items.first : null);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w),
      decoration: BoxDecoration(
        color: palette.input,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18.sp, color: palette.muted),
          SizedBox(width: 12.w),
          Expanded(
            child: hasItems
                ? DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: safeValue,
                      isExpanded: true,
                      dropdownColor: palette.surface,
                      icon: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: palette.muted,
                      ),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                        color: palette.title,
                      ),
                      items: items
                          .map(
                            (item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(itemLabel?.call(item) ?? item,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          )
                          .toList(),
                      onChanged: onChanged,
                    ),
                  )
                : Padding(
                    padding: EdgeInsets.symmetric(vertical: 16.h),
                    child: Text(
                      '$label indisponível',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w600,
                        color: palette.muted,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;
  final _Palette palette;

  const _StatusPill({
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: color.withOpacity(palette.isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: color.withOpacity(0.16)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _ActionButtonMobile extends StatelessWidget {
  final String label;
  final IconData icon;
  final _Palette palette;
  final VoidCallback onTap;
  final Color foreground;
  final Color background;
  final Color? borderColor;

  const _ActionButtonMobile({
    required this.label,
    required this.icon,
    required this.palette,
    required this.onTap,
    required this.foreground,
    required this.background,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14.r),
      child: Container(
        height: 46.h,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: borderColor ?? palette.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16.sp, color: foreground),
            SizedBox(width: 8.w),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorCardMobile extends StatelessWidget {
  final _Palette palette;
  final String message;
  final VoidCallback onRetry;

  const _ErrorCardMobile({
    required this.palette,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Container(
            width: 54.w,
            height: 54.w,
            decoration: BoxDecoration(
              color: palette.isDark
                  ? const Color(0xFF2A1B1B)
                  : const Color(0xFFFDEEEE),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(
              PhosphorIcons.warning_circle_fill,
              size: 24.sp,
              color: palette.accentRed,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            'Não foi possível carregar os boletins',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
            ),
          ),
          SizedBox(height: 16.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onRetry,
              icon: Icon(PhosphorIcons.arrow_clockwise, size: 16.sp),
              label: Text(
                'Tentar novamente',
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: palette.accentBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                minimumSize: Size(double.infinity, 48.h),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final _Palette palette;

  const _EmptyState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 42.h),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          Icon(PhosphorIcons.file_text, size: 46.sp, color: palette.muted),
          SizedBox(height: 14.h),
          Text(
            'Nenhum boletim encontrado',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 17.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            'Ajuste os filtros ou gere os boletins da turma para começar.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  final _Palette palette;

  const _LoadingState({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 22.w, vertical: 42.h),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        children: [
          SizedBox(
            width: 54.w,
            height: 54.w,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: palette.accentBlue,
              backgroundColor: palette.border,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            'Carregando boletins...',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            'Aguarde enquanto a turma é consolidada.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
            ),
          ),
        ],
      ),
    );
  }
}
