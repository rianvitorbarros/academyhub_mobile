import 'package:academyhub_mobile/model/class_model.dart';
import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:academyhub_mobile/model/term_model.dart';
import 'package:academyhub_mobile/providers/academic_calendar_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/class_provider.dart';
import 'package:academyhub_mobile/providers/report_card_provider.dart';
import 'package:academyhub_mobile/util/report_card_score_input.dart';
import 'package:flutter/material.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

class PhysicalEducationGradeScreen extends StatefulWidget {
  const PhysicalEducationGradeScreen({super.key});

  @override
  State<PhysicalEducationGradeScreen> createState() =>
      _PhysicalEducationGradeScreenState();
}

class _PhysicalEducationGradeScreenState
    extends State<PhysicalEducationGradeScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<ClassModel> _classes = [];
  List<TermModel> _terms = [];
  List<ReportCardModel> _cards = [];

  ClassModel? _selectedClass;
  TermModel? _selectedTerm;
  String? _subjectId;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bootstrap());
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
      if (academic.schoolYears.isEmpty) await academic.fetchSchoolYears();
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

      _classes = classesProvider.classes;
      _terms = academic.terms;
      _selectedClass = _classes.isNotEmpty ? _classes.first : null;
      _selectedTerm = _resolveCurrentTerm(_terms) ??
          (_terms.isNotEmpty ? _terms.first : null);
      await _loadCards();
    } catch (e) {
      _error = e.toString().replaceAll('Exception: ', '');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  TermModel? _resolveCurrentTerm(List<TermModel> terms) {
    final now = DateTime.now();
    for (final term in terms) {
      if (term.tipo != 'Letivo') continue;
      if (!now.isBefore(term.startDate) && !now.isAfter(term.endDate)) {
        return term;
      }
    }
    return null;
  }

  Future<void> _loadCards() async {
    final auth = context.read<AuthProvider>();
    final academic = context.read<AcademicCalendarProvider>();
    final token = auth.token;
    if (token == null || _selectedClass == null || _selectedTerm == null) {
      return;
    }
    final year = academic.selectedSchoolYear?.year ?? DateTime.now().year;
    final provider = context.read<ReportCardProvider>();
    _cards = await provider.generateClassReportCards(
      token: token,
      classId: _selectedClass!.id,
      termId: _selectedTerm!.id,
      schoolYear: year,
    );
    _subjectId = _resolvePhysicalSubjectId(_cards);
    _selectedIndex = 0;
  }

  String? _resolvePhysicalSubjectId(List<ReportCardModel> cards) {
    for (final card in cards) {
      for (final subject in card.subjects) {
        final name = subject.subjectNameSnapshot.toLowerCase();
        if (name.contains('educa') && name.contains('f')) {
          return subject.subjectId;
        }
      }
    }
    return null;
  }

  ReportCardSubjectModel? _physicalSubject(ReportCardModel card) {
    if (_subjectId == null) return null;
    try {
      return card.subjects.firstWhere((item) => item.subjectId == _subjectId);
    } catch (_) {
      return null;
    }
  }

  String _studentName(ReportCardModel card) {
    if (card.studentNameSnapshot.trim().isNotEmpty) {
      return card.studentNameSnapshot.trim();
    }
    final end = card.studentId.length < 6 ? card.studentId.length : 6;
    return 'Aluno ${card.studentId.substring(0, end)}';
  }

  String _statusFor(ReportCardSubjectModel? subject) {
    final obs = subject?.observation.toLowerCase() ?? '';
    if (obs.contains('[dispensado]') || obs.contains('[atestado]')) {
      return 'Dispensado';
    }
    if (obs.contains('[ausente]')) return 'Ausente';
    if (subject?.score != null) return 'Avaliado';
    if (subject?.activityScore != null || subject?.participationScore != null) {
      return 'Parcial';
    }
    return 'Pendente';
  }

  Future<void> _saveSubject({
    required ReportCardModel card,
    required ReportCardSubjectModel subject,
    required double? testScore,
    required double? activityScore,
    required double? participationScore,
    required String observation,
  }) async {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    final total =
        (testScore ?? 0) + (activityScore ?? 0) + (participationScore ?? 0);
    if (total > 10) {
      _message('A média prevista ultrapassa 10 pontos.', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final provider = context.read<ReportCardProvider>();
      final ok = await provider.updateTeacherSubjectScore(
        token: token,
        reportCardId: card.id,
        subjectId: subject.subjectId,
        testScore: testScore,
        activityScore: activityScore,
        participationScore: participationScore,
        observation: observation,
      );
      if (!ok) {
        throw Exception(provider.errorMessage ?? 'Falha ao salvar avaliação.');
      }
      await _loadCards();
      if (mounted) {
        setState(() {
          if (_selectedIndex < _cards.length - 1) _selectedIndex += 1;
        });
      }
      _message('Avaliação salva.');
    } catch (e) {
      _message(e.toString().replaceAll('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String message, {bool error = false}) {
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
    final p = _PePalette(Theme.of(context).brightness == Brightness.dark);
    final selectedCard = _cards.isNotEmpty
        ? _cards[_selectedIndex.clamp(0, _cards.length - 1)]
        : null;
    final selectedSubject =
        selectedCard == null ? null : _physicalSubject(selectedCard);

    return Scaffold(
      backgroundColor: p.page,
      appBar: AppBar(
        backgroundColor: p.page,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          'Avaliação Física',
          style: GoogleFonts.inter(
            fontSize: 18.sp,
            fontWeight: FontWeight.w800,
            color: p.title,
          ),
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: p.green))
          : _error != null
              ? Center(child: Text(_error!, style: TextStyle(color: p.red)))
              : ListView(
                  padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 120.h),
                  children: [
                    _buildSelectors(p),
                    SizedBox(height: 14.h),
                    if (_subjectId == null)
                      _EmptyPeBox(
                        palette: p,
                        title: 'Educação Física não encontrada',
                        message:
                            'A turma selecionada não possui disciplina de Educação Física no boletim deste bimestre.',
                      )
                    else ...[
                      _buildSummary(p),
                      SizedBox(height: 14.h),
                      _buildStudents(p),
                      SizedBox(height: 14.h),
                      if (selectedCard != null && selectedSubject != null)
                        _PhysicalStudentEditor(
                          key: ValueKey(selectedCard.id),
                          palette: p,
                          studentName: _studentName(selectedCard),
                          subject: selectedSubject,
                          saving: _saving,
                          onSave: ({
                            required testScore,
                            required activityScore,
                            required participationScore,
                            required observation,
                          }) =>
                              _saveSubject(
                            card: selectedCard,
                            subject: selectedSubject,
                            testScore: testScore,
                            activityScore: activityScore,
                            participationScore: participationScore,
                            observation: observation,
                          ),
                        ),
                    ],
                  ],
                ),
    );
  }

  Widget _buildSelectors(_PePalette p) {
    return Row(
      children: [
        Expanded(
          child: _PeDropdown<ClassModel>(
            value: _selectedClass,
            items: _classes,
            label: (item) => item.name,
            palette: p,
            onChanged: (value) async {
              setState(() => _selectedClass = value);
              await _loadCards();
              if (mounted) setState(() {});
            },
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: _PeDropdown<TermModel>(
            value: _selectedTerm,
            items: _terms,
            label: (item) => item.titulo,
            palette: p,
            onChanged: (value) async {
              setState(() => _selectedTerm = value);
              await _loadCards();
              if (mounted) setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSummary(_PePalette p) {
    final statuses = _cards
        .map((card) => _statusFor(_physicalSubject(card)))
        .fold<Map<String, int>>({}, (map, status) {
      map[status] = (map[status] ?? 0) + 1;
      return map;
    });
    return Container(
      padding: EdgeInsets.all(14.w),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(color: p.border),
      ),
      child: Wrap(
        spacing: 8.w,
        runSpacing: 8.h,
        children: statuses.entries
            .map((entry) => _PeStatusChip(
                  label: '${entry.key} ${entry.value}',
                  color: _statusColor(entry.key, p),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildStudents(_PePalette p) {
    return SizedBox(
      height: 92.h,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _cards.length,
        separatorBuilder: (_, __) => SizedBox(width: 8.w),
        itemBuilder: (context, index) {
          final card = _cards[index];
          final status = _statusFor(_physicalSubject(card));
          final selected = index == _selectedIndex;
          return InkWell(
            onTap: () => setState(() => _selectedIndex = index),
            borderRadius: BorderRadius.circular(14.r),
            child: Container(
              width: 170.w,
              padding: EdgeInsets.all(12.w),
              decoration: BoxDecoration(
                color: selected ? p.green.withOpacity(0.10) : p.surface,
                borderRadius: BorderRadius.circular(14.r),
                border: Border.all(
                  color: selected ? p.green : p.border,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _studentName(card),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: p.title,
                    ),
                  ),
                  const Spacer(),
                  _PeStatusChip(label: status, color: _statusColor(status, p)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Color _statusColor(String status, _PePalette p) {
    return switch (status) {
      'Avaliado' => p.green,
      'Parcial' => p.blue,
      'Ausente' => p.orange,
      'Dispensado' => p.purple,
      _ => p.muted,
    };
  }
}

class _PhysicalStudentEditor extends StatefulWidget {
  final _PePalette palette;
  final String studentName;
  final ReportCardSubjectModel subject;
  final bool saving;
  final Future<void> Function({
    required double? testScore,
    required double? activityScore,
    required double? participationScore,
    required String observation,
  }) onSave;

  const _PhysicalStudentEditor({
    super.key,
    required this.palette,
    required this.studentName,
    required this.subject,
    required this.saving,
    required this.onSave,
  });

  @override
  State<_PhysicalStudentEditor> createState() => _PhysicalStudentEditorState();
}

class _PhysicalStudentEditorState extends State<_PhysicalStudentEditor> {
  late final TextEditingController _testCtrl;
  late final TextEditingController _activityCtrl;
  late final TextEditingController _participationCtrl;
  late final TextEditingController _observationCtrl;
  String _attendanceState = 'avaliado';

  @override
  void initState() {
    super.initState();
    _testCtrl =
        TextEditingController(text: widget.subject.testScore?.toString() ?? '');
    _activityCtrl = TextEditingController(
        text: widget.subject.activityScore?.toString() ?? '');
    _participationCtrl = TextEditingController(
        text: widget.subject.participationScore?.toString() ?? '');
    _observationCtrl = TextEditingController(text: widget.subject.observation);
    final obs = widget.subject.observation.toLowerCase();
    if (obs.contains('[dispensado]') || obs.contains('[atestado]')) {
      _attendanceState = 'dispensado';
    } else if (obs.contains('[ausente]')) {
      _attendanceState = 'ausente';
    }
  }

  @override
  void dispose() {
    _testCtrl.dispose();
    _activityCtrl.dispose();
    _participationCtrl.dispose();
    _observationCtrl.dispose();
    super.dispose();
  }

  double? _parse(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  double get _predicted =>
      (_parse(_testCtrl) ?? 0) +
      (_parse(_activityCtrl) ?? 0) +
      (_parse(_participationCtrl) ?? 0);

  Future<void> _save() async {
    double? testScore;
    double? activityScore;
    double? participationScore;
    try {
      testScore = _attendanceState == 'avaliado'
          ? parseReportCardScore(_testCtrl.text, 'Prova')
          : widget.subject.testScore;
      activityScore = _attendanceState == 'avaliado'
          ? parseReportCardScore(_activityCtrl.text, 'Atividade')
          : widget.subject.activityScore;
      participationScore = _attendanceState == 'avaliado'
          ? parseReportCardScore(_participationCtrl.text, 'Participação')
          : widget.subject.participationScore;
    } on FormatException catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.message)));
      return;
    }
    if (testScore == null &&
        activityScore == null &&
        participationScore == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Informe ao menos uma nota.')));
      return;
    }
    var observation = _observationCtrl.text.trim();
    if (_attendanceState == 'ausente') {
      observation = '[ausente] $observation'.trim();
    } else if (_attendanceState == 'dispensado') {
      observation = '[dispensado/atestado] $observation'.trim();
    }
    await widget.onSave(
      testScore: testScore,
      activityScore: activityScore,
      participationScore: participationScore,
      observation: observation,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.palette;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(18.r),
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.studentName,
              style: GoogleFonts.inter(
                  fontSize: 18.sp,
                  fontWeight: FontWeight.w900,
                  color: p.title)),
          SizedBox(height: 12.h),
          SegmentedButton<String>(
            selected: {_attendanceState},
            onSelectionChanged: (values) =>
                setState(() => _attendanceState = values.first),
            segments: const [
              ButtonSegment(value: 'avaliado', label: Text('Avaliado')),
              ButtonSegment(value: 'ausente', label: Text('Ausente')),
              ButtonSegment(value: 'dispensado', label: Text('Dispensado')),
            ],
          ),
          SizedBox(height: 12.h),
          _PeInput(
              controller: _testCtrl,
              label: 'Prova prática/teórica',
              palette: p),
          SizedBox(height: 10.h),
          _PeInput(
              controller: _activityCtrl,
              label: 'Atividade / execução prática',
              palette: p),
          SizedBox(height: 10.h),
          _PeInput(
              controller: _participationCtrl,
              label: 'Participação / cooperação',
              palette: p),
          SizedBox(height: 10.h),
          _PeInput(
            controller: _observationCtrl,
            label: 'Observação',
            palette: p,
            maxLines: 3,
            keyboardType: TextInputType.text,
          ),
          SizedBox(height: 12.h),
          Container(
            padding: EdgeInsets.all(12.w),
            decoration: BoxDecoration(
              color: _predicted > 10
                  ? p.red.withOpacity(0.08)
                  : p.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.calculator,
                    color: _predicted > 10 ? p.red : p.green),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    'Média prevista: ${_predicted.toStringAsFixed(1)}',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w800,
                      color: _predicted > 10 ? p.red : p.green,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          ElevatedButton.icon(
            onPressed: widget.saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: p.green,
              foregroundColor: Colors.white,
              minimumSize: Size.fromHeight(48.h),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r)),
            ),
            icon: widget.saving
                ? SizedBox(
                    width: 18.w,
                    height: 18.w,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(PhosphorIcons.arrow_right, size: 18.sp),
            label: Text(widget.saving ? 'Salvando...' : 'Salvar e próximo'),
          ),
        ],
      ),
    );
  }
}

class _PePalette {
  final bool isDark;
  _PePalette(this.isDark);

  Color get page => isDark ? const Color(0xFF0F1217) : const Color(0xFFF5F7FB);
  Color get surface => isDark ? const Color(0xFF171B22) : Colors.white;
  Color get border =>
      isDark ? const Color(0xFF2B3038) : const Color(0xFFE5EAF2);
  Color get title => isDark ? Colors.white : const Color(0xFF172033);
  Color get subtitle =>
      isDark ? const Color(0xFFA1A9B7) : const Color(0xFF687386);
  Color get muted => isDark ? const Color(0xFF7B8494) : const Color(0xFF98A2B3);
  Color get green => const Color(0xFF2DBE60);
  Color get blue => const Color(0xFF2F80ED);
  Color get orange => const Color(0xFFF2994A);
  Color get red => const Color(0xFFE05555);
  Color get purple => const Color(0xFF7A5AF8);
}

class _PeDropdown<T> extends StatelessWidget {
  final T? value;
  final List<T> items;
  final String Function(T value) label;
  final _PePalette palette;
  final ValueChanged<T?> onChanged;

  const _PeDropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.palette,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46.h,
      padding: EdgeInsets.symmetric(horizontal: 10.w),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: palette.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: items.contains(value) ? value : null,
          isExpanded: true,
          items: items
              .map((item) =>
                  DropdownMenuItem(value: item, child: Text(label(item))))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PeInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final _PePalette palette;
  final int maxLines;
  final TextInputType keyboardType;

  const _PeInput({
    required this.controller,
    required this.label,
    required this.palette,
    this.maxLines = 1,
    this.keyboardType = const TextInputType.numberWithOptions(decimal: true),
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor:
            palette.isDark ? const Color(0xFF20242C) : const Color(0xFFF8FAFD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12.r),
          borderSide: BorderSide(color: palette.border),
        ),
      ),
    );
  }
}

class _PeStatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _PeStatusChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(9.r),
      ),
      child: Text(label,
          style: GoogleFonts.inter(
              fontSize: 11.sp, fontWeight: FontWeight.w800, color: color)),
    );
  }
}

class _EmptyPeBox extends StatelessWidget {
  final _PePalette palette;
  final String title;
  final String message;

  const _EmptyPeBox({
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
          Icon(PhosphorIcons.person_simple_run,
              size: 42.sp, color: palette.muted),
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
