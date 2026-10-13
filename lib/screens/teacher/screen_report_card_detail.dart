import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/report_card_provider.dart';
import 'package:academyhub_mobile/util/early_childhood_criteria_helper.dart';
import 'package:academyhub_mobile/util/report_card_score_input.dart';
import 'package:academyhub_mobile/widgets/report_card_operation_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class ScreenReportCardDetail extends StatefulWidget {
  final ReportCardModel reportCard;
  final String studentName;
  final String guardianName;
  final String className;
  final String schoolYear;
  final String termLabel;
  final bool isDevelopmental;
  final VoidCallback? onClose;

  const ScreenReportCardDetail({
    super.key,
    required this.reportCard,
    required this.studentName,
    required this.guardianName,
    required this.className,
    required this.schoolYear,
    required this.termLabel,
    this.isDevelopmental = false,
    this.onClose,
  });

  @override
  State<ScreenReportCardDetail> createState() => _ScreenReportCardDetailState();
}

class _ScreenReportCardDetailState extends State<ScreenReportCardDetail> {
  late ReportCardModel _reportCard;

  @override
  void initState() {
    super.initState();
    _reportCard = widget.reportCard;
  }

  bool _canEdit(ReportCardSubjectModel subject) {
    final teacherId = context.read<AuthProvider>().user?.id;
    if (teacherId == null) return false;
    if (_isDevelopmental && subject.teacherId.trim().isEmpty) return true;
    return subject.teacherId == teacherId;
  }

  bool get _isDevelopmental => widget.isDevelopmental;
  double? get _average => _isDevelopmental ? null : _reportCard.averageScore;
  int get _filledCount => _isDevelopmental
      ? EarlyChildhoodCriteriaHelper.completedAreasCount(_reportCard)
      : _reportCard.filledSubjectsCount;
  int get _pendingCount => _isDevelopmental
      ? EarlyChildhoodCriteriaHelper.pendingAreasCount(_reportCard)
      : _reportCard.pendingSubjectsCount;
  int get _editableCount =>
      _reportCard.subjects.where((subject) => _canEdit(subject)).length;

  String get _generalStatus {
    if (_filledCount == 0) return 'Rascunho';
    if (_pendingCount > 0) return 'Parcial';
    return 'Completo';
  }

