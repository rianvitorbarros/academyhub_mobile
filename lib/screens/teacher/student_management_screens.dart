import 'package:academyhub_mobile/model/student_note_model.dart';
import 'package:academyhub_mobile/providers/enrollment_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Módulos e Providers Reais
import '../../model/enrollment_model.dart';
import '../../model/model_alunos.dart';
import '../../model/class_model.dart';
import '../../providers/class_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/student_note_provider.dart';
import '../../widgets/attendance_operation_dialog.dart';
import 'teacher_student_profile_screen.dart';

// Providers vitais para extrair alunos e filtrar turmas pelo horário
import '../../providers/horario_provider.dart';
import '../../providers/academic_calendar_provider.dart';
import '../../util/teacher_class_context_helper.dart';

// =============================================================================
// PALETA ACADEMY HUB - GESTÃO DE ALUNOS
// =============================================================================

const kBackgroundDark = Color(0xFF07090D);
const kSurfaceDark = Color(0xFF11151C);
const kSurfaceDarkAlt = Color(0xFF171C24);
const kBorderDark = Color(0xFF242B36);

const kPrimaryBlue = Color(0xFF2F80FF);
const kSuccessColor = Color(0xFF00C853);
const kErrorColor = Color(0xFFFF5A5F);
const kAccentOrange = Color(0xFFFFA726);
const kWarningYellow = Color(0xFFFFD166);

const kTextPrimaryDark = Color(0xFFF3F5F7);
const kTextSecondaryDark = Color(0xFF9AA4B2);

Color _pageBg(bool isDark) =>
    isDark ? kBackgroundDark : const Color(0xFFF4F6F8);
Color _surface(bool isDark) => isDark ? kSurfaceDark : Colors.white;
Color _surfaceAlt(bool isDark) =>
    isDark ? kSurfaceDarkAlt : const Color(0xFFF8FAFC);
Color _border(bool isDark) => isDark ? kBorderDark : const Color(0xFFE6EAF0);
Color _textPrimary(bool isDark) =>
    isDark ? kTextPrimaryDark : const Color(0xFF0F172A);
Color _textSecondary(bool isDark) =>
    isDark ? kTextSecondaryDark : const Color(0xFF64748B);

// =============================================================================
// 1. TELA DE ENTRADA: SELEÇÃO DE TURMAS (DESIGN DE PASTAS/GESTÃO)
// =============================================================================

