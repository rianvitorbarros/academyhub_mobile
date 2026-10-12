// lib/screens/dashboard/teacher_dashboard_view.dart

import 'dart:async';
import 'dart:math' as math;

import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/model/model_alunos.dart';
import 'package:academyhub_mobile/model/term_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/services/horario_service.dart';
import 'package:academyhub_mobile/services/student_service.dart';
import 'package:academyhub_mobile/services/term_service.dart';
import 'package:academyhub_mobile/services/performance_trace.dart';
import 'package:academyhub_mobile/util/teacher_class_context_helper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class TeacherDashboardView extends StatefulWidget {
  const TeacherDashboardView({super.key});

  @override
  State<TeacherDashboardView> createState() => _TeacherDashboardViewState();
}

class _TeacherDashboardViewState extends State<TeacherDashboardView>
    with TickerProviderStateMixin {
  final HorarioService _horarioService = HorarioService();
  final StudentService _studentService = StudentService();
  final TermService _termService = TermService();

  late AnimationController _pageController;
  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnim;

  bool _isLoading = true;
  String _loadingMessage = "Preparando seu painel...";
  String? _loadError;

  TermModel? _currentTerm;
  List<HorarioModel> _allTeacherClasses = [];
  List<HorarioModel> _displayClasses = [];
  List<Student> _birthdayStudents = [];
  String _timelineTitle = "Sua Agenda Hoje";

  HorarioModel? _currentClass;
  HorarioModel? _nextClass;
  bool _isClassLive = false;

  int _classesTodayCount = 0;
  int _completedTodayCount = 0;

  static const Color _academyBlue = Color(0xFF1769FF);
  static const Color _academyBlueDark = Color(0xFF0C3C91);
  static const Color _academyGreen = Color(0xFF22C55E);
  static const Color _academyBlack = Color(0xFF0F172A);
  static const Color _softBlue = Color(0xFFEAF2FF);
  static const Color _softGreen = Color(0xFFEAFBF1);
  static const Color _softAmber = Color(0xFFFFF3E6);

  @override
  void initState() {
    super.initState();

    _pageController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pageController, curve: Curves.easeOutCubic),
    );

    _slideAnim =
        Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(
      CurvedAnimation(parent: _pageController, curve: Curves.easeOutCubic),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchDashboardData();
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _fetchDashboardData() async {
    PerformanceTrace.mark('dashboard.teacher.prepare.begin');
    final auth = Provider.of<AuthProvider>(context, listen: false);

    final token = auth.token;
    final user = auth.user;

    if (token == null || user == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadingMessage = "Não foi possível identificar o usuário.";
          _loadError = _loadingMessage;
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _loadError = null;
          _loadingMessage = "Preparando seu painel...";
        });
      }
      bool isGestor = false;
      try {
        final roles = (user.roles as List<dynamic>)
            .map((e) => e.toString().toLowerCase())
            .toList();
        isGestor = roles.contains('admin') ||
            roles.contains('diretor') ||
            roles.contains('coordenador') ||
            roles.contains('administrador');
      } catch (_) {}

      final academicCalendar =
          Provider.of<AcademicCalendarProvider>(context, listen: false);
      final selectedSchoolYearId = academicCalendar.selectedSchoolYear?.id;
      final termFilter = selectedSchoolYearId != null
          ? {'schoolYearId': selectedSchoolYearId}
          : <String, String>{};

      final cachedTerms = academicCalendar.terms;
      final termsMatchSelectedYear = selectedSchoolYearId == null ||
          cachedTerms
              .every((term) => term.schoolYearId == selectedSchoolYearId);

      final terms = cachedTerms.isNotEmpty && termsMatchSelectedYear
          ? cachedTerms
          : await PerformanceTrace.measure('dashboard.teacher.terms_api',
              () => _termService.find(token, termFilter));
      final term = TeacherClassContextHelper.getCurrentTerm(terms);
      final referenceTerm = TeacherClassContextHelper.getReferenceTerm(
        terms,
        currentTerm: term,
      );

      _currentTerm = term;
      TeacherClassContextHelper.logContext(
        screen: 'dashboard',
        teacherId: user.id,
        schoolId: user.schoolId,
        currentTerm: term,
        referenceTerm: referenceTerm,
      );

      final horarioFilter = <String, String>{};
      if (!isGestor) {
        horarioFilter['teacherId'] = user.id;
      }
      if (term != null) {
        horarioFilter['termId'] = term.id;
        horarioFilter['resolveInherited'] = 'true';
        final teacherHorarios = await PerformanceTrace.measure(
          'dashboard.teacher.schedule_api',
          () => _horarioService.getHorarios(
            token,
            filter: horarioFilter,
            debugScreen: 'dashboard',
          ),
        );
        _allTeacherClasses = TeacherClassContextHelper.logFilteredHorarios(
          screen: 'dashboard',
          before: teacherHorarios,
          after: TeacherClassContextHelper.effectiveHorarios(
            teacherHorarios,
            term,
            user: user,
          ),
          currentTerm: term,
        );
      } else {
        final teacherHorarios = await PerformanceTrace.measure(
          'dashboard.teacher.assignments_api',
          () => _horarioService.getHorarios(
            token,
            filter: horarioFilter,
            debugScreen: 'dashboard_assignments',
          ),
        );
        _allTeacherClasses = TeacherClassContextHelper.assignedHorarios(
          teacherHorarios,
          terms,
          user: user,
        );
        _loadingMessage = "Fora do período letivo.";
      }

      _processScheduleLogic();
      TeacherClassContextHelper.logScreenResult(
        screen: 'Dashboard',
        isLoading: false,
        totalVisibleClasses:
            _displayClasses.map((horario) => horario.classId).toSet().length,
        totalVisibleSchedules: _displayClasses.length,
        emptyStateShown: _displayClasses.isEmpty,
      );

      if (mounted) {
        setState(() => _isLoading = false);
        _pageController.forward();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) PerformanceTrace.mark('dashboard.teacher.first_frame');
        });
      }

      unawaited(_loadBirthdays(token));
    } catch (e) {
      debugPrint('[TeacherMobile][DashboardError] ${e.runtimeType}');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = "Não foi possível carregar sua agenda. Tente novamente.";
        });
      }
    }
  }

  Future<void> _loadBirthdays(String token) async {
    try {
      final birthdays = await _studentService.getUpcomingBirthdays(token);
      if (!mounted) return;
      _processBirthdays(birthdays);
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint("Erro ao carregar aniversariantes do professor: $e");
    }
  }

  void _processBirthdays(List<Student> allStudents) {
    final currentMonth = DateTime.now().month;

    final bdays = allStudents.where((s) {
      return s.birthDate.month == currentMonth;
    }).toList();

    bdays.sort((a, b) => a.birthDate.day.compareTo(b.birthDate.day));
    _birthdayStudents = bdays;
  }

  void _processScheduleLogic() {
    if (_currentTerm == null) {
      _classesTodayCount = 0;
      _completedTodayCount = 0;
      _displayClasses = [];
      _currentClass = null;
      _nextClass = null;
      _isClassLive = false;
      _timelineTitle = "Sem aulas agendadas";
      return;
    }

    final now = DateTime.now();
    final todayWeekday = now.weekday;

    final todays = _allTeacherClasses
        .where((h) => h.dayOfWeek == todayWeekday)
        .toList()
      ..sort((a, b) =>
          _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime)));

    _classesTodayCount = todays.length;
    _completedTodayCount = _calculateCompletedClasses(todays);

    if (todays.isNotEmpty) {
      _displayClasses = todays;
      _timelineTitle = "Sua Agenda Hoje";
      _determineCurrentStatus(todays);
    } else {
      _findNextDayWithClasses(todayWeekday);
    }
  }

  int _calculateCompletedClasses(List<HorarioModel> todaysClasses) {
    final nowMin = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    return todaysClasses
        .where((aula) => nowMin >= _timeToMinutes(aula.endTime))
        .length;
  }

  void _findNextDayWithClasses(int startDay) {
    for (int i = 1; i <= 7; i++) {
      final nextDay = (startDay + i) > 7 ? (startDay + i) - 7 : (startDay + i);

      final nextClasses = _allTeacherClasses
          .where((h) => h.dayOfWeek == nextDay)
          .toList()
        ..sort((a, b) =>
            _timeToMinutes(a.startTime).compareTo(_timeToMinutes(b.startTime)));

      if (nextClasses.isNotEmpty) {
        _displayClasses = nextClasses;
        _timelineTitle = "Próximas Aulas • ${_getWeekdayName(nextDay)}";
        _currentClass = null;
        _nextClass = nextClasses.first;
        _isClassLive = false;
        return;
      }
    }

    _displayClasses = [];
    _timelineTitle = "Sem aulas agendadas";
  }

  void _determineCurrentStatus(List<HorarioModel> todaysClasses) {
    final nowTime = TimeOfDay.now();
    final nowMinutes = nowTime.hour * 60 + nowTime.minute;

    HorarioModel? live;
    HorarioModel? next;

    for (final aula in todaysClasses) {
      final startMin = _timeToMinutes(aula.startTime);
      final endMin = _timeToMinutes(aula.endTime);

      if (nowMinutes >= startMin && nowMinutes < endMin) {
        live = aula;
      } else if (nowMinutes < startMin) {
        next ??= aula;
      }
    }

    _currentClass = live;
    _nextClass = next;
    _isClassLive = live != null;
  }

  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  String _getWeekdayName(int day) {
    const days = {
      1: 'Segunda',
      2: 'Terça',
      3: 'Quarta',
      4: 'Quinta',
      5: 'Sexta',
      6: 'Sábado',
      7: 'Domingo',
    };
    return days[day] ?? '';
  }

  String _getFirstName(String fullName) {
    if (fullName.trim().isEmpty) return "Professor";
    return fullName.trim().split(' ').first;
  }

  String _capitalizeFirstLetter(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1);
  }

  String _getInitials(String fullName) {
    final parts =
        fullName.trim().split(' ').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return "?";
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  int _minutesUntil(String startTime) {
    final now = TimeOfDay.now();
    final nowMin = now.hour * 60 + now.minute;
    final startMin = _timeToMinutes(startTime);
    return math.max(0, startMin - nowMin);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final auth = Provider.of<AuthProvider>(context);

    final textPrimary = isDark ? Colors.white : _academyBlack;
    final textSecondary = isDark ? Colors.white70 : Colors.blueGrey[500]!;
    final surface = isDark ? const Color(0xFF111827) : Colors.white;
    final background =
        isDark ? const Color(0xFF060B16) : const Color(0xFFF6F8FC);

    final now = DateTime.now();
    final formattedDate = _capitalizeFirstLetter(
      DateFormat("EEEE, d 'de' MMMM", 'pt_BR').format(now),
    );
    final firstName = _getFirstName(auth.user?.fullName ?? "");

    return Scaffold(
      backgroundColor: background,
      body: _isLoading
          ? _buildLoadingState(textSecondary)
          : _loadError != null
              ? _buildDashboardError(
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                )
              : FadeTransition(
                  opacity: _fadeAnim,
                  child: SlideTransition(
                    position: _slideAnim,
                    child: CustomScrollView(
                      physics: const BouncingScrollPhysics(),
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(18.w, 24.h, 18.w, 120.h),
                          sliver: SliverList(
                            delegate: SliverChildListDelegate(
                              [
                                _buildTopHeader(
                                  auth: auth,
                                  firstName: firstName,
                                  formattedDate: formattedDate,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  isDark: isDark,
                                ),
                                SizedBox(height: 18.h),
                                _buildMainStatusCard(
                                    surface: surface, isDark: isDark),
                                SizedBox(height: 18.h),
                                _buildQuickStatsRow(
                                  surface: surface,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  isDark: isDark,
                                ),
                                SizedBox(height: 22.h),
                                _buildSectionHeader(
                                  title: _timelineTitle,
                                  subtitle: _displayClasses.isEmpty
                                      ? "Organização do seu dia letivo"
                                      : "${_displayClasses.length} itens na sua visualização",
                                  icon: PhosphorIcons.calendar_blank,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                ),
                                SizedBox(height: 14.h),
                                _displayClasses.isEmpty
                                    ? _buildEmptyAgendaCard(
                                        surface: surface,
                                        textPrimary: textPrimary,
                                        textSecondary: textSecondary,
                                        isDark: isDark,
                                      )
                                    : SizedBox(
                                        height: 220.h,
                                        child: ListView.separated(
                                          physics:
                                              const BouncingScrollPhysics(),
                                          scrollDirection: Axis.horizontal,
                                          itemCount: _displayClasses.length,
                                          separatorBuilder: (_, __) =>
                                              SizedBox(width: 12.w),
                                          itemBuilder: (context, index) {
                                            final aula = _displayClasses[index];
                                            return TweenAnimationBuilder<
                                                double>(
                                              tween: Tween(begin: 0.96, end: 1),
                                              duration: Duration(
                                                milliseconds:
                                                    300 + (index * 80),
                                              ),
                                              curve: Curves.easeOut,
                                              builder: (context, value, child) {
                                                return Transform.scale(
                                                  scale: value,
                                                  child: child,
                                                );
                                              },
                                              child: _buildTimelineCard(
                                                aula,
                                                surface,
                                                isDark,
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                                SizedBox(height: 22.h),
                                _buildFocusInsightCard(
                                  surface: surface,
                                  textPrimary: textPrimary,
                                  textSecondary: textSecondary,
                                  isDark: isDark,
                                ),
                                SizedBox(height: 22.h),
                                if (_birthdayStudents.isNotEmpty) ...[
                                  _buildSectionHeader(
                                    title: "Aniversariantes do Mês",
                                    subtitle:
                                        "${_birthdayStudents.length} aluno(s) celebrando neste mês",
                                    icon: PhosphorIcons.cake_fill,
                                    textPrimary: textPrimary,
                                    textSecondary: textSecondary,
                                    iconColor: const Color(0xFFF59E0B),
                                  ),
                                  SizedBox(height: 14.h),
                                  SizedBox(
                                    height: 156.h,
                                    child: ListView.separated(
                                      physics: const BouncingScrollPhysics(),
                                      scrollDirection: Axis.horizontal,
                                      itemCount: _birthdayStudents.length,
                                      separatorBuilder: (_, __) =>
                                          SizedBox(width: 12.w),
                                      itemBuilder: (context, index) {
                                        final student =
                                            _birthdayStudents[index];
                                        return TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.94, end: 1),
                                          duration: Duration(
                                            milliseconds: 320 + (index * 70),
                                          ),
                                          curve: Curves.easeOut,
                                          builder: (context, value, child) {
                                            return Transform.scale(
                                              scale: value,
                                              child: child,
                                            );
                                          },
                                          child: _buildBirthdayCard(
                                            student,
                                            surface,
                                            isDark,
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
    );
  }

  Widget _buildLoadingState(Color textSecondary) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 54.w,
            height: 54.w,
            child: CircularProgressIndicator(
              strokeWidth: 3.2,
              valueColor: const AlwaysStoppedAnimation(_academyBlue),
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            _loadingMessage,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardError({
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Semantics(
      liveRegion: true,
      label: _loadError,
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.warning_circle,
                color: const Color(0xFFF59E0B),
                size: 38.sp,
              ),
              SizedBox(height: 14.h),
              Text(
                _loadError!,
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Sua ausência de dados não será tratada como agenda vazia.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  color: textSecondary,
                ),
              ),
              SizedBox(height: 18.h),
              ElevatedButton.icon(
                onPressed: _fetchDashboardData,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader({
    required AuthProvider auth,
    required String firstName,
    required String formattedDate,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    final profileUrl = auth.user?.profilePictureUrl;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                formattedDate,
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: textSecondary,
                ),
              ),
              SizedBox(height: 6.h),
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: "Olá, ",
                      style: GoogleFonts.sairaCondensed(
                        fontSize: 30.sp,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        color: textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: "$firstName!",
                      style: GoogleFonts.sairaCondensed(
                        fontSize: 30.sp,
                        height: 1,
                        fontWeight: FontWeight.w800,
                        color: _academyBlue,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 6.h),
              Text(
                "Seu painel foi reorganizado para priorizar aula, ritmo e contexto do dia.",
                style: GoogleFonts.inter(
                  fontSize: 12.5.sp,
                  height: 1.45,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: 14.w),
        Container(
          width: 58.w,
          height: 58.w,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: isDark
                  ? [const Color(0xFF1E3A8A), const Color(0xFF2563EB)]
                  : [const Color(0xFFDBEAFE), const Color(0xFFBFDBFE)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: _academyBlue.withOpacity(0.18),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: EdgeInsets.all(2.5.sp),
          child: CircleAvatar(
            backgroundColor: Colors.white,
            backgroundImage: (profileUrl != null && profileUrl.isNotEmpty)
                ? NetworkImage(profileUrl)
                : null,
            child: (profileUrl == null || profileUrl.isEmpty)
                ? Text(
                    _getInitials(auth.user?.fullName ?? ""),
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      fontSize: 18.sp,
                      color: _academyBlueDark,
                    ),
                  )
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildMainStatusCard({
    required Color surface,
    required bool isDark,
  }) {
    if (_isClassLive && _currentClass != null) {
      return _buildHeroCard(
        classInfo: _currentClass!,
        statusLabel: "AULA EM ANDAMENTO",
        statusColor: _academyGreen,
        gradientColors: const [
          Color(0xFF0E4FD3),
          Color(0xFF1769FF),
          Color(0xFF22C55E),
        ],
        buttonText: "Registrar frequência",
        icon: PhosphorIcons.broadcast_fill,
        isDark: isDark,
        isLive: true,
      );
    }

    if (_nextClass != null) {
      return _buildHeroCard(
        classInfo: _nextClass!,
        statusLabel: "PRÓXIMA AULA",
        statusColor: const Color(0xFFF59E0B),
        gradientColors: const [
          Color(0xFF0F172A),
          Color(0xFF1769FF),
        ],
        buttonText: "Ver detalhes",
        icon: PhosphorIcons.clock_counter_clockwise_fill,
        isDark: isDark,
        isNext: true,
      );
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.sp),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE7ECF5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.22 : 0.05),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54.w,
            height: 54.w,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isDark ? Colors.white10 : _softBlue,
            ),
            child: const Icon(
              PhosphorIcons.coffee_fill,
              color: _academyBlue,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Tudo certo por enquanto",
                  style: GoogleFonts.sairaCondensed(
                    fontSize: 22.sp,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : _academyBlack,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  "Nenhuma aula em andamento no momento. Aproveite para revisar o próximo compromisso.",
                  style: GoogleFonts.inter(
                    fontSize: 12.5.sp,
                    height: 1.45,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white70 : Colors.blueGrey[500],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required HorarioModel classInfo,
    required String statusLabel,
    required Color statusColor,
    required List<Color> gradientColors,
    required String buttonText,
    required IconData icon,
    required bool isDark,
    bool isNext = false,
    bool isLive = false,
  }) {
    final minutesUntil = _minutesUntil(classInfo.startTime);

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28.r),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withOpacity(0.28),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -30.w,
            top: -24.h,
            child: Container(
              width: 140.w,
              height: 140.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            left: -25.w,
            bottom: -36.h,
            child: Container(
              width: 120.w,
              height: 120.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(20.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnim,
                      builder: (context, child) {
                        return Transform.scale(
                          scale: isLive ? _pulseAnim.value : 1,
                          child: child,
                        );
                      },
                      child: Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: 10.w,
                          vertical: 6.h,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.14),
                          borderRadius: BorderRadius.circular(999.r),
                          border: Border.all(color: Colors.white24),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8.w,
                              height: 8.w,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              statusLabel,
                              style: GoogleFonts.inter(
                                color: Colors.white,
                                fontSize: 11.sp,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      width: 42.w,
                      height: 42.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withOpacity(0.12),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: 20.sp,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: 18.h),
                Text(
                  classInfo.subject.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.sairaCondensed(
                    color: Colors.white,
                    fontSize: 28.sp,
                    height: 1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  classInfo.classInfo.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    color: Colors.white.withOpacity(0.92),
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 14.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    _buildHeroInfoChip(
                      icon: PhosphorIcons.clock_fill,
                      label: "${classInfo.startTime} - ${classInfo.endTime}",
                    ),
                    _buildHeroInfoChip(
                      icon: PhosphorIcons.map_pin_fill,
                      label: classInfo.room?.trim().isNotEmpty == true
                          ? classInfo.room!
                          : "Sala não definida",
                    ),
                    if (isNext)
                      _buildHeroInfoChip(
                        icon: PhosphorIcons.timer_fill,
                        label: minutesUntil > 0
                            ? "Em $minutesUntil min"
                            : "Começando em breve",
                      ),
                  ],
                ),
                SizedBox(height: 18.h),
                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: gradientColors.first,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16.r),
                      ),
                    ),
                    child: Text(
                      buttonText,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w800,
                        fontSize: 13.sp,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroInfoChip({
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 13.sp),
          SizedBox(width: 6.w),
          Text(
            label,
            style: GoogleFonts.inter(
              color: Colors.white,
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatsRow({
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    final nextRoom =
        _nextClass?.room?.trim().isNotEmpty == true ? _nextClass!.room! : "—";

    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            icon: PhosphorIcons.chalkboard_teacher_fill,
            value: _classesTodayCount.toString(),
            label: "Aulas hoje",
            accent: _academyBlue,
            softColor: isDark ? Colors.white10 : _softBlue,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _buildStatCard(
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            icon: PhosphorIcons.check_circle_fill,
            value: _completedTodayCount.toString(),
            label: "Concluídas",
            accent: _academyGreen,
            softColor: isDark ? Colors.white10 : _softGreen,
          ),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: _buildStatCard(
            surface: surface,
            textPrimary: textPrimary,
            textSecondary: textSecondary,
            icon: PhosphorIcons.door_fill,
            value: nextRoom,
            label: "Próxima sala",
            accent: const Color(0xFFF59E0B),
            softColor: isDark ? Colors.white10 : _softAmber,
            isValueCompact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard({
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required IconData icon,
    required String value,
    required String label,
    required Color accent,
    required Color softColor,
    bool isValueCompact = false,
  }) {
    return Container(
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: const Color(0xFFE9EEF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: softColor,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Icon(icon, color: accent, size: 18.sp),
          ),
          SizedBox(height: 12.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sairaCondensed(
              fontSize: isValueCompact ? 20.sp : 24.sp,
              fontWeight: FontWeight.w800,
              color: textPrimary,
              height: 1,
            ),
          ),
          SizedBox(height: 3.h),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
              color: textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color textPrimary,
    required Color textSecondary,
    Color iconColor = _academyBlue,
  }) {
    return Row(
      children: [
        Container(
          width: 42.w,
          height: 42.w,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14.r),
          ),
          child: Icon(icon, color: iconColor, size: 20.sp),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 17.sp,
                  fontWeight: FontWeight.w800,
                  color: textPrimary,
                ),
              ),
              SizedBox(height: 2.h),
              Text(
                subtitle,
                style: GoogleFonts.inter(
                  fontSize: 11.5.sp,
                  fontWeight: FontWeight.w500,
                  color: textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyAgendaCard({
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.sp),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE7ECF5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48.w,
            height: 48.w,
            decoration: BoxDecoration(
              color: isDark ? Colors.white10 : _softBlue,
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: const Icon(
              PhosphorIcons.calendar_x_fill,
              color: _academyBlue,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Text(
              "Nenhuma aula encontrada nos próximos dias. Seu cronograma está livre no momento.",
              style: GoogleFonts.inter(
                fontSize: 12.5.sp,
                height: 1.45,
                fontWeight: FontWeight.w500,
                color: textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard(HorarioModel aula, Color surface, bool isDark) {
    final nowMin = TimeOfDay.now().hour * 60 + TimeOfDay.now().minute;
    final startMin = _timeToMinutes(aula.startTime);
    final endMin = _timeToMinutes(aula.endTime);

    bool isLive = false;
    bool isDone = false;

    if (_timelineTitle.contains("Hoje")) {
      if (nowMin >= startMin && nowMin < endMin) isLive = true;
      if (nowMin >= endMin) isDone = true;
    }

    final Color accentColor = isLive
        ? _academyBlue
        : (isDone ? Colors.blueGrey : const Color(0xFFF59E0B));

    final Color softAccent =
        isLive ? _softBlue : (isDone ? const Color(0xFFF1F5F9) : _softAmber);

    return Container(
      width: 212.w,
      padding: EdgeInsets.all(14.sp),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(
          color:
              isLive ? _academyBlue.withOpacity(0.35) : const Color(0xFFE6ECF5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: softAccent,
                  borderRadius: BorderRadius.circular(999.r),
                ),
                child: Text(
                  "${aula.startTime} • ${aula.endTime}",
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w800,
                    color: accentColor,
                  ),
                ),
              ),
              const Spacer(),
              if (isLive)
                Container(
                  width: 10.w,
                  height: 10.w,
                  decoration: const BoxDecoration(
                    color: _academyGreen,
                    shape: BoxShape.circle,
                  ),
                ),
              if (isDone)
                Icon(
                  PhosphorIcons.check_circle_fill,
                  size: 18.sp,
                  color: _academyGreen,
                ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            aula.subject.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.sairaCondensed(
              fontSize: 21.sp,
              height: 1,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : _academyBlack,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            aula.classInfo.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white70 : Colors.blueGrey[600],
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Container(
                width: 34.w,
                height: 34.w,
                decoration: BoxDecoration(
                  color: softAccent,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Icon(
                  PhosphorIcons.map_pin_fill,
                  size: 16.sp,
                  color: accentColor,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Text(
                  aula.room?.trim().isNotEmpty == true
                      ? aula.room!
                      : "Sala não definida",
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _academyBlack,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFocusInsightCard({
    required Color surface,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    String title;
    String description;
    IconData icon;
    Color accent;

    if (_isClassLive && _currentClass != null) {
      title = "Momento de execução";
      description =
          "Sua atenção principal agora está em ${_currentClass!.subject.name}. O painel foi pensado para destacar a aula ativa e reduzir ruído.";
      icon = PhosphorIcons.lightning_fill;
      accent = _academyGreen;
    } else if (_nextClass != null) {
      title = "Prepare a próxima entrada";
      description =
          "Sua próxima aula é ${_nextClass!.subject.name}. Verifique sala, turma e ritmo do restante do turno.";
      icon = PhosphorIcons.sparkle_fill;
      accent = _academyBlue;
    } else {
      title = "Janela livre no cronograma";
      description =
          "Sem compromissos letivos imediatos. Este é um bom momento para revisar frequência, conteúdo ou registros.";
      icon = PhosphorIcons.compass_fill;
      accent = const Color(0xFFF59E0B);
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.sp),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFE7ECF5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.12),
              borderRadius: BorderRadius.circular(14.r),
            ),
            child: Icon(icon, color: accent, size: 21.sp),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: textPrimary,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: 12.5.sp,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                    color: textSecondary,
                  ),
                ),
                if (_currentTerm != null) ...[
                  SizedBox(height: 10.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 10.w, vertical: 7.h),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white10 : _softBlue,
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                    child: Text(
                      "Período letivo ativo",
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w800,
                        color: _academyBlue,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBirthdayCard(Student student, Color surface, bool isDark) {
    final currentYear = DateTime.now().year;
    final birthYear = student.birthDate.year;
    final ageTurning = currentYear - birthYear;
    final formattedBday = DateFormat("dd/MM").format(student.birthDate);

    return Container(
      width: 248.w,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24.r),
        gradient: LinearGradient(
          colors: isDark
              ? [
                  const Color(0xFF1E293B),
                  const Color(0xFF0F172A),
                ]
              : [
                  Colors.white,
                  const Color(0xFFFFFBF4),
                ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: const Color(0xFFF4D9A8).withOpacity(0.7),
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFF59E0B).withOpacity(0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -18.w,
            top: -14.h,
            child: Container(
              width: 86.w,
              height: 86.w,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFFDE7B0).withOpacity(0.35),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.all(16.sp),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50.w,
                      height: 50.w,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFFFD36E),
                            Color(0xFFF59E0B),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFF59E0B).withOpacity(0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          _getInitials(student.fullName),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800,
                            fontSize: 15.sp,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 10.w,
                              vertical: 5.h,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF3D8),
                              borderRadius: BorderRadius.circular(999.r),
                            ),
                            child: Text(
                              "Aniversário • $formattedBday",
                              style: GoogleFonts.inter(
                                fontSize: 10.5.sp,
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFFB87400),
                              ),
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Text(
                            student.fullName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.inter(
                              fontSize: 14.sp,
                              height: 1.2,
                              fontWeight: FontWeight.w800,
                              color: isDark ? Colors.white : _academyBlack,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: double.infinity,
                  padding:
                      EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withOpacity(0.06)
                        : const Color(0xFFFFFAEF),
                    borderRadius: BorderRadius.circular(16.r),
                    border: Border.all(
                      color: const Color(0xFFF7DDA2).withOpacity(0.8),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        PhosphorIcons.confetti_fill,
                        color: const Color(0xFFF59E0B),
                        size: 18.sp,
                      ),
                      SizedBox(width: 10.w),
                      Expanded(
                        child: Text(
                          "Completa $ageTurning anos neste mês",
                          style: GoogleFonts.inter(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : _academyBlack,
                          ),
                        ),
                      ),
                    ],
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