  Future<void> _finalize() async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      _message('Faça login para salvar o boletim.');
      return;
    }

    await showReportCardOperationDialog(
      context: context,
      loadingTitle: 'Salvando revisão',
      loadingMessage: _isDevelopmental
          ? 'Consolidando a revisão dos critérios.'
          : 'Recalculando o status consolidado do boletim.',
      loadingDetail: _isDevelopmental
          ? 'A API está validando a avaliação do desenvolvimento.'
          : 'A API está finalizando o consolidado do aluno.',
      successTitle: 'Boletim revisado',
      successMessage: 'O status consolidado foi atualizado com sucesso.',
      operation: () async {
        final provider = context.read<ReportCardProvider>();
        final ok = await provider.recalculateReportCardStatus(
          token: token,
          reportCardId: _reportCard.id,
        );
        if (!ok) {
          throw Exception(
              provider.errorMessage ?? 'Falha ao recalcular o boletim.');
        }
        if (mounted) {
          setState(() {
            _reportCard = provider.currentReportCard ?? _reportCard;
          });
        }
      },
    );
  }

  Future<void> _saveSubject(
    ReportCardSubjectModel subject, {
    double? testScore,
    double? activityScore,
    double? participationScore,
    required String observation,
  }) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      _message('Faça login para salvar o boletim.');
      return;
    }

    await showReportCardOperationDialog(
      context: context,
      loadingTitle: 'Salvando boletim',
      loadingMessage: 'Aplicando as alterações na disciplina.',
      loadingDetail: '${subject.subjectNameSnapshot} está sendo registrada.',
      successTitle: 'Disciplina salva',
      successMessage: 'As alterações foram aplicadas com sucesso.',
      operation: () async {
        final provider = context.read<ReportCardProvider>();
        final ok = await provider.updateTeacherSubjectScore(
          token: token,
          reportCardId: _reportCard.id,
          subjectId: subject.subjectId,
          testScore: testScore,
          activityScore: activityScore,
          participationScore: participationScore,
          observation: observation,
        );
        if (!ok) {
          throw Exception(
              provider.errorMessage ?? 'Falha ao salvar a disciplina.');
        }
        if (mounted) {
          setState(() {
            _reportCard = provider.currentReportCard ?? _reportCard;
          });
        }
      },
    );
  }

  Future<void> _saveDevelopmentalAssessment(
    ReportCardSubjectModel subject,
    DevelopmentalSubjectAssessmentModel assessment,
  ) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) {
      _message('Faça login para salvar o boletim.');
      return;
    }

    await showReportCardOperationDialog(
      context: context,
      loadingTitle: 'Salvando avaliação',
      loadingMessage: 'Registrando os critérios de desenvolvimento.',
      loadingDetail: '${subject.subjectNameSnapshot} está sendo salva na API.',
      successTitle: 'Avaliação salva',
      successMessage: 'Os critérios foram persistidos com sucesso.',
      operation: () async {
        final provider = context.read<ReportCardProvider>();
        final ok = await provider.updateTeacherSubjectDevelopmentalAssessment(
          token: token,
          reportCardId: _reportCard.id,
          subjectId: subject.developmentalKey,
          criteria: assessment.criteria,
          generalObservation: assessment.generalObservation,
        );
        if (!ok) {
          throw Exception(
            provider.errorMessage ?? 'Falha ao salvar a avaliação.',
          );
        }
        if (mounted) {
          setState(() {
            _reportCard = provider.currentReportCard ?? _reportCard;
          });
        }
      },
    );
  }

  void _openEditor(ReportCardSubjectModel subject) {
    if (_isDevelopmental) {
      _openDevelopmentalEditor(subject);
      return;
    }

    final testCtrl =
        TextEditingController(text: subject.testScore?.toString() ?? '');
    final actCtrl =
        TextEditingController(text: subject.activityScore?.toString() ?? '');
    final partCtrl = TextEditingController(
        text: subject.participationScore?.toString() ?? '');

    final observationController =
        TextEditingController(text: subject.observation);

    showDialog(
      context: context,
      builder: (dialogContext) {
        final p =
            _Palette(Theme.of(dialogContext).brightness == Brightness.dark);
        return AlertDialog(
          backgroundColor: p.surface,
          insetPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 24.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18.r),
            side: BorderSide(color: p.border),
          ),
          titlePadding: EdgeInsets.fromLTRB(22.w, 24.h, 22.w, 12.h),
          contentPadding: EdgeInsets.fromLTRB(22.w, 0, 22.w, 24.h),
          title: Text(
            'Atualizar ${subject.subjectNameSnapshot}',
            style: GoogleFonts.inter(
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
              color: p.title,
            ),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Preencha as notas parciais. A soma total não pode ultrapassar 10 pontos.',
                    style: GoogleFonts.inter(
                      fontSize: 13.sp,
                      color: p.subtitle,
                    ),
                  ),
                  SizedBox(height: 18.h),
                  _DialogInput(
                    controller: testCtrl,
                    label: 'Prova (Pr)',
                    hint: 'Ex: 6.0',
                    palette: p,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  SizedBox(height: 12.h),
                  _DialogInput(
                    controller: actCtrl,
                    label: 'Atividade (At)',
                    hint: 'Ex: 2.0',
                    palette: p,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  SizedBox(height: 12.h),
                  _DialogInput(
                    controller: partCtrl,
                    label: 'Participação (Pa)',
                    hint: 'Ex: 2.0',
                    palette: p,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                  ),
                  SizedBox(height: 16.h),
                  _DialogInput(
                    controller: observationController,
                    label: 'Observação Pedagógica',
                    hint: 'Digite uma observação (Opcional)',
                    palette: p,
                    maxLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 16.h),
          actions: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      side: BorderSide(color: p.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      'Cancelar',
                      style: GoogleFonts.inter(
                        color: p.title,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 14.h),
                      backgroundColor: p.accentGreen,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                    ),
                    onPressed: () async {
                      double? t;
                      double? a;
                      double? part;
                      try {
                        t = parseReportCardScore(testCtrl.text, 'Prova');
                        a = parseReportCardScore(actCtrl.text, 'Atividade');
                        part =
                            parseReportCardScore(partCtrl.text, 'Participação');
                      } on FormatException catch (error) {
                        _message(error.message);
                        return;
                      }
                      if (t == null && a == null && part == null) {
                        _message('Informe ao menos uma nota.');
                        return;
                      }
                      final total = (t ?? 0) + (a ?? 0) + (part ?? 0);

                      if (total > 10) {
                        _message(
                            'A soma das notas ($total) não pode ultrapassar 10.');
                        return;
                      }

                      Navigator.pop(dialogContext);
                      await _saveSubject(
                        subject,
                        testScore: t,
                        activityScore: a,
                        participationScore: part,
                        observation: observationController.text.trim(),
                      );
                    },
                    child: Text(
                      'Salvar',
                      style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _openDevelopmentalEditor(ReportCardSubjectModel subject) {
    final initial =
        EarlyChildhoodCriteriaHelper.assessmentForSubject(_reportCard, subject);
    final observationController =
        TextEditingController(text: initial.generalObservation);
    var criteria = List<DevelopmentalCriterionAssessmentModel>.from(
      initial.criteria,
    );

    showDialog(
      context: context,
      builder: (dialogContext) {
        final p =
            _Palette(Theme.of(dialogContext).brightness == Brightness.dark);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: p.surface,
              insetPadding:
                  EdgeInsets.symmetric(horizontal: 14.w, vertical: 20.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18.r),
                side: BorderSide(color: p.border),
              ),
              titlePadding: EdgeInsets.fromLTRB(20.w, 22.h, 20.w, 8.h),
              contentPadding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
              title: Text(
                'Avaliar ${subject.subjectNameSnapshot.toUpperCase()}',
                style: GoogleFonts.inter(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w800,
                  color: p.title,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Selecione o estágio de desenvolvimento observado em cada critério. Use “Não trabalhado no bimestre” quando o objetivo não tiver sido trabalhado neste período.',
                        style: GoogleFonts.inter(
                          fontSize: 12.5.sp,
                          fontWeight: FontWeight.w500,
                          color: p.subtitle,
                          height: 1.35,
                        ),
                      ),
                      SizedBox(height: 16.h),
                      ...List.generate(criteria.length, (index) {
                        final criterion = criteria[index];
                        return _DevelopmentCriteriaSelector(
                          palette: p,
                          criterion: criterion,
                          onChanged: (status) {
                            setDialogState(() {
                              criteria[index] = criterion.copyWith(
                                status: status,
                                updatedAt: DateTime.now(),
                              );
                            });
                          },
                        );
                      }),
                      SizedBox(height: 14.h),
                      _DialogInput(
                        controller: observationController,
                        label: 'Observação pedagógica',
                        hint: 'Digite uma observação da área (opcional)',
                        palette: p,
                        maxLines: 3,
                      ),
                    ],
                  ),
                ),
              ),
              actionsPadding: EdgeInsets.fromLTRB(18.w, 0, 18.w, 16.h),
              actions: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          side: BorderSide(color: p.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(
                          'Cancelar',
                          style: GoogleFonts.inter(
                            color: p.title,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          padding: EdgeInsets.symmetric(vertical: 14.h),
                          backgroundColor: p.accentGreen,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                        onPressed: () async {
                          Navigator.pop(dialogContext);
                          await _saveDevelopmentalAssessment(
                            subject,
                            initial.copyWith(
                              criteria: criteria,
                              generalObservation:
                                  observationController.text.trim(),
                            ),
                          );
                        },
                        child: Text(
                          'Salvar',
                          style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = _Palette(Theme.of(context).brightness == Brightness.dark);
    final currentTeacherId = context.watch<AuthProvider>().user?.id;

    return Scaffold(
      backgroundColor: p.page,
      appBar: AppBar(
        backgroundColor: p.page,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: widget.onClose != null
            ? IconButton(
                icon: Icon(PhosphorIcons.arrow_left, color: p.title),
                onPressed: widget.onClose,
              )
            : null,
        title: Text(
          'Boletim do Aluno',
          style: GoogleFonts.inter(
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
            color: p.title,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(PhosphorIcons.eye, color: p.accentBlue),
            tooltip: 'Pré-visualizar',
            onPressed: () => _message('Pré-visualização em breve.'),
          ),
          SizedBox(width: 8.w),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: EdgeInsets.all(16.w),
          decoration: BoxDecoration(
            color: p.surface,
            border: Border(top: BorderSide(color: p.border)),
          ),
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accentGreen,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(vertical: 16.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
              ),
            ),
            icon: Icon(PhosphorIcons.floppy_disk, size: 20.sp),
            label: Text(
              'Salvar Revisão Consolidada',
              style: GoogleFonts.inter(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            onPressed: _finalize,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 24.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _summary(p),
            SizedBox(height: 16.h),
            _buildInfoStripsScroll(p),
            SizedBox(height: 16.h),
            _GeneralObservationCard(palette: p, reportCard: _reportCard),
            SizedBox(height: 24.h),
            Text(
              _isDevelopmental ? 'Áreas do Boletim' : 'Disciplinas do Boletim',
              style: GoogleFonts.sairaCondensed(
                fontSize: 24.sp,
                fontWeight: FontWeight.w700,
                color: p.title,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              _isDevelopmental
                  ? 'Avalie os critérios das áreas vinculadas a você.'
                  : 'Apenas disciplinas vinculadas a você podem ser editadas.',
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: p.subtitle,
              ),
            ),
            SizedBox(height: 16.h),
            _buildDisciplineList(p, currentTeacherId),
          ],
        ),
      ),
    );
  }

  Widget _summary(_Palette p) {
    final average = _average;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 54.w,
                height: 54.w,
                decoration: BoxDecoration(
                  color: p.iconSurface,
                  shape: BoxShape.circle,
                  border: Border.all(color: p.border),
                ),
                child: Center(
                  child: Text(
                    widget.studentName.isNotEmpty
                        ? widget.studentName.substring(0, 1).toUpperCase()
                        : '?',
                    style: GoogleFonts.inter(
                      fontSize: 20.sp,
                      fontWeight: FontWeight.w800,
                      color: p.accentBlue,
                    ),
                  ),
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.studentName,
                      style: GoogleFonts.inter(
                        fontSize: 18.sp,
                        fontWeight: FontWeight.w700,
                        color: p.title,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Resp: ${widget.guardianName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: p.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          SizedBox(
            height: 34.h,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _Tag(text: widget.className, palette: p, type: _TagType.green),
                SizedBox(width: 8.w),
                _Tag(text: widget.termLabel, palette: p, type: _TagType.blue),
                SizedBox(width: 8.w),
                _Tag(
                    text: 'Ano ${widget.schoolYear}',
                    palette: p,
                    type: _TagType.neutral),
                SizedBox(width: 8.w),
                if (!_isDevelopmental)
                  _Tag(
                    text:
                        'Mínimo ${_reportCard.minimumAverage.toStringAsFixed(1)}',
                    palette: p,
                    type: _TagType.orange,
                  )
                else
                  _Tag(
                    text: 'Avaliação do desenvolvimento',
                    palette: p,
                    type: _TagType.orange,
                  ),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _MiniMetricCard(
                  title: 'Status Geral',
                  value: _generalStatus,
                  subtitle: 'Progresso do boletim',
                  palette: p,
                  accent: p.accentBlue,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _MiniMetricCard(
                  title: _isDevelopmental ? 'Critérios' : 'Média Atual',
                  value: _isDevelopmental
                      ? '${EarlyChildhoodCriteriaHelper.filledCriteriaCount(_reportCard)}/${EarlyChildhoodCriteriaHelper.totalCriteriaCount(_reportCard)}'
                      : (average?.toStringAsFixed(1) ?? '--'),
                  subtitle: _isDevelopmental
                      ? 'Avaliados no bimestre'
                      : 'Consolidado parcial',
                  palette: p,
                  accent: _isDevelopmental
                      ? p.accentGreen
                      : average == null
                          ? p.muted
                          : average >= _reportCard.minimumAverage
                              ? p.accentGreen
                              : p.accentRed,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoStripsScroll(_Palette p) {
    return SizedBox(
      height: 76.h,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          SizedBox(
            width: 220.w,
            child: _InfoStripCard(
              icon: PhosphorIcons.notepad,
              title: _isDevelopmental ? 'Áreas avaliadas' : 'Preenchidas',
              value: '$_filledCount/${_reportCard.subjects.length}',
              palette: p,
              accent: p.accentGreen,
            ),
          ),
          SizedBox(width: 12.w),
          SizedBox(
            width: 180.w,
            child: _InfoStripCard(
              icon: PhosphorIcons.warning_circle,
              title: _isDevelopmental ? 'Áreas pendentes' : 'Pendências',
              value: _pendingCount.toString(),
              palette: p,
              accent: _pendingCount > 0 ? p.accentOrange : p.accentGreen,
            ),
          ),
          SizedBox(width: 12.w),
          SizedBox(
            width: 200.w,
            child: _InfoStripCard(
              icon: PhosphorIcons.chalkboard_teacher,
              title: _isDevelopmental ? 'Suas Áreas' : 'Suas Disciplinas',
              value: _editableCount.toString(),
              palette: p,
              accent: p.accentBlue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDisciplineList(_Palette p, String? currentTeacherId) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _reportCard.subjects.length,
      separatorBuilder: (_, __) => SizedBox(height: 12.h),
      itemBuilder: (context, index) {
        final subject = _reportCard.subjects[index];
        final editable = currentTeacherId != null &&
            ((_isDevelopmental && subject.teacherId.trim().isEmpty) ||
                subject.teacherId == currentTeacherId);
        if (_isDevelopmental) {
          final assessment = EarlyChildhoodCriteriaHelper.assessmentForSubject(
            _reportCard,
            subject,
          );
          return _EarlyChildhoodSubjectCard(
            subject: subject,
            assessment: assessment,
            palette: p,
            editable: editable,
            onEdit: editable ? () => _openEditor(subject) : null,
          );
        }
        return _SubjectMobileCard(
          subject: subject,
          palette: p,
          minimumAverage: _reportCard.minimumAverage,
          editable: editable,
          onEdit: editable ? () => _openEditor(subject) : null,
        );
      },
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
  Color get accentRed => const Color(0xFFE05555);
  Color get accentPurple => const Color(0xFF7A5AF8);
}

class _MiniMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final _Palette palette;
  final Color accent;

  const _MiniMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.palette,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: palette.subtitle,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: GoogleFonts.sairaCondensed(
              fontSize: 22.sp,
              fontWeight: FontWeight.w700,
              color: accent,
              height: 1,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11.sp,
              fontWeight: FontWeight.w500,
              color: palette.muted,
            ),
          ),
        ],
      ),
    );
  }
}

enum _TagType { green, blue, orange, neutral }

class _Tag extends StatelessWidget {
  final String text;
  final _Palette palette;
  final _TagType type;

  const _Tag({
    required this.text,
    required this.palette,
    required this.type,
  });

  @override
  Widget build(BuildContext context) {
    late Color bg;
    late Color fg;
    switch (type) {
      case _TagType.green:
        bg = palette.isDark ? const Color(0xFF1C2B23) : const Color(0xFFEEF9F1);
        fg = palette.accentGreen;
        break;
      case _TagType.blue:
        bg = palette.isDark ? const Color(0xFF1C2638) : const Color(0xFFEFF5FF);
        fg = palette.accentBlue;
        break;
      case _TagType.orange:
        bg = palette.isDark ? const Color(0xFF2A231A) : const Color(0xFFFFF5E8);
        fg = palette.accentOrange;
        break;
      case _TagType.neutral:
        bg = palette.surfaceAlt;
        fg = palette.subtitle;
        break;
    }
    return Container(
      alignment: Alignment.center,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: _colorWithOpacity(fg, 0.14)),
      ),
      child: Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11.5.sp,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _InfoStripCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final _Palette palette;
  final Color accent;

  const _InfoStripCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.palette,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          Container(
            width: 36.w,
            height: 36.w,
            decoration: BoxDecoration(
              color: palette.iconSurface,
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, size: 18.sp, color: accent),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: palette.subtitle,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 15.sp,
                    fontWeight: FontWeight.w800,
                    color: palette.title,
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

class _GeneralObservationCard extends StatelessWidget {
  final _Palette palette;
  final ReportCardModel reportCard;

  const _GeneralObservationCard({
    required this.palette,
    required this.reportCard,
  });

  @override
  Widget build(BuildContext context) {
    final text = reportCard.generalObservation.trim().isEmpty
        ? 'Nenhuma observação geral cadastrada.'
        : reportCard.generalObservation.trim();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(PhosphorIcons.chat_circle_text,
                  size: 18.sp, color: palette.muted),
              SizedBox(width: 8.w),
              Text(
                'Observação Geral',
                style: GoogleFonts.inter(
                  fontSize: 14.sp,
                  fontWeight: FontWeight.w700,
                  color: palette.title,
                ),
              ),
            ],
          ),
          SizedBox(height: 10.h),
          Text(
            text,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: palette.subtitle,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _EarlyChildhoodSubjectCard extends StatelessWidget {
  final ReportCardSubjectModel subject;
  final DevelopmentalSubjectAssessmentModel assessment;
  final _Palette palette;
  final bool editable;
  final VoidCallback? onEdit;

  const _EarlyChildhoodSubjectCard({
    required this.subject,
    required this.assessment,
    required this.palette,
    required this.editable,
    required this.onEdit,
  });

  Color _statusColor() {
    if (assessment.isComplete) return palette.accentGreen;
    if (assessment.isStarted) return palette.accentOrange;
    return palette.muted;
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _statusColor();
    final progressLabel =
        '${assessment.filledCriteriaCount}/${assessment.totalCriteriaCount} critérios avaliados';

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color:
              editable ? palette.accentBlue.withOpacity(0.4) : palette.border,
          width: editable ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.subjectNameSnapshot,
                      style: GoogleFonts.inter(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: palette.title,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Prof. ${subject.teacherNameSnapshot}',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: palette.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(
                label: assessment.completionStatusLabel,
                color: statusColor,
                palette: palette,
              ),
            ],
          ),
          SizedBox(height: 14.h),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: palette.border),
            ),
            child: Row(
              children: [
                Icon(
                  PhosphorIcons.check_square_offset,
                  size: 18.sp,
                  color: statusColor,
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    progressLabel,
                    style: GoogleFonts.inter(
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w700,
                      color: palette.title,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (assessment.generalObservation.trim().isNotEmpty) ...[
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: palette.input,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                assessment.generalObservation.trim(),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: palette.subtitle,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          SizedBox(height: 16.h),
          Align(
            alignment: Alignment.centerRight,
            child: editable
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.surfaceAlt,
                      foregroundColor: palette.accentBlue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        side: BorderSide(color: palette.border),
                      ),
                    ),
                    icon: Icon(PhosphorIcons.pencil_simple_line, size: 16.sp),
                    label: Text(
                      'Avaliar',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onEdit,
                  )
                : Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.lock,
                            size: 14.sp, color: palette.muted),
                        SizedBox(width: 6.w),
                        Text(
                          'Somente Leitura',
                          style: GoogleFonts.inter(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DevelopmentCriteriaSelector extends StatelessWidget {
  final _Palette palette;
  final DevelopmentalCriterionAssessmentModel criterion;
  final ValueChanged<String> onChanged;

  const _DevelopmentCriteriaSelector({
    required this.palette,
    required this.criterion,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: EdgeInsets.only(bottom: 14.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: palette.surfaceAlt,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            criterion.description,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: palette.title,
              height: 1.3,
            ),
          ),
          SizedBox(height: 10.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 8.h,
            children: EarlyChildhoodCriteriaHelper.compactStatusLabels.entries
                .map(
                  (entry) => ChoiceChip(
                    label: Text(entry.value),
                    selected: criterion.status == entry.key,
                    onSelected: (_) => onChanged(entry.key),
                    selectedColor: palette.accentBlue
                        .withOpacity(palette.isDark ? 0.22 : 0.12),
                    backgroundColor: palette.surface,
                    side: BorderSide(
                      color: criterion.status == entry.key
                          ? palette.accentBlue.withOpacity(0.35)
                          : palette.border,
                    ),
                    labelStyle: GoogleFonts.inter(
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w700,
                      color: criterion.status == entry.key
                          ? palette.accentBlue
                          : palette.subtitle,
                    ),
                  ),
                )
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _SubjectMobileCard extends StatelessWidget {
  final ReportCardSubjectModel subject;
  final _Palette palette;
  final double minimumAverage;
  final bool editable;
  final VoidCallback? onEdit;

  const _SubjectMobileCard({
    required this.subject,
    required this.palette,
    required this.minimumAverage,
    required this.editable,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = subject.score == null
        ? palette.muted
        : subject.score! >= minimumAverage
            ? palette.accentGreen
            : palette.accentRed;

    final hasObservation = subject.observation.trim().isNotEmpty;

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color:
              editable ? palette.accentBlue.withOpacity(0.4) : palette.border,
          width: editable ? 1.5 : 1.0,
        ),
        boxShadow: editable
            ? [
                BoxShadow(
                  color: palette.accentBlue.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subject.subjectNameSnapshot,
                      style: GoogleFonts.inter(
                        fontSize: 16.sp,
                        fontWeight: FontWeight.w700,
                        color: palette.title,
                      ),
                    ),
                    SizedBox(height: 4.h),
                    Text(
                      'Prof. ${subject.teacherNameSnapshot}',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w500,
                        color: palette.subtitle,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 8.w),
              _StatusChip(
                label: subject.score == null
                    ? 'Pendente'
                    : subject.score! >= minimumAverage
                        ? 'Na média'
                        : 'Abaixo',
                color: statusColor,
                palette: palette,
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: palette.surfaceAlt,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Média Final',
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w600,
                        color: palette.subtitle,
                      ),
                    ),
                    Text(
                      subject.score?.toStringAsFixed(1) ?? '--',
                      style: GoogleFonts.sairaCondensed(
                        fontSize: 26.sp,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
                SizedBox(width: 16.w),
                Container(width: 1, height: 36.h, color: palette.divider),
                SizedBox(width: 16.w),
                Expanded(
                  child: Wrap(
                    spacing: 8.w,
                    runSpacing: 8.h,
                    children: [
                      _SubScoreBadge(
                          label: 'Pr',
                          score: subject.testScore,
                          palette: palette),
                      _SubScoreBadge(
                          label: 'At',
                          score: subject.activityScore,
                          palette: palette),
                      _SubScoreBadge(
                          label: 'Pa',
                          score: subject.participationScore,
                          palette: palette),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (hasObservation) ...[
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: palette.input,
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Text(
                subject.observation.trim(),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  color: palette.subtitle,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
          if (subject.testScoreSource?.hasSource == true) ...[
            SizedBox(height: 12.h),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: palette.accentBlue.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                  color: palette.accentBlue.withOpacity(0.18),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    PhosphorIcons.upload_simple,
                    size: 15.sp,
                    color: palette.accentBlue,
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      'Origem: ${subject.testScoreSource!.examTitle}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 12.sp,
                        fontWeight: FontWeight.w700,
                        color: palette.accentBlue,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          SizedBox(height: 16.h),
          Align(
            alignment: Alignment.centerRight,
            child: editable
                ? ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: palette.surfaceAlt,
                      foregroundColor: palette.accentBlue,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r),
                        side: BorderSide(color: palette.border),
                      ),
                    ),
                    icon: Icon(PhosphorIcons.pencil_simple_line, size: 16.sp),
                    label: Text(
                      'Editar Notas',
                      style: GoogleFonts.inter(
                        fontSize: 13.sp,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: onEdit,
                  )
                : Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    decoration: BoxDecoration(
                      color: palette.surfaceAlt,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: palette.border),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.lock,
                            size: 14.sp, color: palette.muted),
                        SizedBox(width: 6.w),
                        Text(
                          'Somente Leitura',
                          style: GoogleFonts.inter(
                            fontSize: 12.sp,
                            fontWeight: FontWeight.w600,
                            color: palette.muted,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _SubScoreBadge extends StatelessWidget {
  final String label;
  final double? score;
  final _Palette palette;

  const _SubScoreBadge({
    required this.label,
    required this.score,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(6.r),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        '$label: ${score?.toStringAsFixed(1) ?? '--'}',
        style: GoogleFonts.inter(
          fontSize: 11.sp,
          fontWeight: FontWeight.w600,
          color: palette.subtitle,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final _Palette palette;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: _colorWithOpacity(color, palette.isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: _colorWithOpacity(color, 0.16)),
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

class _DialogInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final _Palette palette;
  final int maxLines;
  final TextInputType? keyboardType;

  const _DialogInput({
    required this.controller,
    required this.label,
    required this.hint,
    required this.palette,
    this.maxLines = 1,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 13.sp,
            fontWeight: FontWeight.w700,
            color: palette.title,
          ),
        ),
        SizedBox(height: 8.h),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          style: GoogleFonts.inter(
            fontSize: 14.sp,
            fontWeight: FontWeight.w600,
            color: palette.title,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.inter(
              color: palette.muted,
              fontWeight: FontWeight.w500,
            ),
            filled: true,
            fillColor: palette.input,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: palette.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10.r),
              borderSide: BorderSide(color: palette.accentBlue, width: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

Color _colorWithOpacity(Color color, double opacity) {
  return Color.fromRGBO(
    (color.r * 255.0).round(),
    (color.g * 255.0).round(),
    (color.b * 255.0).round(),
    opacity,
  );
}