class StudentManagementEntryScreen extends StatelessWidget {
  const StudentManagementEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _pageBg(isDark),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 10.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Gestão de Alunos",
                    style: GoogleFonts.bebasNeue(
                      fontSize: 32.sp,
                      color: _textPrimary(isDark),
                      letterSpacing: 0.5,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    "Selecione uma turma para visualizar perfis, ocorrências e dados acadêmicos dos alunos.",
                    style: GoogleFonts.inter(
                      fontSize: 13.sp,
                      height: 1.4,
                      color: _textSecondary(isDark),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: 10.h),
            Expanded(
              child: Consumer4<ClassProvider, HorarioProvider, AuthProvider,
                  AcademicCalendarProvider>(
                builder: (
                  context,
                  classProv,
                  horarioProv,
                  authProv,
                  academicProv,
                  child,
                ) {
                  if (classProv.isLoading || horarioProv.isLoading) {
                    return const Center(
                        child: CircularProgressIndicator(color: kPrimaryBlue));
                  }

                  final currentUser = authProv.user;
                  if (currentUser == null) return const SizedBox();

                  final classes = TeacherClassContextHelper.getAvailableClasses(
                    classes: classProv.classes,
                    horarios: horarioProv.horarios,
                    user: currentUser,
                    terms: academicProv.terms,
                    sharedAcrossPeriods: true,
                  );
                  final currentTerm = TeacherClassContextHelper.getCurrentTerm(
                    academicProv.terms,
                  );
                  final effectiveHorarios =
                      TeacherClassContextHelper.assignedHorarios(
                    horarioProv.horarios,
                    academicProv.terms,
                    user: currentUser,
                    sharedAcrossPeriods: true,
                  );
                  TeacherClassContextHelper.logClasses(
                    screen: 'students',
                    currentTerm: currentTerm,
                    classes: classes,
                    horarios: effectiveHorarios,
                  );
                  TeacherClassContextHelper.logScreenResult(
                    screen: 'StudentsTab',
                    isLoading: false,
                    totalVisibleClasses: classes.length,
                    totalVisibleSchedules: effectiveHorarios.length,
                    emptyStateShown: classes.isEmpty,
                  );

                  final hasDataError = classes.isEmpty &&
                      (classProv.error != null || horarioProv.error != null);
                  if (hasDataError) {
                    return _TeacherStudentsLoadError(
                      isDark: isDark,
                      onRetry: () async {
                        await TeacherClassContextHelper.ensureDataLoaded(
                          authProvider: authProv,
                          classProvider: classProv,
                          horarioProvider: horarioProv,
                          academicProvider: academicProv,
                          forceRefresh: true,
                          sharedAcrossPeriods: true,
                          screen: 'students_retry',
                        );
                      },
                    );
                  }

                  if (classes.isEmpty) {
                    return Center(
                      child: Text(
                        "Você não possui alunos atribuídos no momento.",
                        style: GoogleFonts.inter(color: _textSecondary(isDark)),
                      ),
                    );
                  }

                  return GridView.builder(
                    padding: EdgeInsets.fromLTRB(24.w, 10.h, 24.w, 100.h),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount:
                          MediaQuery.of(context).size.width > 600 ? 3 : 2,
                      crossAxisSpacing: 16.w,
                      mainAxisSpacing: 16.h,
                      childAspectRatio: 0.85,
                    ),
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final c = classes[index];
                      return _ClassFolderCard(
                        classData: c,
                        isDark: isDark,
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  StudentManagementListScreen(classData: c),
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TeacherStudentsLoadError extends StatelessWidget {
  final bool isDark;
  final Future<void> Function() onRetry;

  const _TeacherStudentsLoadError({
    required this.isDark,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Erro ao carregar alunos. Tente novamente.',
      child: Center(
        child: Padding(
          padding: EdgeInsets.all(24.w),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIcons.warning_circle,
                color: kAccentOrange,
                size: 36,
              ),
              SizedBox(height: 14.h),
              Text(
                'Não foi possível carregar suas turmas',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w700,
                  color: _textPrimary(isDark),
                ),
              ),
              SizedBox(height: 8.h),
              Text(
                'Tente novamente para acessar os alunos atribuídos.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 13.sp,
                  color: _textSecondary(isDark),
                ),
              ),
              SizedBox(height: 18.h),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClassFolderCard extends StatelessWidget {
  final ClassModel classData;
  final bool isDark;
  final VoidCallback onTap;

  const _ClassFolderCard({
    required this.classData,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        decoration: BoxDecoration(
          color: _surface(isDark),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(color: _border(isDark)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(isDark ? 0.3 : 0.04),
              blurRadius: 15,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Stack(
          children: [
            Positioned(
              top: -15.h,
              right: -15.w,
              child: Icon(
                PhosphorIcons.folder,
                size: 100.sp,
                color: kPrimaryBlue.withOpacity(0.05),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(18.w),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: kPrimaryBlue.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(PhosphorIcons.users,
                        color: kPrimaryBlue, size: 24.sp),
                  ),
                  const Spacer(),
                  Text(
                    classData.name,
                    style: GoogleFonts.inter(
                      fontSize: 16.sp,
                      fontWeight: FontWeight.bold,
                      color: _textPrimary(isDark),
                      height: 1.2,
                    ),
                  ),
                  SizedBox(height: 6.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 8.w, vertical: 4.h),
                    decoration: BoxDecoration(
                      color: _surfaceAlt(isDark),
                      borderRadius: BorderRadius.circular(8.r),
                    ),
                    child: Text(
                      "${classData.studentCount} Alunos",
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: _textSecondary(isDark),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 2. TELA DE LISTA DE ALUNOS (AGORA FAZ A REQUISIÇÃO PARA A API)
// =============================================================================

class StudentManagementListScreen extends StatefulWidget {
  final ClassModel classData;

  const StudentManagementListScreen({super.key, required this.classData});

  @override
  State<StudentManagementListScreen> createState() =>
      _StudentManagementListScreenState();
}

class _StudentManagementListScreenState
    extends State<StudentManagementListScreen> {
  final TextEditingController _searchController = TextEditingController();

  // Listas locais para evitar que a tela pisque enquanto filtra
  List<Enrollment> _allEnrollments = [];
  List<Enrollment> _filteredEnrollments = [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _filterStudents();
    });

    // MÁGICA DE VERDADE AQUI: Chama a API logo que a tela abre!
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadStudentsFromApi();
    });
  }

  Future<void> _loadStudentsFromApi() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final enrollmentProv =
        Provider.of<EnrollmentProvider>(context, listen: false);

    // 1. Pede ao EnrollmentProvider para buscar as matrículas desta turma na API
    await enrollmentProv.fetchEnrollmentsByClass(
        authProv.token!, widget.classData.id);

    if (!mounted) return;
    if (enrollmentProv.error != null) {
      setState(() {
        _allEnrollments = [];
        _filteredEnrollments = [];
        _isLoading = false;
        _loadError = 'Não foi possível carregar os alunos desta turma.';
      });
      return;
    }

    // 2. Transforma as matrículas ativas em uma lista de alunos
    final activeEnrollments = enrollmentProv.enrollments.toList();

    // 3. Coloca em ordem alfabética
    activeEnrollments.sort(
      (a, b) => a.student.fullName.compareTo(b.student.fullName),
    );

    setState(() {
      _allEnrollments = activeEnrollments;
      _filteredEnrollments = activeEnrollments; // Inicialmente, todos aparecem
      _isLoading = false; // Tira a bolinha de carregamento
    });
  }

  void _filterStudents() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredEnrollments = _allEnrollments.where((enrollment) {
        final fullName = enrollment.student.fullName.toLowerCase();
        final enrollmentNumber =
            (enrollment.student.enrollmentNumber ?? '').toLowerCase();
        return fullName.contains(query) || enrollmentNumber.contains(query);
      }).toList();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: _pageBg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: _textPrimary(isDark)),
        title: Column(
          children: [
            Text("Alunos Matriculados",
                style: GoogleFonts.inter(
                    color: _textPrimary(isDark),
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp)),
            Text(widget.classData.name,
                style: GoogleFonts.inter(
                    color: kPrimaryBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.sp)),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(20.w, 10.h, 20.w, 20.h),
            child: TextField(
              controller: _searchController,
              style: GoogleFonts.inter(color: _textPrimary(isDark)),
              decoration: InputDecoration(
                hintText: 'Pesquisar aluno...',
                hintStyle: TextStyle(color: _textSecondary(isDark)),
                prefixIcon: Icon(PhosphorIcons.magnifying_glass,
                    color: _textSecondary(isDark)),
                filled: true,
                fillColor: _surfaceAlt(isDark),
                contentPadding: EdgeInsets.symmetric(vertical: 14.h),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: _border(isDark)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(color: _border(isDark)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: kPrimaryBlue),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                        color:
                            kPrimaryBlue)) // Bolinha de Loading enquanto a API responde
                : _loadError != null
                    ? Semantics(
                        liveRegion: true,
                        label: _loadError,
                        child: Center(
                          child: Padding(
                            padding: EdgeInsets.all(24.w),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  PhosphorIcons.warning_circle,
                                  color: kAccentOrange,
                                  size: 38,
                                ),
                                SizedBox(height: 12.h),
                                Text(
                                  _loadError!,
                                  textAlign: TextAlign.center,
                                  style: GoogleFonts.inter(
                                    color: _textPrimary(isDark),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 16.h),
                                ElevatedButton.icon(
                                  onPressed: _loadStudentsFromApi,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Tentar novamente'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : _allEnrollments.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(PhosphorIcons.users,
                                    size: 48.sp, color: _textSecondary(isDark)),
                                SizedBox(height: 16.h),
                                Text('Nenhum aluno matriculado nesta turma.',
                                    style: GoogleFonts.inter(
                                        color: _textSecondary(isDark))),
                              ],
                            ),
                          )
                        : _filteredEnrollments.isEmpty
                            ? Center(
                                child: Text(
                                    'Nenhum aluno encontrado na pesquisa.',
                                    style: GoogleFonts.inter(
                                        color: _textSecondary(isDark))),
                              )
                            : ListView.separated(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 20.w, vertical: 10.h),
                                itemCount: _filteredEnrollments.length,
                                separatorBuilder: (_, __) =>
                                    SizedBox(height: 12.h),
                                itemBuilder: (context, index) {
                                  final enrollment =
                                      _filteredEnrollments[index];
                                  return _StudentListItem(
                                    enrollment: enrollment,
                                    classData: widget.classData,
                                    isDark: isDark,
                                  );
                                },
                              ),
          ),
        ],
      ),
    );
  }
}

class _StudentListItem extends StatelessWidget {
  final Enrollment enrollment;
  final ClassModel classData;
  final bool isDark;

  const _StudentListItem({
    required this.enrollment,
    required this.classData,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final student = enrollment.student;
    final enrollmentNumber = (student.enrollmentNumber ?? '').trim().isEmpty
        ? 'Sem matricula'
        : student.enrollmentNumber!.trim();
    final gender = student.gender.trim();
    final hasGender = gender.isNotEmpty &&
        gender.toLowerCase() != 'nao informado' &&
        gender.toLowerCase() != 'não informado';

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TeacherStudentProfileScreen(
              enrollment: enrollment,
              classData: classData,
            ),
          ),
        );
      },
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(14.w),
        decoration: BoxDecoration(
            color: _surface(isDark),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: _border(isDark)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.2 : 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              )
            ]),
        child: Row(
          children: [
            CircleAvatar(
              radius: 26.sp,
              backgroundColor: _surfaceAlt(isDark),
              child: Text(
                student.fullName.isNotEmpty
                    ? student.fullName[0].toUpperCase()
                    : '?',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark),
                    fontSize: 18.sp),
              ),
            ),
            SizedBox(width: 16.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 15.sp,
                      fontWeight: FontWeight.w700,
                      color: _textPrimary(isDark),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Row(
                    children: [
                      Icon(PhosphorIcons.identification_card,
                          size: 14.sp, color: _textSecondary(isDark)),
                      SizedBox(width: 4.w),
                      Text(
                        enrollmentNumber,
                        style: GoogleFonts.sourceCodePro(
                          fontSize: 12.sp,
                          color: _textSecondary(isDark),
                        ),
                      ),
                      if (hasGender) ...[
                        SizedBox(width: 8.w),
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8.w,
                            vertical: 3.h,
                          ),
                          decoration: BoxDecoration(
                            color: _surfaceAlt(isDark),
                            borderRadius: BorderRadius.circular(999.r),
                          ),
                          child: Text(
                            gender,
                            style: GoogleFonts.inter(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w700,
                              color: _textSecondary(isDark),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            Icon(PhosphorIcons.caret_right,
                color: _textSecondary(isDark), size: 20.sp),
          ],
        ),
      ),
    );
  }
}

// =============================================================================
// 3. TELA DE PERFIL DO ALUNO (RAIO-X E ANOTAÇÕES)
// =============================================================================

class StudentProfileScreen extends StatefulWidget {
  final Student student;

  const StudentProfileScreen({super.key, required this.student});

  @override
  State<StudentProfileScreen> createState() => _StudentProfileScreenState();
}

class _StudentProfileScreenState extends State<StudentProfileScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authProv = Provider.of<AuthProvider>(context, listen: false);
      Provider.of<StudentNoteProvider>(context, listen: false)
          .loadNotes(authProv, widget.student.id);
    });
  }

