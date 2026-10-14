import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/class_provider.dart';
import 'package:academyhub_mobile/providers/horario_provider.dart';
import 'package:academyhub_mobile/util/teacher_class_context_helper.dart';
import 'package:academyhub_mobile/widgets/teacher_class_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class TeacherActivityClassSelectionScreen extends StatefulWidget {
  final void Function(ClassModel classData, HorarioModel? preferredSchedule)
      onOpenActivities;
  final void Function(ClassModel classData)? onOpenAttendance;

  const TeacherActivityClassSelectionScreen({
    super.key,
    required this.onOpenActivities,
    this.onOpenAttendance,
  });

  @override
  State<TeacherActivityClassSelectionScreen> createState() =>
      _TeacherActivityClassSelectionScreenState();
}

class _TeacherActivityClassSelectionScreenState
    extends State<TeacherActivityClassSelectionScreen> {
  final TextEditingController _searchController = TextEditingController();

  bool _isPreparing = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _ensureDataLoaded();
    });
    _searchController.addListener(() {
      if (!mounted) return;
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _ensureDataLoaded({bool refresh = false}) async {
    if (!mounted) return;
    setState(() => _isPreparing = true);

    try {
      await TeacherClassContextHelper.ensureDataLoaded(
        authProvider: context.read<AuthProvider>(),
        classProvider: context.read<ClassProvider>(),
        horarioProvider: context.read<HorarioProvider>(),
        academicProvider: context.read<AcademicCalendarProvider>(),
        forceRefresh: refresh,
        sharedAcrossPeriods: true,
        screen: 'classes',
      );
    } finally {
      if (mounted) {
        setState(() => _isPreparing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final classProvider = context.watch<ClassProvider>();
    final horarioProvider = context.watch<HorarioProvider>();
    final academicProvider = context.watch<AcademicCalendarProvider>();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final user = authProvider.user;

    final currentTerm =
        TeacherClassContextHelper.getCurrentTerm(academicProvider.terms);
    final effectiveHorarios = TeacherClassContextHelper.assignedHorarios(
      horarioProvider.horarios,
      academicProvider.terms,
      user: user,
      sharedAcrossPeriods: true,
    );

    final availableClasses = TeacherClassContextHelper.sortClassesForActivities(
      classes: classProvider.classes,
      horarios: horarioProvider.horarios,
      user: user,
      terms: academicProvider.terms,
      sharedAcrossPeriods: true,
    );
    final suggestion = TeacherClassContextHelper.resolveSuggestedClass(
      classes: classProvider.classes,
      horarios: horarioProvider.horarios,
      user: user,
      terms: academicProvider.terms,
      sharedAcrossPeriods: true,
    );
    TeacherClassContextHelper.logClasses(
      screen: 'classes',
      currentTerm: currentTerm,
      classes: availableClasses,
      horarios: effectiveHorarios,
    );

    var filteredClasses = availableClasses;
    if (_searchQuery.isNotEmpty) {
      filteredClasses = availableClasses.where((classData) {
        final haystack =
            '${classData.name} ${classData.grade} ${classData.shift}'
                .toLowerCase();
        return haystack.contains(_searchQuery);
      }).toList();
    }
    final isLoading = _isPreparing ||
        (classProvider.isLoading && classProvider.classes.isEmpty) ||
        (horarioProvider.isLoading && horarioProvider.horarios.isEmpty);
    final hasDataError = availableClasses.isEmpty &&
        (classProvider.error != null || horarioProvider.error != null);
    TeacherClassContextHelper.logScreenResult(
      screen: 'ClassesTab',
      isLoading: isLoading,
      totalVisibleClasses: filteredClasses.length,
      totalVisibleSchedules: effectiveHorarios.length,
      emptyStateShown: !isLoading && filteredClasses.isEmpty,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () => _ensureDataLoaded(refresh: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(18.w, 18.h, 18.w, 120.h),
          children: [
            Text(
              'Turmas',
              style: GoogleFonts.sairaCondensed(
                fontSize: 34.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A2230),
                height: 0.95,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Selecione a turma para abrir atividades, planejar tarefas e corrigir entregas.',
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                height: 1.45,
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
              ),
            ),
            SizedBox(height: 20.h),
            _SearchBox(
              controller: _searchController,
              isDark: isDark,
            ),
            if (suggestion != null && _searchQuery.isEmpty) ...[
              SizedBox(height: 18.h),
              _SuggestedClassBanner(
                suggestion: suggestion,
                isDark: isDark,
                onTap: () => widget.onOpenActivities(
                  suggestion.classData,
                  suggestion.schedule,
                ),
              ),
            ],
            SizedBox(height: 22.h),
            if (isLoading)
              Padding(
                padding: EdgeInsets.only(top: 80.h),
                child: const Center(child: CircularProgressIndicator()),
              )
            else if (hasDataError)
              _ClassesErrorState(
                isDark: isDark,
                onRetry: () => _ensureDataLoaded(refresh: true),
              )
            else if (filteredClasses.isEmpty)
              _EmptyClassesState(
                isDark: isDark,
                hasSearch: _searchQuery.isNotEmpty,
              )
            else
              ...filteredClasses.map(
                (classData) {
                  final preferredSchedule =
                      TeacherClassContextHelper.scheduleForClass(
                    classId: classData.id,
                    horarios: horarioProvider.horarios,
                    user: user,
                    terms: academicProvider.terms,
                    sharedAcrossPeriods: true,
                  );

                  return Padding(
                    padding: EdgeInsets.only(bottom: 16.h),
                    child: TeacherClassCard(
                      classData: classData,
                      isDark: isDark,
                      onTap: () => widget.onOpenActivities(
                        classData,
                        preferredSchedule,
                      ),
                      onOpenAttendance: () {
                        if (widget.onOpenAttendance != null) {
                          widget.onOpenAttendance!(classData);
                        } else {
                          widget.onOpenActivities(classData, preferredSchedule);
                        }
                      },
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _ClassesErrorState extends StatelessWidget {
  final bool isDark;
  final VoidCallback onRetry;

  const _ClassesErrorState({
    required this.isDark,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Erro ao carregar turmas. Tente novamente.',
      child: Container(
        padding: EdgeInsets.all(24.w),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF171B20) : Colors.white,
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(
            color: isDark ? const Color(0xFF2A313B) : const Color(0xFFE7EBF2),
          ),
        ),
        child: Column(
          children: [
            Icon(
              PhosphorIcons.warning_circle,
              color: Colors.orange,
              size: 32.sp,
            ),
            SizedBox(height: 14.h),
            Text(
              'Não foi possível carregar suas turmas',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 16.sp,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : const Color(0xFF1A2230),
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Verifique sua conexão e tente novamente.',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
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
    );
  }
}

class _SearchBox extends StatelessWidget {
  final TextEditingController controller;
  final bool isDark;

  const _SearchBox({
    required this.controller,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      style: GoogleFonts.inter(
        fontSize: 14.sp,
        color: isDark ? Colors.white : const Color(0xFF1A2230),
      ),
      decoration: InputDecoration(
        hintText: 'Buscar turma...',
        hintStyle: GoogleFonts.inter(
          color: isDark ? Colors.grey[500] : const Color(0xFF94A3B8),
        ),
        prefixIcon: Icon(
          PhosphorIcons.magnifying_glass,
          color: isDark ? Colors.grey[500] : const Color(0xFF64748B),
        ),
        filled: true,
        fillColor: isDark ? const Color(0xFF1D2024) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2C3440) : const Color(0xFFE5EAF1),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF2C3440) : const Color(0xFFE5EAF1),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18.r),
          borderSide: const BorderSide(
            color: Color(0xFF00A859),
            width: 1.4,
          ),
        ),
      ),
    );
  }
}

class _SuggestedClassBanner extends StatelessWidget {
  final TeacherClassSuggestion suggestion;
  final bool isDark;
  final VoidCallback onTap;

  const _SuggestedClassBanner({
    required this.suggestion,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final subjectName = suggestion.schedule?.subject.name.trim() ?? '';
    final timing = suggestion.schedule == null
        ? 'Turma recomendada para abrir suas atividades.'
        : '${suggestion.schedule!.startTime} - ${suggestion.schedule!.endTime}';

    return Container(
      padding: EdgeInsets.all(18.w),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20.r),
        gradient: const LinearGradient(
          colors: [Color(0xFF0F172A), Color(0xFF1769FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52.w,
            height: 52.w,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16.r),
            ),
            child: Icon(
              PhosphorIcons.lightning_fill,
              color: Colors.white,
              size: 24.sp,
            ),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Abrir rapido',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withOpacity(0.84),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  suggestion.classData.name,
                  style: GoogleFonts.inter(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  subjectName.isEmpty ? timing : '$subjectName • $timing',
                  style: GoogleFonts.inter(
                    fontSize: 12.5.sp,
                    color: Colors.white.withOpacity(0.84),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: 12.w),
          ElevatedButton(
            onPressed: onTap,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF0F172A),
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
            ),
            child: Text(
              'Abrir',
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyClassesState extends StatelessWidget {
  final bool isDark;
  final bool hasSearch;

  const _EmptyClassesState({
    required this.isDark,
    required this.hasSearch,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(24.w),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF171B20) : Colors.white,
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(
          color: isDark ? const Color(0xFF2A313B) : const Color(0xFFE7EBF2),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 64.w,
            height: 64.w,
            decoration: BoxDecoration(
              color: (hasSearch ? Colors.orange : const Color(0xFF1769FF))
                  .withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              hasSearch
                  ? PhosphorIcons.magnifying_glass
                  : PhosphorIcons.notepad,
              color: hasSearch ? Colors.orange : const Color(0xFF1769FF),
              size: 28.sp,
            ),
          ),
          SizedBox(height: 16.h),
          Text(
            hasSearch ? 'Nenhuma turma encontrada' : 'Nenhuma turma disponivel',
            style: GoogleFonts.inter(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: isDark ? Colors.white : const Color(0xFF1A2230),
            ),
          ),
          SizedBox(height: 8.h),
          Text(
            hasSearch
                ? 'Tente ajustar a busca para localizar a turma.'
                : 'Quando suas turmas estiverem carregadas, elas aparecerao aqui.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              height: 1.45,
              color: isDark ? Colors.grey[400] : const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}
