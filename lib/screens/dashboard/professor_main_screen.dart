import 'dart:convert';

import 'package:academyhub_mobile/attendance/attendance_swipe_screen.dart';
import 'package:academyhub_mobile/attendance/class_selection_screen.dart';
import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/horario_provider.dart';
import 'package:academyhub_mobile/screens/settings/shared_settings_view.dart';
import 'package:academyhub_mobile/screens/teacher/teacher_exams_mobile_screen.dart';
import 'package:academyhub_mobile/screens/teacher/teacher_activity_class_selection_screen.dart';
import 'package:academyhub_mobile/screens/teacher/screen_report_cards.dart';
import 'package:academyhub_mobile/screens/teacher/screen_teacher_dashboard.dart';
import 'package:academyhub_mobile/screens/teacher/teacher_class_activities_screen.dart';
import 'package:academyhub_mobile/util/teacher_class_context_helper.dart';
import 'package:academyhub_mobile/widgets/custom_bottom_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

// [IMPORTANTE] Imports dos Providers e Telas Novas
import 'package:academyhub_mobile/providers/class_provider.dart';
// import 'package:academyhub_mobile/providers/enrollment_provider.dart'; // <-- Certifique-se que o caminho está correto
import 'package:academyhub_mobile/screens/teacher/student_management_screens.dart'; // O novo arquivo de gestão de alunos

class ProfessorMainScreen extends StatefulWidget {
  const ProfessorMainScreen({super.key});

  @override
  State<ProfessorMainScreen> createState() => _ProfessorMainScreenState();
}

class _ProfessorMainScreenState extends State<ProfessorMainScreen> {
  static const int _homeIndex = 0;
  static const int _studentsIndex =
      1; // 1. Módulo Principal de Alunos (Tela de Pastas)
  static const int _classesIndex = 2;
  static const int _settingsIndex = 3;

  static const int _myDataIndex = 4;
  static const int _attendanceClassSelectionIndex = 5;
  static const int _attendanceSwipeIndex = 6;
  static const int _reportCardsIndex = 7;

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  int _currentIndex = _homeIndex;

  String? _selectedClassId;
  String? _selectedClassName;