  void _launchContact(String phone, bool isWhatsApp) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(
              'Abrindo ${isWhatsApp ? "WhatsApp" : "Ligação"} para $phone...')),
    );
  }

  String _calculateAge(DateTime birthDate) {
    final today = DateTime.now();
    int age = today.year - birthDate.year;
    if (today.month < birthDate.month ||
        (today.month == birthDate.month && today.day < birthDate.day)) {
      age--;
    }
    return "$age anos";
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final s = widget.student;

    final bool hasHealthAlert = s.healthInfo.hasAllergy ||
        s.healthInfo.hasHealthProblem ||
        s.healthInfo.hasDisability ||
        s.healthInfo.hasMedicationAllergy ||
        s.healthInfo.takesMedication;

    return Scaffold(
      backgroundColor: _pageBg(isDark),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: IconThemeData(color: _textPrimary(isDark)),
        actions: [
          IconButton(
            onPressed: () {},
            icon: Icon(PhosphorIcons.dots_three_vertical,
                color: _textPrimary(isDark)),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: kPrimaryBlue,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => _CreateNoteBottomSheet(
                studentId: s.id, studentName: s.fullName),
          );
        },
        icon: const Icon(PhosphorIcons.pencil_simple, color: Colors.white),
        label: Text("Anotação",
            style: GoogleFonts.inter(
                fontWeight: FontWeight.bold, color: Colors.white)),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 100.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: _surface(isDark),
                borderRadius: BorderRadius.circular(24.r),
                border: Border.all(color: _border(isDark)),
              ),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 46.sp,
                    backgroundColor: _surfaceAlt(isDark),
                    child: Text(
                      s.fullName.isNotEmpty ? s.fullName[0].toUpperCase() : '?',
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w800,
                          color: _textPrimary(isDark),
                          fontSize: 36.sp),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Text(
                    s.fullName,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                        fontSize: 22.sp,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary(isDark)),
                  ),
                  SizedBox(height: 8.h),
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    decoration: BoxDecoration(
                      color: _surfaceAlt(isDark),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      "Matrícula: ${s.enrollmentNumber ?? s.id.substring(s.id.length - 6).toUpperCase()}",
                      style: GoogleFonts.sourceCodePro(
                          fontSize: 13.sp,
                          color: _textSecondary(isDark),
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildMiniTag(PhosphorIcons.calendar_blank,
                          _calculateAge(s.birthDate), isDark),
                      SizedBox(width: 12.w),
                      _buildMiniTag(
                          PhosphorIcons.gender_intersex, s.gender, isDark),
                    ],
                  )
                ],
              ),
            ),
            SizedBox(height: 24.h),
            if (hasHealthAlert)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: 24.h),
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  color: kErrorColor.withOpacity(isDark ? 0.15 : 0.08),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: kErrorColor.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(PhosphorIcons.warning_circle_fill,
                            color: kErrorColor, size: 22.sp),
                        SizedBox(width: 10.w),
                        Text("Atenção Médica / Cuidados",
                            style: GoogleFonts.inter(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: kErrorColor)),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    if (s.healthInfo.hasHealthProblem)
                      _buildHealthLine("Condição:",
                          s.healthInfo.healthProblemDetails, isDark),
                    if (s.healthInfo.hasAllergy)
                      _buildHealthLine(
                          "Alergia:", s.healthInfo.allergyDetails, isDark),
                    if (s.healthInfo.hasMedicationAllergy)
                      _buildHealthLine("Alergia a Remédio:",
                          s.healthInfo.medicationAllergyDetails, isDark),
                    if (s.healthInfo.takesMedication)
                      _buildHealthLine("Medicação Contínua:",
                          s.healthInfo.medicationDetails, isDark),
                    if (s.healthInfo.hasDisability)
                      _buildHealthLine("Necessidade Especial:",
                          s.healthInfo.disabilityDetails, isDark),
                  ],
                ),
              ),
            if (s.authorizedPickups.isNotEmpty || s.tutors.isNotEmpty)
              Container(
                width: double.infinity,
                margin: EdgeInsets.only(bottom: 32.h),
                padding: EdgeInsets.all(20.w),
                decoration: BoxDecoration(
                  color: _surface(isDark),
                  borderRadius: BorderRadius.circular(20.r),
                  border: Border.all(color: _border(isDark)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(PhosphorIcons.phone_call,
                            color: kPrimaryBlue, size: 22.sp),
                        SizedBox(width: 10.w),
                        Text("Contato de Emergência",
                            style: GoogleFonts.inter(
                                fontSize: 15.sp,
                                fontWeight: FontWeight.bold,
                                color: _textPrimary(isDark))),
                      ],
                    ),
                    SizedBox(height: 16.h),
                    Builder(builder: (context) {
                      final contactName = s.authorizedPickups.isNotEmpty
                          ? s.authorizedPickups.first.fullName
                          : "Responsável";
                      final relation = s.authorizedPickups.isNotEmpty
                          ? s.authorizedPickups.first.relationship
                          : "Tutor";
                      final phone = s.authorizedPickups.isNotEmpty
                          ? s.authorizedPickups.first.phoneNumber
                          : s.phoneNumber ?? "";

                      return Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(contactName,
                                    style: GoogleFonts.inter(
                                        fontWeight: FontWeight.bold,
                                        color: _textPrimary(isDark),
                                        fontSize: 16.sp)),
                                SizedBox(height: 4.h),
                                Text("$relation • $phone",
                                    style: GoogleFonts.inter(
                                        color: _textSecondary(isDark),
                                        fontSize: 13.sp)),
                              ],
                            ),
                          ),
                          if (phone.isNotEmpty) ...[
                            IconButton(
                              onPressed: () => _launchContact(phone, true),
                              icon: Icon(PhosphorIcons.whatsapp_logo,
                                  color: Colors.white, size: 22.sp),
                              style: IconButton.styleFrom(
                                  backgroundColor: kSuccessColor,
                                  padding: EdgeInsets.all(12.w)),
                            ),
                            SizedBox(width: 10.w),
                            IconButton(
                              onPressed: () => _launchContact(phone, false),
                              icon: Icon(PhosphorIcons.phone,
                                  color: Colors.white, size: 22.sp),
                              style: IconButton.styleFrom(
                                  backgroundColor: kPrimaryBlue,
                                  padding: EdgeInsets.all(12.w)),
                            ),
                          ]
                        ],
                      );
                    }),
                  ],
                ),
              ),
            Row(
              children: [
                Icon(PhosphorIcons.files,
                    color: _textPrimary(isDark), size: 22.sp),
                SizedBox(width: 10.w),
                Text("Ocorrências e Notas",
                    style: GoogleFonts.inter(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w800,
                        color: _textPrimary(isDark))),
              ],
            ),
            SizedBox(height: 16.h),
            Consumer<StudentNoteProvider>(
              builder: (context, noteProvider, child) {
                if (noteProvider.isLoading) {
                  return const Center(
                      child: CircularProgressIndicator(color: kPrimaryBlue));
                }

                if (noteProvider.notes.isEmpty) {
                  return Container(
                    padding:
                        EdgeInsets.symmetric(vertical: 40.h, horizontal: 20.w),
                    decoration: BoxDecoration(
                      color: _surface(isDark),
                      borderRadius: BorderRadius.circular(20.r),
                      border: Border.all(
                          color: _border(isDark),
                          style: BorderStyle.solid,
                          width: 2),
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(PhosphorIcons.note_blank,
                              size: 48.sp,
                              color: _textSecondary(isDark).withOpacity(0.5)),
                          SizedBox(height: 12.h),
                          Text("O histórico disciplinar está limpo.",
                              style: GoogleFonts.inter(
                                  color: _textSecondary(isDark))),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: noteProvider.notes.length,
                  separatorBuilder: (_, __) => SizedBox(height: 12.h),
                  itemBuilder: (context, index) {
                    final note = noteProvider.notes[index];
                    return _NoteCard(note: note, isDark: isDark);
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniTag(IconData icon, String text, bool isDark) {
    return Row(
      children: [
        Icon(icon, size: 14.sp, color: _textSecondary(isDark)),
        SizedBox(width: 6.w),
        Text(text,
            style: GoogleFonts.inter(
                fontSize: 13.sp,
                color: _textSecondary(isDark),
                fontWeight: FontWeight.w500)),
      ],
    );
  }

  Widget _buildHealthLine(String title, String desc, bool isDark) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: RichText(
        text: TextSpan(
          style:
              GoogleFonts.inter(fontSize: 13.sp, color: _textPrimary(isDark)),
          children: [
            TextSpan(
                text: "• $title ",
                style: const TextStyle(fontWeight: FontWeight.bold)),
            TextSpan(text: desc),
          ],
        ),
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final StudentNoteModel note;
  final bool isDark;

  const _NoteCard({required this.note, required this.isDark});

  @override
  Widget build(BuildContext context) {
    Color tagColor;
    String tagLabel;
    IconData tagIcon;

    switch (note.type) {
      case StudentNoteType.attention:
        tagColor = kWarningYellow;
        tagLabel = "Atenção (Gestão)";
        tagIcon = PhosphorIcons.warning;
        break;
      case StudentNoteType.warning:
        tagColor = kErrorColor;
        tagLabel = "Advertência";
        tagIcon = PhosphorIcons.warning_octagon;
        break;
      case StudentNoteType.private:
      default:
        tagColor = kPrimaryBlue;
        tagLabel = "Nota Privada";
        tagIcon = PhosphorIcons.lock_key;
        break;
    }

    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        color: _surface(isDark),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: _border(isDark)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                    color: tagColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(tagIcon, size: 14.sp, color: tagColor),
                    SizedBox(width: 6.w),
                    Text(tagLabel,
                        style: GoogleFonts.inter(
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            color: tagColor)),
                  ],
                ),
              ),
              Text(
                DateFormat("dd/MM/yyyy HH:mm").format(note.createdAt),
                style: GoogleFonts.inter(
                    fontSize: 12.sp, color: _textSecondary(isDark)),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(note.title,
              style: GoogleFonts.inter(
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                  color: _textPrimary(isDark))),
          SizedBox(height: 8.h),
          Text(note.description,
              style: GoogleFonts.inter(
                  fontSize: 14.sp, color: _textSecondary(isDark), height: 1.4)),
          Divider(height: 32.h, color: _border(isDark)),
          Row(
            children: [
              CircleAvatar(
                radius: 12.sp,
                backgroundColor: _surfaceAlt(isDark),
                backgroundImage: note.createdBy?.profilePictureUrl != null
                    ? NetworkImage(note.createdBy!.profilePictureUrl!)
                    : null,
                child: note.createdBy?.profilePictureUrl == null
                    ? Icon(PhosphorIcons.user,
                        size: 14.sp, color: _textSecondary(isDark))
                    : null,
              ),
              SizedBox(width: 10.w),
              Text("Por: ${note.createdBy?.fullName ?? 'Professor'}",
                  style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      color: _textSecondary(isDark),
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

// =============================================================================
// MODAL DE CRIAÇÃO DE ANOTAÇÃO
// =============================================================================

class _CreateNoteBottomSheet extends StatefulWidget {
  final String studentId;
  final String studentName;

  const _CreateNoteBottomSheet(
      {required this.studentId, required this.studentName});

  @override
  State<_CreateNoteBottomSheet> createState() => _CreateNoteBottomSheetState();
}

class _CreateNoteBottomSheetState extends State<_CreateNoteBottomSheet> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedType = 'PRIVATE';

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _submit() async {
    if (_titleController.text.trim().isEmpty ||
        _descController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Preencha título e descrição.'),
          backgroundColor: kErrorColor));
      return;
    }

    final authProv = Provider.of<AuthProvider>(context, listen: false);
    final noteProv = Provider.of<StudentNoteProvider>(context, listen: false);

    final success = await showAttendanceOperationDialog(
      context: context,
      operation: () async {
        final result = await noteProv.createNote(
          authProvider: authProv,
          studentId: widget.studentId,
          title: _titleController.text.trim(),
          description: _descController.text.trim(),
          type: _selectedType,
        );
        if (!result) throw Exception(noteProv.errorMessage ?? 'Erro ao salvar');
      },
      loadingTitle: 'Salvando',
      loadingMessage: 'Registrando anotação...',
      successTitle: 'Salvo!',
      successMessage: 'Anotação adicionada ao perfil do aluno.',
    );

    if (success == true && mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
          color: _surface(isDark),
          borderRadius: BorderRadius.vertical(top: Radius.circular(32.r)),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.5),
                blurRadius: 40,
                offset: const Offset(0, -10))
          ]),
      child: Padding(
        padding: EdgeInsets.fromLTRB(30.w, 30.w, 30.w, 40.h),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("Nova Ocorrência",
                        style: GoogleFonts.inter(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w900,
                            color: _textPrimary(isDark))),
                    SizedBox(height: 4.h),
                    Text("Aluno: ${widget.studentName}",
                        style: GoogleFonts.inter(
                            fontSize: 14.sp, color: _textSecondary(isDark))),
                  ],
                ),
                Container(
                  decoration: BoxDecoration(
                      color: _surfaceAlt(isDark), shape: BoxShape.circle),
                  child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(PhosphorIcons.x, color: _textPrimary(isDark))),
                ),
              ],
            ),
            SizedBox(height: 30.h),
            Text('Visibilidade',
                style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark))),
            SizedBox(height: 10.h),
            DropdownButtonFormField<String>(
              value: _selectedType,
              dropdownColor: _surfaceAlt(isDark),
              decoration: InputDecoration(
                filled: true,
                fillColor: _surfaceAlt(isDark),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kPrimaryBlue)),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16.w, vertical: 16.h),
              ),
              items: [
                DropdownMenuItem(
                    value: 'PRIVATE',
                    child: Text('Privado (Apenas para mim)',
                        style: TextStyle(color: _textPrimary(isDark)))),
                DropdownMenuItem(
                    value: 'ATTENTION',
                    child: Text('Atenção (Alerta Coordenação)',
                        style: TextStyle(
                            color: kWarningYellow,
                            fontWeight: FontWeight.bold))),
                DropdownMenuItem(
                    value: 'WARNING',
                    child: Text('Advertência (Aviso aos Pais)',
                        style: TextStyle(
                            color: kErrorColor, fontWeight: FontWeight.bold))),
              ],
              onChanged: (val) => setState(() => _selectedType = val!),
            ),
            SizedBox(height: 20.h),
            Text('Assunto',
                style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark))),
            SizedBox(height: 10.h),
            TextField(
              controller: _titleController,
              style: GoogleFonts.inter(color: _textPrimary(isDark)),
              decoration: InputDecoration(
                hintText: 'Ex: Briga no recreio',
                hintStyle: TextStyle(color: _textSecondary(isDark)),
                filled: true,
                fillColor: _surfaceAlt(isDark),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kPrimaryBlue)),
              ),
            ),
            SizedBox(height: 20.h),
            Text('Descrição Detalhada',
                style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.bold,
                    color: _textPrimary(isDark))),
            SizedBox(height: 10.h),
            TextField(
              controller: _descController,
              maxLines: 4,
              style: GoogleFonts.inter(color: _textPrimary(isDark)),
              decoration: InputDecoration(
                hintText: 'Descreva a ocorrência ou observação com detalhes...',
                hintStyle: TextStyle(color: _textSecondary(isDark)),
                filled: true,
                fillColor: _surfaceAlt(isDark),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide(color: _border(isDark))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: kPrimaryBlue)),
              ),
            ),
            SizedBox(height: 30.h),
            SizedBox(
              width: double.infinity,
              height: 56.h,
              child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimaryBlue,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                child: Text("Registrar Ocorrência",
                    style: GoogleFonts.inter(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