  @override
  void initState() {
    super.initState();

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _primeTeacherEffectiveContext();
    });
  }

  Future<void> _primeTeacherEffectiveContext() async {
    final authProvider = context.read<AuthProvider>();
    final classProvider = context.read<ClassProvider>();
    final horarioProvider = context.read<HorarioProvider>();
    final academicProvider = context.read<AcademicCalendarProvider>();

    await TeacherClassContextHelper.ensureDataLoaded(
      authProvider: authProvider,
      classProvider: classProvider,
      horarioProvider: horarioProvider,
      academicProvider: academicProvider,
      forceRefresh: true,
      sharedAcrossPeriods: true,
      screen: 'professor_bootstrap',
    );
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  void _navigateToMyDataScreen() {
    setState(() => _currentIndex = _myDataIndex);
  }

  void _navigateToAttendance() {
    setState(() => _currentIndex = _attendanceClassSelectionIndex);
  }

  void _navigateToAttendanceSwipe(String classId, String className) {
    setState(() {
      _selectedClassId = classId;
      _selectedClassName = className;
      _currentIndex = _attendanceSwipeIndex;
    });
  }

  void _backToClassSelection() {
    setState(() {
      _selectedClassId = null;
      _selectedClassName = null;
      _currentIndex = _attendanceClassSelectionIndex;
    });
  }

  void _navigateToReportCards() {
    setState(() => _currentIndex = _reportCardsIndex);
  }

  void _openActivitiesForClass(
    ClassModel classData, [
    HorarioModel? preferredSchedule,
  ]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TeacherClassActivitiesScreen(
          classData: classData,
          preferredSchedule: preferredSchedule,
        ),
      ),
    );
  }

  void _openAttendanceForClass(ClassModel classData) {
    final classId = classData.id;
    if (classId.isEmpty) return;
    _navigateToAttendanceSwipe(classId, classData.name);
  }

  Future<void> _navigateToActivitiesShortcut() async {
    final authProvider = context.read<AuthProvider>();
    final classProvider = context.read<ClassProvider>();
    final horarioProvider = context.read<HorarioProvider>();
    final academicProvider = context.read<AcademicCalendarProvider>();

    await TeacherClassContextHelper.ensureDataLoaded(
      authProvider: authProvider,
      classProvider: classProvider,
      horarioProvider: horarioProvider,
      academicProvider: academicProvider,
    );

    if (!mounted) return;

    final suggestion = TeacherClassContextHelper.resolveSuggestedClass(
      classes: classProvider.classes,
      horarios: horarioProvider.horarios,
      user: authProvider.user,
      terms: academicProvider.terms,
    );

    if (suggestion != null) {
      _openActivitiesForClass(suggestion.classData, suggestion.schedule);
      return;
    }

    setState(() => _currentIndex = _classesIndex);
  }

  void _navigateToExams() {
    final startedAt = DateTime.now();
    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][NavigateToExamsStart] ${jsonEncode({
            'timestamp': startedAt.toIso8601String(),
            'fromScreen': 'ProfessorMainScreen',
          })}');
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TeacherExamsMobileScreen(
          navigateStartedAt: startedAt,
        ),
      ),
    );
  }

  bool _shouldHideAppBar() {
    return _currentIndex == _myDataIndex ||
        _currentIndex == _attendanceClassSelectionIndex ||
        _currentIndex == _attendanceSwipeIndex ||
        _currentIndex == _reportCardsIndex ||
        _currentIndex ==
            _studentsIndex; // Escondemos aqui pois o módulo de alunos tem Header próprio
  }

  int _bottomMenuSelectedIndex() {
    if (_currentIndex == _homeIndex ||
        _currentIndex == _studentsIndex ||
        _currentIndex == _classesIndex ||
        _currentIndex == _settingsIndex) {
      return _currentIndex;
    }
    return _homeIndex;
  }

  PreferredSizeWidget? _buildAppBar(BuildContext context) {
    if (_shouldHideAppBar()) return null;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      extendBodyBehindAppBar: true,
      resizeToAvoidBottomInset: false,
      appBar: _buildAppBar(context),
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                // 0: Home
                const TeacherDashboardView(),

                // 1: Módulo de Gestão de Alunos (NOVO FLUXO 100% ISOLADO)
                const StudentManagementEntryScreen(),

                // 2: Turmas
                TeacherActivityClassSelectionScreen(
                  onOpenActivities: _openActivitiesForClass,
                  onOpenAttendance: _openAttendanceForClass,
                ),

                // 3: Settings
                const SharedSettingsView(),

                // 4: Meus Dados
                const Center(child: Text("Tela de Meus Dados (Em breve)")),

                // 5: Frequência -> Seleção de Turma Original
                ClassSelectionScreen(
                  onBack: () => _onTabTapped(_homeIndex),
                  onClassSelected: _navigateToAttendanceSwipe,
                ),

                // 6: Frequência -> Tela de Swipe
                _selectedClassId != null
                    ? AttendanceSwipeScreen(
                        classId: _selectedClassId!,
                        className: _selectedClassName ?? "Turma",
                        onBack: _backToClassSelection,
                      )
                    : const Center(child: CircularProgressIndicator()),

                // 7: Boletins
                const ScreenReportCards(),
              ],
            ),
          ),
          Positioned.fill(
            child: CustomSpeedDialMenu(
              isProfessor: true,
              currentIndex: _bottomMenuSelectedIndex(),
              onTabSelected: _onTabTapped,
              onNavigateToAttendance: _navigateToAttendance,
              onNavigateToActivities: () {
                _navigateToActivitiesShortcut();
              },
              onNavigateToStaff: _navigateToMyDataScreen,
              onNavigateToReportCards: _navigateToReportCards,
              onNavigateToScanner: _navigateToExams,
            ),
          ),
        ],
      ),
      bottomNavigationBar: null,
    );
  }
}
