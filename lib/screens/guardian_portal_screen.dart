import 'dart:async';

import 'package:academyhub_mobile/model/guardian_auth_model.dart';
import 'package:academyhub_mobile/model/app_notification_model.dart';
import 'package:academyhub_mobile/model/invoice_model.dart';
import 'package:academyhub_mobile/providers/app_notification_provider.dart';
import 'package:academyhub_mobile/providers/auth_provider.dart';
import 'package:academyhub_mobile/providers/guardian_official_documents_provider.dart';
import 'package:academyhub_mobile/providers/invoice_provider.dart';
import 'package:academyhub_mobile/providers/re_enrollment_provider.dart';
import 'package:academyhub_mobile/model/re_enrollment_model.dart';
import 'package:academyhub_mobile/providers/school_provider.dart';
import 'package:academyhub_mobile/providers/theme_provider.dart';
import 'package:academyhub_mobile/screens/guardian_activities_screen.dart';
import 'package:academyhub_mobile/screens/guardian_attendance_screen.dart';
import 'package:academyhub_mobile/screens/guardian_documents_screen.dart';
import 'package:academyhub_mobile/screens/guardian_schedule_screen.dart';
import 'package:academyhub_mobile/services/guardian_auth_service.dart';
import 'package:academyhub_mobile/services/guardian_session_exception.dart';
import 'package:academyhub_mobile/services/websocket.dart';
import 'package:academyhub_mobile/widgets/app_notification_center_sheet.dart';
import 'package:academyhub_mobile/widgets/custom_bottom_menu.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_phosphor_icons/flutter_phosphor_icons.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class GuardianPortalScreen extends StatefulWidget {
  const GuardianPortalScreen({super.key});

  @override
  State<GuardianPortalScreen> createState() => _GuardianPortalScreenState();
}

class _GuardianPortalScreenState extends State<GuardianPortalScreen> {
  final GuardianAuthService _guardianAuthService = GuardianAuthService();
  final WebSocketService _webSocketService = WebSocketService();
  StreamSubscription<Map<String, dynamic>>? _socketSubscription;

  int _currentIndex = 0;
  GuardianPortalHomeData? _portalHome;
  bool _isPortalLoading = false;
  String? _portalError;
  String? _selectedStudentId;
  String? _focusedDocumentRequestId;
  String? _focusedDocumentId;
  int _documentsFocusNonce = 0;
  String? _focusedAbsenceRequestId;
  int _attendanceFocusNonce = 0;
  int _attendanceRefreshNonce = 0;
  bool _hasShownReEnrollmentSheetThisSession = false;
  bool _isSubmittingReEnrollment = false;
  _GuardianFinanceFilter _financeFilter = _GuardianFinanceFilter.priority;

  String get _currentSectionLabel {
    switch (_currentIndex) {
      case 1:
        return 'Acompanhar';
      case 2:
        return 'Financeiro';
      case 3:
        return 'Conta';
      case 4:
        return 'Documentações';
      case 5:
        return 'Frequência';
      case 0:
      default:
        return 'Início';
    }
  }

  GuardianLinkedStudent? get _selectedStudent {
    final home = _portalHome;
    if (home == null) return null;
    final selectedId = (_selectedStudentId ?? '').trim();
    if (selectedId.isEmpty) return home.selectedStudent;

    for (final student in home.linkedStudents) {
      if (student.id == selectedId) {
        return student;
      }
    }
    return home.selectedStudent;
  }

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listenToSocketEvents();
      _refreshGuardianPortal();
    });
  }

  @override
  void dispose() {
    _socketSubscription?.cancel();
    super.dispose();
  }

  void _listenToSocketEvents() {
    _socketSubscription?.cancel();
    _socketSubscription = _webSocketService.stream.listen((message) {
      if (!mounted) return;

      context.read<AppNotificationProvider>().handleRealtimeEvent(
            message,
            currentStudentId: _selectedStudent?.id,
            linkedStudentIds: _portalHome?.linkedStudents
                    .map((student) => student.id)
                    .toList() ??
                const [],
          );

      final type = message['type']?.toString().trim() ?? '';
      if (type.startsWith('absence_justification_request_')) {
        setState(() => _attendanceRefreshNonce++);
        if (_currentIndex == 5) {
          final feedback = _attendanceRealtimeFeedback(type);
          if (feedback != null) _showFeedback(feedback);
        }
      }

      final handled =
          context.read<GuardianOfficialDocumentsProvider>().handleRealtimeEvent(
                message,
                studentId: _selectedStudent?.id,
              );

      if (!handled || _currentIndex != 4) return;

      final feedback = _documentRealtimeFeedback(message['type']?.toString());
      if (feedback != null) {
        _showFeedback(feedback);
      }
    });
  }

  void _openNotificationCenter() {
    final token = context.read<AuthProvider>().token;
    if ((token ?? '').trim().isNotEmpty) {
      unawaited(
        context
            .read<AppNotificationProvider>()
            .loadPersisted(token: token!.trim()),
      );
    }

    showAppNotificationCenterSheet(
      context: context,
      onNotificationTap: _handleNotificationTap,
    );
  }

  void _handleNotificationTap(AppNotificationItem notification) {
    final token = context.read<AuthProvider>().token;
    context.read<AppNotificationProvider>().markAsRead(notification.id, token);
    Navigator.of(context).maybePop();

    if (notification.routeKey == 'guardian.documents' ||
        notification.domain == AppNotificationDomain.documents) {
      setState(() {
        _currentIndex = 4;
        _focusedDocumentRequestId =
            notification.metadata['requestId']?.toString();
        _focusedDocumentId = notification.metadata['documentId']?.toString();
        _documentsFocusNonce++;
      });
      return;
    }

    if (notification.routeKey == 'guardian.attendance' ||
        notification.domain == AppNotificationDomain.academic) {
      final studentId = notification.metadata['studentId']?.toString();
      if ((studentId ?? '').trim().isNotEmpty) {
        _selectedStudentId = studentId!.trim();
        unawaited(
          context.read<AuthProvider>().setGuardianSelectedStudentId(
                _selectedStudentId,
              ),
        );
      }
      setState(() {
        _currentIndex = 5;
        _focusedAbsenceRequestId =
            notification.metadata['requestId']?.toString();
        _attendanceFocusNonce++;
      });
    }
  }

  void _connectGuardianWebSocket() {
    final schoolId =
        context.read<AuthProvider>().guardianSession?.schoolId.trim() ?? '';
    if (schoolId.isEmpty) return;
    _webSocketService.connect(schoolId);
  }

  String? _documentRealtimeFeedback(String? type) {
    switch (type) {
      case 'official_document_request_approved':
        return 'A escola aprovou uma solicitação de documento.';
      case 'official_document_request_rejected':
        return 'A escola respondeu uma solicitação de documento.';
      case 'official_document_awaiting_signature':
        return 'Um documento está aguardando assinatura.';
      case 'official_document_signed':
        return 'Um documento foi assinado pela escola.';
      case 'official_document_published':
        return 'Documento oficial disponível para abrir ou baixar.';
      case 'official_document_downloaded':
        return 'Download registrado no protocolo.';
      default:
        return null;
    }
  }

  String? _attendanceRealtimeFeedback(String? type) {
    switch (type) {
      case 'absence_justification_request_approved':
        return 'A escola aprovou uma solicitação de abono.';
      case 'absence_justification_request_partially_approved':
        return 'A escola aprovou parte do período solicitado.';
      case 'absence_justification_request_rejected':
        return 'A escola respondeu uma solicitação de abono.';
      case 'absence_justification_request_needs_information':
        return 'A escola solicitou complemento para um abono.';
      case 'absence_justification_request_applied':
        return 'Um abono aprovado foi aplicado em uma falta registrada.';
      default:
        return null;
    }
  }

  Future<void> _expireGuardianSession([Object? error]) async {
    if (!mounted) return;
    await context.read<AuthProvider>().expireGuardianSession(
          context,
          reason: error?.toString(),
        );
  }

  Future<void> _refreshGuardianPortal() async {
    try {
      final auth = context.read<AuthProvider>();
      final notificationProvider = context.read<AppNotificationProvider>();
      final reEnrollmentProvider = context.read<ReEnrollmentProvider>();
      final token = auth.token;
      final preferredStudentId = (_selectedStudentId ??
              auth.guardianSelectedStudentId ??
              auth.guardianSession?.defaultStudent?.id)
          ?.trim();

      await _loadGuardianPortalData(studentId: preferredStudentId);
      if (!mounted || !context.read<AuthProvider>().isGuardian) return;

      if ((token ?? '').trim().isNotEmpty) {
        await notificationProvider.loadPersisted(token: token!.trim());
      }
      await _loadGuardianInvoices(studentId: _selectedStudentId);
      await _loadGuardianDocuments(studentId: _selectedStudentId);
      if ((token ?? '').trim().isNotEmpty) {
        await reEnrollmentProvider.load(token!.trim());
        _showReEnrollmentSheetOnce();
      }
    } on GuardianSessionExpiredException catch (error) {
      await _expireGuardianSession(error);
    }
  }

  Future<void> _loadGuardianPortalData({String? studentId}) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;

    final hasGuardianToken = (token ?? '').trim().isNotEmpty;
    if (!hasGuardianToken) {
      await _expireGuardianSession(
        const GuardianSessionExpiredException(
          message: 'Sessao do responsavel ausente.',
          code: 'guardian_token_missing',
        ),
      );
      return;
    }

    if (mounted) {
      setState(() {
        _isPortalLoading = true;
        _portalError = null;
      });
    }

    try {
      final result = await _guardianAuthService.getGuardianPortalHome(
        token: token!.trim(),
        studentId: studentId,
      );
      final preferredStudentId =
          (studentId ?? auth.guardianSelectedStudentId ?? '').trim();
      final resolvedStudentId = result.linkedStudents.any(
        (student) => student.id == preferredStudentId,
      )
          ? preferredStudentId
          : (result.selectedStudent?.id ??
              (result.linkedStudents.isNotEmpty
                  ? result.linkedStudents.first.id
                  : null));

      if (!mounted) return;
      setState(() {
        _portalHome = result;
        _selectedStudentId = resolvedStudentId;
        _isPortalLoading = false;
      });

      await auth.setGuardianSelectedStudentId(resolvedStudentId);
      _connectGuardianWebSocket();
    } on GuardianSessionExpiredException {
      rethrow;
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _portalError = e.toString().replaceFirst('Exception: ', '');
        _isPortalLoading = false;
      });
    }
  }

  void _showReEnrollmentSheetOnce() {
    if (_hasShownReEnrollmentSheetThisSession || !mounted) return;
    final items = context.read<ReEnrollmentProvider>().eligibility?.items ??
        const <GuardianReEnrollmentItem>[];
    if (!items.any((item) => item.canRequest || item.financialBlocked)) return;
    _hasShownReEnrollmentSheetThisSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openReEnrollmentSheet();
    });
  }

  Widget _buildReEnrollmentCard() {
    return Consumer<ReEnrollmentProvider>(builder: (context, provider, _) {
      final items =
          provider.eligibility?.items ?? const <GuardianReEnrollmentItem>[];
      final visible = items
          .where((item) =>
              !item.progressionMissing ||
              item.canRequest ||
              item.financialBlocked)
          .toList();
      if (visible.isEmpty) return const SizedBox.shrink();
      if (visible.isEmpty) return const SizedBox.shrink();
      final year = provider.eligibility?.academicYearTo ??
          visible.first.targetAcademicYear;
      final blocked = visible.where((item) => item.financialBlocked).length;
      return InkWell(
        onTap: _openReEnrollmentSheet,
        borderRadius: BorderRadius.circular(20.r),
        child: Ink(
          padding: EdgeInsets.all(18.w),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20.r),
            gradient: const LinearGradient(
                colors: [Color(0xFF00A859), Color(0xFF007A40)]),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF00A859).withOpacity(.20),
                  blurRadius: 18,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Row(children: [
            Container(
                padding: EdgeInsets.all(11.w),
                decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.18),
                    shape: BoxShape.circle),
                child: Icon(PhosphorIcons.graduation_cap_fill,
                    color: Colors.white, size: 25.sp)),
            SizedBox(width: 13.w),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('REMATRÍCULAS $year',
                      style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.sp)),
                  SizedBox(height: 4.h),
                  Text(
                      blocked > 0
                          ? 'Há uma pendência a regularizar antes de solicitar.'
                          : 'Garanta a vaga do seu aluno para o próximo ano letivo.',
                      style: GoogleFonts.inter(
                          color: Colors.white.withOpacity(.92),
                          fontSize: 12.sp,
                          height: 1.3)),
                ])),
            Icon(PhosphorIcons.caret_right_bold,
                color: Colors.white, size: 18.sp),
          ]),
        ),
      );
    });
  }

  Future<void> _openReEnrollmentSheet() async {
    final provider = context.read<ReEnrollmentProvider>();
    final items =
        provider.eligibility?.items ?? const <GuardianReEnrollmentItem>[];
    if (items.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => SafeArea(
          child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * .84),
        decoration: BoxDecoration(
            color: Theme.of(sheetContext).scaffoldBackgroundColor,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28.r))),
        padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 24.h),
        child: Column(children: [
          Container(
              width: 42.w,
              height: 4.h,
              decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(4.r))),
          SizedBox(height: 18.h),
          Text('Rematrículas ${provider.eligibility?.academicYearTo ?? ''}',
              style: GoogleFonts.inter(
                  fontSize: 21.sp, fontWeight: FontWeight.w800)),
          SizedBox(height: 5.h),
          Text('O próximo ciclo está chegando!',
              style: GoogleFonts.inter(
                  color: _guardianTextSecondary(sheetContext),
                  fontSize: 13.sp)),
          SizedBox(height: 16.h),
          Expanded(
              child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => SizedBox(height: 10.h),
                  itemBuilder: (_, index) =>
                      _buildReEnrollmentItem(sheetContext, items[index]))),
        ]),
      )),
    );
  }

  Widget _buildReEnrollmentItem(
      BuildContext sheetContext, GuardianReEnrollmentItem item) {
    final isBlocked = item.financialBlocked;
    final alreadyRequested = item.eligibility == 'ALREADY_REQUESTED';
    final approved = item.eligibility == 'APPROVED';
    final rejected = item.eligibility == 'REJECTED';
    final color = isBlocked
        ? const Color(0xFFD97706)
        : approved
            ? const Color(0xFF00A859)
            : (alreadyRequested || rejected)
                ? const Color(0xFF2F80ED)
                : const Color(0xFF00A859);
    final status = isBlocked
        ? 'Rematrícula temporariamente indisponível'
        : approved
            ? (item.enrollmentEffectivated
                ? 'Matrícula confirmada'
                : 'Rematrícula aprovada')
            : rejected
                ? 'Solicitação não aprovada'
                : alreadyRequested
                    ? 'Em análise'
                    : item.canRequest
                        ? 'Apta para rematrícula'
                        : 'Estamos preparando a próxima etapa escolar';
    return Container(
        padding: EdgeInsets.all(15.w),
        decoration: BoxDecoration(
            color: Theme.of(sheetContext).cardColor,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: color.withOpacity(.25))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(item.studentName,
              style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800, fontSize: 15.sp)),
          SizedBox(height: 10.h),
          Row(children: [
            Expanded(
                child: _reEnrollmentStage('ATUAL',
                    '${item.currentClass?.name ?? '—'}\n${item.currentClass?.grade ?? ''}')),
            Icon(PhosphorIcons.arrow_right_bold, color: color, size: 18.sp),
            Expanded(
                child: _reEnrollmentStage('PRÓXIMO ANO',
                    '${item.targetLabel.isEmpty ? 'Série a definir' : item.targetLabel}\n${item.targetAcademicYear}'))
          ]),
          SizedBox(height: 12.h),
          if (item.targetLevel.isNotEmpty || item.targetShift.isNotEmpty)
            Text(
                '${item.targetLevel}${item.targetShift.isNotEmpty ? ' • ${item.targetShift}' : ''}',
                style: GoogleFonts.inter(
                    color: _guardianTextSecondary(sheetContext),
                    fontSize: 11.sp)),
          if (item.formattedMonthlyFee.isNotEmpty) ...[
            SizedBox(height: 8.h),
            Text(
                'Mensalidade ${item.targetAcademicYear}: ${item.formattedMonthlyFee}',
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w800, fontSize: 13.sp)),
          ],
          Text(status,
              style: GoogleFonts.inter(
                  color: color, fontWeight: FontWeight.w700, fontSize: 12.sp)),
          if (isBlocked)
            Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                    'Existe uma pendência financeira que precisa ser regularizada antes de solicitar a rematrícula.',
                    style: GoogleFonts.inter(fontSize: 12.sp, height: 1.35))),
          if (approved)
            Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                    item.enrollmentEffectivated && item.targetClass != null
                        ? '${item.studentName} está matriculada para ${item.targetAcademicYear}.\nTurma: ${item.targetClass!.name}'
                        : 'A escola aprovou a rematrícula para ${item.targetAcademicYear}.\nTurma será definida pela escola.',
                    style: GoogleFonts.inter(fontSize: 12.sp))),
          if (rejected)
            Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                    item.rejectionReason.isNotEmpty
                        ? 'Motivo: ${item.rejectionReason}'
                        : 'Entre em contato com a escola para mais informações.',
                    style: GoogleFonts.inter(fontSize: 12.sp))),
          if (item.progressionMissing)
            Padding(
                padding: EdgeInsets.only(top: 6.h),
                child: Text(
                    'Estamos preparando as informações da próxima etapa escolar de ${item.studentName}. Entre em contato com a escola caso precise de mais informações.',
                    style: GoogleFonts.inter(fontSize: 12.sp, height: 1.35))),
          if (item.canRequest) ...[
            SizedBox(height: 12.h),
            SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                    onPressed: _isSubmittingReEnrollment
                        ? null
                        : () => _confirmReEnrollment(sheetContext, item),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: color,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r))),
                    child: Text(_isSubmittingReEnrollment
                        ? 'Enviando...'
                        : 'Garantir vaga')))
          ],
        ]));
  }

  Widget _reEnrollmentStage(String label, String value) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 9.sp,
                fontWeight: FontWeight.w800,
                color: _guardianTextSecondary(context))),
        SizedBox(height: 3.h),
        Text(value,
            style:
                GoogleFonts.inter(fontSize: 12.sp, fontWeight: FontWeight.w700),
            maxLines: 2,
            overflow: TextOverflow.ellipsis)
      ]);

  Future<void> _confirmReEnrollment(
      BuildContext sheetContext, GuardianReEnrollmentItem item) async {
    final shouldSubmit = await showDialog<bool>(
        context: sheetContext,
        builder: (dialogContext) => AlertDialog(
                title: const Text('Confirmar rematrícula'),
                content: Text(
                    'Você está solicitando a continuidade de ${item.studentName} para o ano letivo de ${item.targetAcademicYear}.\n\nAtual: ${item.currentClass?.name ?? '—'}\nPróxima etapa: ${item.targetLabel}${item.formattedMonthlyFee.isEmpty ? '' : '\nMensalidade: ${item.formattedMonthlyFee}'}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      child: const Text('Voltar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      child: const Text('Confirmar solicitação'))
                ]));
    if (shouldSubmit != true || !mounted) return;
    try {
      setState(() => _isSubmittingReEnrollment = true);
      final token = context.read<AuthProvider>().token;
      if ((token ?? '').isEmpty) return;
      await context
          .read<ReEnrollmentProvider>()
          .request(token: token!, studentId: item.studentId);
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Solicitação enviada! A escola será avisada.'),
          behavior: SnackBarBehavior.floating));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', '')),
            behavior: SnackBarBehavior.floating));
    } finally {
      if (mounted) setState(() => _isSubmittingReEnrollment = false);
    }
  }

  Future<void> _loadGuardianInvoices({String? studentId}) async {
    final auth = context.read<AuthProvider>();
    final invoices = context.read<InvoiceProvider>();

    final hasGuardianToken = (auth.token ?? '').trim().isNotEmpty;
    if (!hasGuardianToken) {
      await _expireGuardianSession(
        const GuardianSessionExpiredException(
          message: 'Sessao do responsavel ausente.',
          code: 'guardian_token_missing',
        ),
      );
      return;
    }

    try {
      await invoices.fetchGuardianInvoices(
        token: auth.token!,
        studentId: studentId,
      );
    } on GuardianSessionExpiredException catch (error) {
      await _expireGuardianSession(error);
    }
  }

  Future<void> _loadGuardianDocuments({String? studentId}) async {
    final auth = context.read<AuthProvider>();
    final documents = context.read<GuardianOfficialDocumentsProvider>();
    final normalizedStudentId =
        (studentId ?? _selectedStudent?.id ?? '').trim();

    final hasGuardianToken = (auth.token ?? '').trim().isNotEmpty;
    if (!hasGuardianToken) {
      documents.clear();
      await _expireGuardianSession(
        const GuardianSessionExpiredException(
          message: 'Sessao do responsavel ausente.',
          code: 'guardian_token_missing',
        ),
      );
      return;
    }

    if (normalizedStudentId.isEmpty) {
      documents.clear();
      return;
    }

    try {
      await documents.load(
        token: auth.token!,
        studentId: normalizedStudentId,
        silent: true,
      );
    } on GuardianSessionExpiredException catch (error) {
      await _expireGuardianSession(error);
    }
  }

  void _onTabTapped(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _copyInvoiceCode(Invoice invoice) async {
    final code = _resolveInvoiceCode(invoice);
    if (code == null || code.isEmpty) {
      _showFeedback('Este boleto não possui código disponível para cópia.');
      return;
    }

    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    _showFeedback('Código do boleto copiado com sucesso.');
  }

  Future<void> _openInvoiceBoleto(Invoice invoice) async {
    final auth = context.read<AuthProvider>();
    final invoices = context.read<InvoiceProvider>();

    try {
      if ((invoice.boletoUrl ?? '').trim().isNotEmpty) {
        final opened = await launchUrl(
          Uri.parse(invoice.boletoUrl!.trim()),
          mode: LaunchMode.externalApplication,
        );

        if (!opened && mounted) {
          _showFeedback('Não foi possível abrir o boleto.');
        }
        return;
      }

      final hasGuardianToken = (auth.token ?? '').trim().isNotEmpty;
      if (!hasGuardianToken) {
        await _expireGuardianSession(
          const GuardianSessionExpiredException(
            message: 'Sessao do responsavel ausente.',
            code: 'guardian_token_missing',
          ),
        );
        return;
      }

      await invoices.generateGuardianBatchPdf(
        invoiceIds: [invoice.id],
        token: auth.token!,
        studentId: _selectedStudent?.id,
      );

      if (!mounted) return;
      if (invoices.error != null) {
        _showFeedback(invoices.error!);
      }
    } on GuardianSessionExpiredException catch (error) {
      await _expireGuardianSession(error);
    } catch (_) {
      if (!mounted) return;
      _showFeedback('Não foi possível abrir ou baixar o boleto.');
    }
  }

  Future<void> _openScheduleScreen() async {
    final student = _selectedStudent;
    if (student == null) {
      _showFeedback('Nenhum aluno vinculado foi encontrado neste acesso.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuardianScheduleScreen(student: student),
      ),
    );
  }

  Future<void> _openAttendanceScreen() async {
    final student = _selectedStudent;
    if (student == null) {
      _showFeedback('Nenhum aluno vinculado foi encontrado neste acesso.');
      return;
    }

    setState(() => _currentIndex = 5);
  }

  Future<void> _openActivitiesScreen() async {
    final student = _selectedStudent;
    if (student == null) {
      _showFeedback('Nenhum aluno vinculado foi encontrado neste acesso.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => GuardianActivitiesScreen(student: student),
      ),
    );
  }

  Future<void> _showStudentPicker() async {
    final students =
        _portalHome?.linkedStudents ?? const <GuardianLinkedStudent>[];
    if (students.length < 2) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _guardianSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (context) {
        final primaryText = _guardianTextPrimary(context);
        final secondaryText = _guardianTextSecondary(context);

        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 14.h, 20.w, 20.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: _guardianBorder(context),
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                  ),
                ),
                SizedBox(height: 14.h),
                Text(
                  'Trocar aluno',
                  style: GoogleFonts.inter(
                    color: primaryText,
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 6.h),
                Text(
                  'Escolha quem você quer acompanhar agora.',
                  style: GoogleFonts.inter(
                    fontSize: 11.5.sp,
                    fontWeight: FontWeight.w500,
                    color: secondaryText,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 12.h),
                ...students.map(
                  (student) => Padding(
                    padding: EdgeInsets.only(bottom: 10.h),
                    child: _GuardianStudentOptionTile(
                      student: student,
                      selected: student.id == _selectedStudent?.id,
                      onTap: () async {
                        Navigator.of(context).pop();
                        setState(() => _selectedStudentId = student.id);
                        await context
                            .read<AuthProvider>()
                            .setGuardianSelectedStudentId(student.id);
                        await _loadGuardianPortalData(studentId: student.id);
                        await _loadGuardianInvoices(studentId: student.id);
                        await _loadGuardianDocuments(studentId: student.id);
                        if (mounted) {
                          setState(() => _attendanceRefreshNonce++);
                        }
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _showPinSecurityInfo() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _guardianSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.w, 18.h, 24.w, 28.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: _guardianBorder(context),
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                Text(
                  'Segurança em preparação',
                  style: GoogleFonts.inter(
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                    color: _guardianTextPrimary(context),
                  ),
                ),
                SizedBox(height: 10.h),
                Text(
                  'A alteração de PIN por e-mail ainda depende de um fluxo seguro no backend para envio e validação do código.',
                  style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w500,
                    color: _guardianTextSecondary(context),
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 12.h),
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(16.r),
                  decoration: BoxDecoration(
                    color: _guardianSoftSurface(context),
                    borderRadius: BorderRadius.circular(18.r),
                    border: Border.all(color: _guardianBorder(context)),
                  ),
                  child: Text(
                    'Assim que esse backend estiver pronto, esta área poderá enviar um código para o e-mail verificado do responsável e permitir a definição de um novo PIN.',
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: _guardianTextSecondary(context),
                      height: 1.5,
                    ),
                  ),
                ),
                SizedBox(height: 18.h),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: const Color(0xFF00A859),
                      foregroundColor: Colors.white,
                      minimumSize: Size.fromHeight(46.h),
                    ),
                    child: const Text('Entendi'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ignore: unused_element
  PreferredSizeWidget _buildLegacyAppBar(GuardianSession? session) {
    /*
      if ((student?.classInfo?.name ?? '').trim().isNotEmpty)
        student!.classInfo!.name,
      if ((student?.classInfo?.shift ?? '').trim().isNotEmpty)
        student!.classInfo!.shift,
      if ((student?.relationship ?? '').trim().isNotEmpty)
        student!.relationship,
    ].join(' · ');
    final subtitle = studentContext.isNotEmpty
        ? studentContext
        : (schoolName.isNotEmpty ? schoolName : 'Academy Hub');
    */
    final isDark = _isDarkContext(context);

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 66.h,
      automaticallyImplyLeading: false,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: _guardianAppBarBackground(context),
          border: Border(
            bottom: BorderSide(color: _guardianBorder(context)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 6.h, 20.w, 8.h),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Portal do responsável',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.sp,
                        fontWeight: FontWeight.w700,
                        color: _guardianTextSecondary(context),
                      ),
                    ),
                    SizedBox(height: 2.h),
                    Text(
                      _currentSectionLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _guardianTextPrimary(context),
                        fontSize: 18.sp,
                        fontFamily: 'GR Milesons Three',
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(GuardianSession? session) {
    final isDark = _isDarkContext(context);

    return AppBar(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      toolbarHeight: 54.h,
      automaticallyImplyLeading: false,
      systemOverlayStyle:
          isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      flexibleSpace: Container(
        decoration: BoxDecoration(
          color: _guardianAppBarBackground(context),
          border: Border(
            bottom: BorderSide(color: _guardianBorder(context)),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20.w, 3.h, 20.w, 4.h),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Responsável',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w700,
                          color: _guardianTextSecondary(context),
                        ),
                      ),
                      SizedBox(height: 1.h),
                      Text(
                        _currentSectionLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: _guardianTextPrimary(context),
                          fontSize: 16.5.sp,
                          fontFamily: 'GR Milesons Three',
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 12.w),
                Consumer<AppNotificationProvider>(
                  builder: (context, provider, _) {
                    return _NotificationBellButton(
                      unreadCount: provider.unreadCount,
                      onTap: _openNotificationCenter,
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHomeTab(
    GuardianSession? session,
    InvoiceProvider invoiceProvider,
  ) {
    final invoiceGroups = _invoiceGroups(invoiceProvider.guardianInvoices);
    final home = _portalHome;
    final selectedStudent = _selectedStudent;

    return RefreshIndicator(
      color: const Color(0xFF00A859),
      onRefresh: _refreshGuardianPortal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20.w, 84.h, 20.w, 128.h),
        children: [
          _buildHeaderBlock(
            title: 'Resumo do dia',
            subtitle: selectedStudent == null
                ? 'Veja rapidamente aula, frequência, atividades e o financeiro do aluno.'
                : 'Acompanhe os principais sinais do dia de ${selectedStudent.firstName} em poucos toques.',
          ),
          SizedBox(height: 14.h),
          if (selectedStudent == null && _isPortalLoading)
            const _GuardianLoadingCard(
              label: 'Carregando o contexto do aluno...',
            )
          else if (selectedStudent == null)
            const _EmptyStateCard(
              title: 'Nenhum aluno disponível',
              message:
                  'Quando houver um vínculo acadêmico ativo para este acesso, ele aparecerá aqui.',
            ),
          SizedBox(height: 14.h),
          if (_portalError != null && home == null)
            _ErrorCard(
              message: _portalError!,
              onRetry: _refreshGuardianPortal,
            )
          else if (_isPortalLoading && home == null)
            Column(
              children: [
                const _GuardianLoadingCard(
                  label: 'Atualizando aula atual e resumos acadêmicos...',
                ),
                SizedBox(height: 12.h),
                Row(
                  children: [
                    const Expanded(
                      child: _GuardianLoadingCard(label: 'Frequência'),
                    ),
                    SizedBox(width: 10.w),
                    const Expanded(
                      child: _GuardianLoadingCard(label: 'Atividades'),
                    ),
                  ],
                ),
              ],
            )
          else ...[
            _GuardianLessonSummaryCard(
              schedule: home?.schedule,
              onOpenSchedule: _openScheduleScreen,
            ),
            SizedBox(height: 10.h),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _GuardianHomeSummaryCard(
                    title: 'Frequência',
                    accentColor: _attendanceAccent(
                      home?.attendance.summary.attentionLevel,
                    ),
                    icon: PhosphorIcons.check_circle_fill,
                    headline:
                        '${home?.attendance.summary.presenceRate.toStringAsFixed(0) ?? '0'}%',
                    subtitle: _buildAttendanceHomeSubtitle(
                      home?.attendance.summary,
                    ),
                    actionLabel: 'Ver detalhes',
                    onTap: _openAttendanceScreen,
                  ),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: _GuardianHomeSummaryCard(
                    title: 'Atividades',
                    accentColor: const Color(0xFF2F80ED),
                    icon: PhosphorIcons.notepad_fill,
                    headline: _buildActivitiesHomeHeadline(
                      home?.activitiesSummary,
                    ),
                    subtitle: _buildActivitiesHomeSubtitle(
                      home?.activitiesSummary,
                    ),
                    actionLabel: 'Ver atividades',
                    onTap: _openActivitiesScreen,
                  ),
                ),
              ],
            ),
          ],
          SizedBox(height: 14.h),
          _buildReEnrollmentCard(),
          SizedBox(height: 14.h),
          _buildSectionLabel('Resumo do portal'),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(
                child: _PortalShortcutCard(
                  title: 'Acompanhar',
                  subtitle: 'Grade, frequência e atividades',
                  icon: PhosphorIcons.book_open_fill,
                  color: const Color(0xFF2F80ED),
                  onTap: () => _onTabTapped(1),
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: _PortalShortcutCard(
                  title: 'Financeiro',
                  subtitle: 'Boleto do mês e histórico',
                  icon: PhosphorIcons.money_fill,
                  color: const Color(0xFF00A859),
                  onTap: () => _onTabTapped(2),
                ),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          _PortalShortcutCard(
            title: 'Documentações',
            subtitle: 'Solicitações, andamento e PDFs oficiais assinados',
            icon: PhosphorIcons.files_fill,
            color: const Color(0xFF2F80ED),
            onTap: () => _onTabTapped(4),
          ),
          SizedBox(height: 14.h),
          _buildSectionLabel('Financeiro em destaque'),
          SizedBox(height: 10.h),
          if (invoiceProvider.error != null &&
              invoiceProvider.error!.trim().isNotEmpty)
            _ErrorCard(
              message: invoiceProvider.error!,
              onRetry: _loadGuardianInvoices,
            )
          else if (invoiceGroups.featured != null)
            _PortalFinanceSpotlight(
              invoice: invoiceGroups.featured!,
              onOpenFinance: () => _onTabTapped(2),
              onCopyCode: () => _copyInvoiceCode(invoiceGroups.featured!),
              onOpenBoleto: () => _openInvoiceBoleto(invoiceGroups.featured!),
            )
          else
            const _EmptyStateCard(
              title: 'Nenhuma cobrança urgente',
              message:
                  'Quando houver um boleto vencido ou o próximo vencimento, ele aparecerá aqui.',
            ),
          SizedBox(height: 18.h),
          Row(
            children: [
              Expanded(
                child: _MetricCard(
                  label: 'Pendentes',
                  count: invoiceGroups.pending.length,
                  color: const Color(0xFFF59E0B),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _MetricCard(
                  label: 'Em atraso',
                  count: invoiceGroups.overdue.length,
                  color: const Color(0xFFEF4444),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _MetricCard(
                  label: 'Pagos',
                  count: invoiceGroups.paid.length,
                  color: const Color(0xFF00A859),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrackingTab() {
    final home = _portalHome;
    final selectedStudent = _selectedStudent;

    return RefreshIndicator(
      color: const Color(0xFF00A859),
      onRefresh: _refreshGuardianPortal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20.w, 84.h, 20.w, 128.h),
        children: [
          _buildHeaderBlock(
            title: 'Acompanhar',
            subtitle: selectedStudent == null
                ? 'Entre nas áreas acadêmicas com uma visão clara do que está acontecendo agora.'
                : 'Abra grade, frequência e atividades de ${selectedStudent.firstName} sem perder o contexto atual.',
          ),
          SizedBox(height: 18.h),
          if (selectedStudent == null && _isPortalLoading)
            const _GuardianLoadingCard(
              label: 'Carregando dados de acompanhamento...',
            )
          else if (selectedStudent == null)
            const _EmptyStateCard(
              title: 'Sem contexto acadêmico',
              message:
                  'Assim que houver um aluno vinculado a este acesso, o acompanhamento ficará disponível aqui.',
            ),
          SizedBox(height: 18.h),
          if (_portalError != null && home == null)
            _ErrorCard(
              message: _portalError!,
              onRetry: _refreshGuardianPortal,
            )
          else ...[
            _GuardianHubCard(
              title: 'Grade e horários',
              icon: PhosphorIcons.clock_fill,
              accent: const Color(0xFF2F80ED),
              description: _buildScheduleHubDescription(home?.schedule),
              footnote: 'Veja aula atual, próxima aula e a semana completa.',
              onTap: _openScheduleScreen,
            ),
            SizedBox(height: 12.h),
            _GuardianHubCard(
              title: 'Frequência',
              icon: PhosphorIcons.check_circle_fill,
              accent:
                  _attendanceAccent(home?.attendance.summary.attentionLevel),
              description: _buildAttendanceHomeSubtitle(
                home?.attendance.summary,
              ),
              footnote:
                  'Consulte o percentual de presença e os registros recentes.',
              onTap: _openAttendanceScreen,
            ),
            SizedBox(height: 12.h),
            _GuardianHubCard(
              title: 'Atividades',
              icon: PhosphorIcons.notepad_fill,
              accent: const Color(0xFF7C3AED),
              description: _buildActivitiesHubDescription(
                home?.activitiesSummary,
              ),
              footnote: 'Acompanhe entregas, pendências e atividades recentes.',
              onTap: _openActivitiesScreen,
            ),
            SizedBox(height: 12.h),
            _GuardianHubCard(
              title: 'Documentações',
              icon: PhosphorIcons.files_fill,
              accent: const Color(0xFF2F80ED),
              description:
                  'Solicite declarações, acompanhe a análise da secretaria e acesse PDFs oficiais assinados.',
              footnote:
                  'Veja o andamento em etapas claras e baixe quando estiver publicado.',
              onTap: () => _onTabTapped(4),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFinanceTab(
    GuardianSession? session,
    InvoiceProvider invoiceProvider,
  ) {
    final invoiceGroups = _invoiceGroups(invoiceProvider.guardianInvoices);
    final scoreContext = invoiceProvider.guardianFinancialScoreContext;
    final availableScoreContext =
        scoreContext != null && scoreContext.hasScore ? scoreContext : null;
    final selectedInvoices = _financeInvoicesForFilter(invoiceGroups);
    final selectedTitle = _financeFilterTitle(_financeFilter);

    return RefreshIndicator(
      color: const Color(0xFF00A859),
      onRefresh: _refreshGuardianPortal,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20.w, 84.h, 20.w, 128.h),
        children: [
          _buildHeaderBlock(
            title: 'Financeiro',
            subtitle:
                'Veja o que precisa de atenção agora, acompanhe seu score financeiro e encontre boletos por status sem procurar na rolagem.',
          ),
          SizedBox(height: 18.h),
          if (invoiceProvider.error != null &&
              invoiceProvider.error!.trim().isNotEmpty)
            _ErrorCard(
              message: invoiceProvider.error!,
              onRetry: _loadGuardianInvoices,
            )
          else if (invoiceGroups.featured == null && !invoiceProvider.isLoading)
            _EmptyStateCard(
              title: 'Tudo em dia',
              message: (session?.linkedStudentsCount ?? 0) > 0
                  ? 'Não encontramos boletos pendentes para esta conta neste momento.'
                  : 'Assim que existirem cobranças vinculadas a este acesso, elas aparecerão aqui.',
            )
          else if (invoiceGroups.featured != null)
            _buildFeaturedCard(invoiceGroups.featured!),
          if (availableScoreContext != null) ...[
            SizedBox(height: 14.h),
            _GuardianFinancialScoreCard(
              scoreContext: availableScoreContext,
              onDetails: () =>
                  _showFinancialScoreDetails(availableScoreContext),
            ),
          ],
          SizedBox(height: 18.h),
          _buildFinanceFilterBar(invoiceGroups),
          SizedBox(height: 16.h),
          _buildInvoiceSection(
            selectedTitle,
            selectedInvoices,
            showPaidAccent: _financeFilter == _GuardianFinanceFilter.paid,
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceTab() {
    final student = _selectedStudent;

    if (student == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(20.w, 84.h, 20.w, 128.h),
        children: const [
          _EmptyStateCard(
            title: 'Sem aluno selecionado',
            message:
                'Assim que houver um aluno vinculado a este acesso, a frequência ficará disponível aqui.',
          ),
        ],
      );
    }

    return GuardianAttendanceScreen(
      student: student,
      embedded: true,
      bottomPadding: 128,
      focusRequestId: _focusedAbsenceRequestId,
      focusNonce: _attendanceFocusNonce,
      realtimeRefreshNonce: _attendanceRefreshNonce,
    );
  }

  Widget _buildAccountTab(AuthProvider auth, GuardianSession? session) {
    final themeProvider = context.watch<ThemeProvider>();
    final schoolProvider = context.watch<SchoolProvider>();
    final providerSchool = schoolProvider.currentSchool;
    final sessionSchoolName = (session?.schoolName ?? '').trim();
    final resolvedSchoolName = sessionSchoolName.isNotEmpty
        ? sessionSchoolName
        : ((providerSchool?.name ?? '').trim().isNotEmpty
            ? providerSchool!.name
            : 'Academy Hub');
    final providerMatchesSession = providerSchool != null &&
        ((session?.schoolPublicId ?? '').trim().isNotEmpty
            ? providerSchool.publicIdentifier == session!.schoolPublicId
            : providerSchool.name.trim().toLowerCase() ==
                resolvedSchoolName.toLowerCase());
    final schoolLogoBytes =
        providerMatchesSession ? providerSchool.logoBytes : null;
    final currentStudent = _selectedStudent;
    final linkedStudentsCount = session?.linkedStudentsCount ?? 0;
    final currentStudentLabel = currentStudent == null
        ? 'Nenhum aluno selecionado'
        : [
            currentStudent.fullName,
            if ((currentStudent.classInfo?.name ?? '').trim().isNotEmpty)
              currentStudent.classInfo!.name,
          ].join(' · ');

    return ListView(
      padding: EdgeInsets.fromLTRB(20.w, 84.h, 20.w, 128.h),
      children: [
        _buildHeaderBlock(
          title: 'Conta e preferências',
          subtitle:
              'Ajuste aparência, segurança e sessão do seu acesso sem mexer no contexto acadêmico do portal.',
        ),
        SizedBox(height: 18.h),
        _GuardianAccountContextCard(
          schoolName: resolvedSchoolName,
          schoolLogoBytes: schoolLogoBytes,
          currentStudent: currentStudent,
          linkedStudentsCount: linkedStudentsCount,
        ),
        SizedBox(height: 14.h),
        _SettingsSectionCard(
          title: 'Contexto atual',
          subtitle:
              'Troque o aluno acompanhado sem sair do portal quando precisar.',
          child: Column(
            children: [
              _SettingsActionRow(
                icon: PhosphorIcons.student_fill,
                title: linkedStudentsCount > 1 ? 'Trocar aluno' : 'Aluno atual',
                subtitle: currentStudentLabel,
                badgeLabel: linkedStudentsCount > 1 ? 'Alternar' : null,
                onTap: linkedStudentsCount > 1 ? _showStudentPicker : null,
              ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        _SettingsSectionCard(
          title: 'Conta',
          child: Column(
            children: [
              _SettingsInfoRow(
                icon: PhosphorIcons.identification_card_fill,
                label: 'Identificador',
                value: session?.identifierMasked ?? '--',
              ),
              _SettingsInfoRow(
                icon: PhosphorIcons.users_three_fill,
                label: 'Alunos vinculados',
                value: '$linkedStudentsCount',
              ),
              const _SettingsInfoRow(
                icon: PhosphorIcons.envelope_simple_fill,
                label: 'E-mail para recuperação',
                value:
                    'Disponível quando o backend validar o endereço do responsável.',
                helper:
                    'Ainda não há um fluxo seguro publicado para envio de código por e-mail.',
              ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        _SettingsSectionCard(
          title: 'Aparência',
          subtitle:
              'Use o mesmo sistema de tema já disponível no restante do app.',
          child: _ThemeModeSelector(
            themeMode: themeProvider.themeMode,
            onThemeModeSelected: themeProvider.setThemeMode,
          ),
        ),
        SizedBox(height: 14.h),
        _SettingsSectionCard(
          title: 'Segurança',
          child: Column(
            children: [
              _SettingsInfoRow(
                icon: PhosphorIcons.shield_check_fill,
                label: 'Status do acesso',
                value: _buildAccessStatusLabel(session?.status ?? 'active'),
              ),
              _SettingsActionRow(
                icon: PhosphorIcons.password_fill,
                title: 'Alterar PIN',
                subtitle:
                    'Este fluxo vai usar código por e-mail assim que o backend publicar a validação segura.',
                badgeLabel: 'Em breve',
                onTap: _showPinSecurityInfo,
              ),
            ],
          ),
        ),
        SizedBox(height: 14.h),
        _SettingsSectionCard(
          title: 'Sessão',
          child: Column(
            children: [
              SizedBox(height: 2.h),
              SizedBox(
                height: 48.h,
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => auth.logout(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1B1F24),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16.r),
                    ),
                  ),
                  child: Text(
                    'Encerrar sessão',
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHeaderBlock({
    required String title,
    required String subtitle,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: _guardianTextPrimary(context),
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 3.h),
        Text(
          subtitle,
          style: GoogleFonts.inter(
            fontSize: 11.5.sp,
            fontWeight: FontWeight.w500,
            color: _guardianTextSecondary(context),
            height: 1.35,
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: GoogleFonts.inter(
        fontSize: 15.sp,
        fontWeight: FontWeight.w700,
        color: _guardianTextPrimary(context),
      ),
    );
  }

  void _showInvoiceDetails(Invoice invoice) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _guardianSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 28.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: _guardianBorder(context),
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                  ),
                ),
                SizedBox(height: 22.h),
                Text(
                  'Detalhes do boleto',
                  style: GoogleFonts.inter(
                    color: _guardianTextPrimary(context),
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 12.h),
                _InfoCard(label: 'Descrição', value: invoice.description),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Referência',
                  value: _buildReferenceLabel(invoice),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Valor',
                  value: _formatCurrency(invoice.value),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Vencimento',
                  value: _buildDate(invoice.dueDate),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Status',
                  value: _buildStatusLabel(_resolveInvoiceState(invoice)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFinancialScoreDetails(GuardianFinancialScoreContext scoreContext) {
    final score = scoreContext.score;
    if (score == null) return;

    final summary = score.summary;
    final ownerName = (scoreContext.owner?.fullName ?? '').trim().isNotEmpty
        ? scoreContext.owner!.fullName
        : 'Responsável autenticado';
    final relationship = scoreContext.owner?.relationship;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _guardianSurface(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.r)),
      ),
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24.w, 16.h, 24.w, 28.h),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 48.w,
                    height: 5.h,
                    decoration: BoxDecoration(
                      color: _guardianBorder(context),
                      borderRadius: BorderRadius.circular(999.r),
                    ),
                  ),
                ),
                SizedBox(height: 22.h),
                Text(
                  'Score financeiro',
                  style: GoogleFonts.inter(
                    color: _guardianTextPrimary(context),
                    fontSize: 20.sp,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8.h),
                Text(
                  'Este score pertence ao responsável autenticado neste acesso. Quando há mais de um aluno vinculado, a leitura continua sendo do responsável, não de um aluno isolado.',
                  style: GoogleFonts.inter(
                    color: _guardianTextSecondary(context),
                    fontSize: 12.5.sp,
                    fontWeight: FontWeight.w500,
                    height: 1.45,
                  ),
                ),
                SizedBox(height: 16.h),
                _InfoCard(
                  label: 'Responsável',
                  value: [
                    ownerName,
                    if ((relationship ?? '').trim().isNotEmpty) relationship,
                  ].join(' · '),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Faixa atual',
                  value:
                      '${score.value} de 1000 · ${_scoreClassificationLabel(score.classification)}',
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Confiança da leitura',
                  value: _scoreConfidenceLabel(score.confidenceLevel),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Última atualização',
                  value: _scoreUpdatedLabel(summary.lastCalculatedAt),
                ),
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Base analisada',
                  value:
                      '${summary.totalInvoices} boletos analisados, ${summary.paidOnTime} pagos em dia, ${summary.paidLate} pagos com atraso e ${summary.unpaidOverdue} vencidos em aberto.',
                ),
                if (summary.totalOverdueAmount > 0) ...[
                  SizedBox(height: 10.h),
                  _InfoCard(
                    label: 'Valor vencido em aberto',
                    value: _formatCurrency(summary.totalOverdueAmount.round()),
                  ),
                ],
                SizedBox(height: 10.h),
                _InfoCard(
                  label: 'Leitura atual',
                  value: _buildScoreReading(score),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildFeaturedCard(Invoice invoice) {
    final state = _resolveInvoiceState(invoice);
    final accent = _buildStatusColor(state);

    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: _isDarkContext(context) ? 0.18 : 0.14),
            _guardianSurface(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusChip(label: _buildFeaturedLabel(state), color: accent),
          SizedBox(height: 14.h),
          Text(
            _buildReferenceLabel(invoice),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w700,
              color: _guardianTextSecondary(context),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            invoice.description,
            style: GoogleFonts.inter(
              color: _guardianTextPrimary(context),
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 14.h),
          Text(
            _formatCurrency(invoice.value),
            style: GoogleFonts.inter(
              fontSize: 24.sp,
              fontWeight: FontWeight.w800,
              color: _guardianTextPrimary(context),
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            _buildDueText(invoice),
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: _guardianTextSecondary(context),
            ),
          ),
          SizedBox(height: 18.h),
          _InvoiceCardActionBar(
            accent: accent,
            onOpenBoleto: () => _openInvoiceBoleto(invoice),
            onCopyCode: () => _copyInvoiceCode(invoice),
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceFilterBar(_GuardianInvoiceGroups groups) {
    final totalActionable = groups.overdue.length + groups.pending.length;
    final items = [
      (
        filter: _GuardianFinanceFilter.priority,
        label: 'Agora',
        count: totalActionable,
        color: totalActionable > 0
            ? const Color(0xFF00A859)
            : _guardianTextSecondary(context),
      ),
      (
        filter: _GuardianFinanceFilter.overdue,
        label: 'Atrasados',
        count: groups.overdue.length,
        color: const Color(0xFFEF4444),
      ),
      (
        filter: _GuardianFinanceFilter.pending,
        label: 'Pendentes',
        count: groups.pending.length,
        color: const Color(0xFFF59E0B),
      ),
      (
        filter: _GuardianFinanceFilter.paid,
        label: 'Pagos',
        count: groups.paid.length,
        color: const Color(0xFF00A859),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = 8.w;
        final itemWidth = (constraints.maxWidth - gap) / 2;

        return Wrap(
          spacing: gap,
          runSpacing: 8.h,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: _FinanceFilterPill(
                  label: item.label,
                  count: item.count,
                  color: item.color,
                  selected: _financeFilter == item.filter,
                  onTap: () => setState(() => _financeFilter = item.filter),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInvoiceSection(
    String title,
    List<Invoice> items, {
    bool showPaidAccent = false,
  }) {
    if (items.isEmpty) {
      final isPriority = title == 'Prioridade agora';
      return _EmptyStateCard(
        title: isPriority
            ? 'Nenhuma cobrança para pagar agora'
            : '$title sem itens',
        message: title == 'Pagos'
            ? 'Os boletos pagos mais recentes aparecerão aqui.'
            : isPriority
                ? 'Quando houver boleto vencido ou próximo vencimento, ele aparecerá neste filtro.'
                : 'Quando houver boletos nesta categoria, eles aparecerão nesta seção.',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.inter(
            color: _guardianTextPrimary(context),
            fontSize: 18.sp,
            fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: 10.h),
        ...items.map(
          (invoice) => Padding(
            padding: EdgeInsets.only(bottom: 10.h),
            child: _InvoiceListTileCard(
              invoice: invoice,
              highlightPaid: showPaidAccent,
              onCopyCode: () => _copyInvoiceCode(invoice),
              onOpenBoleto: () => _openInvoiceBoleto(invoice),
              onDetails: () => _showInvoiceDetails(invoice),
            ),
          ),
        ),
      ],
    );
  }

  List<Invoice> _financeInvoicesForFilter(_GuardianInvoiceGroups groups) {
    switch (_financeFilter) {
      case _GuardianFinanceFilter.overdue:
        return groups.overdue;
      case _GuardianFinanceFilter.pending:
        return groups.pending;
      case _GuardianFinanceFilter.paid:
        return groups.paid;
      case _GuardianFinanceFilter.priority:
        if (groups.overdue.isNotEmpty) return groups.overdue;
        return groups.pending;
    }
  }

  String _financeFilterTitle(_GuardianFinanceFilter filter) {
    switch (filter) {
      case _GuardianFinanceFilter.overdue:
        return 'Atrasados';
      case _GuardianFinanceFilter.pending:
        return 'Pendentes';
      case _GuardianFinanceFilter.paid:
        return 'Pagos';
      case _GuardianFinanceFilter.priority:
        return 'Prioridade agora';
    }
  }

  _GuardianInvoiceGroups _invoiceGroups(List<Invoice> invoices) {
    final overdue = _sortInvoices(
      invoices.where(
        (invoice) => _resolveInvoiceState(invoice) == _InvoiceState.overdue,
      ),
    );
    final pending = _sortInvoices(
      invoices.where(
        (invoice) => _resolveInvoiceState(invoice) == _InvoiceState.pending,
      ),
    );
    final paid = _sortInvoices(
      invoices.where(
        (invoice) => _resolveInvoiceState(invoice) == _InvoiceState.paid,
      ),
      descending: true,
    );

    final featured = overdue.isNotEmpty
        ? overdue.first
        : pending.isNotEmpty
            ? pending.first
            : null;

    return _GuardianInvoiceGroups(
      overdue: overdue,
      pending: pending,
      paid: paid,
      featured: featured,
    );
  }

  String? _resolveInvoiceCode(Invoice invoice) {
    final digitable = _digitsOnly(invoice.boletoDigitableLine);
    if (digitable.length == 47) {
      return digitable;
    }

    final barcode = _digitsOnly(invoice.boletoBarcode);
    if (barcode.length == 47) {
      return barcode;
    }
    if (barcode.length == 44) {
      return _convertToDigitableLine(barcode) ?? barcode;
    }
    if (barcode.isNotEmpty) {
      return barcode;
    }
    return null;
  }

  String _digitsOnly(String? value) {
    return (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  }

  String? _convertToDigitableLine(String rawBarcode) {
    final barcode = _digitsOnly(rawBarcode);
    if (barcode.length != 44) return null;

    int mod10(String block) {
      int sum = 0;
      bool multiplyBy2 = true;
      for (int i = block.length - 1; i >= 0; i--) {
        final digit = int.parse(block[i]);
        final multiplied = digit * (multiplyBy2 ? 2 : 1);
        sum += multiplied > 9
            ? (multiplied ~/ 10) + (multiplied % 10)
            : multiplied;
        multiplyBy2 = !multiplyBy2;
      }
      final remainder = sum % 10;
      final dv = 10 - remainder;
      return dv == 10 ? 0 : dv;
    }

    final field1Base = barcode.substring(0, 4) + barcode.substring(19, 24);
    final field2Base = barcode.substring(24, 34);
    final field3Base = barcode.substring(34, 44);
    return '$field1Base${mod10(field1Base)}'
        '$field2Base${mod10(field2Base)}'
        '$field3Base${mod10(field3Base)}'
        '${barcode.substring(4, 5)}${barcode.substring(5, 19)}';
  }

  String _buildScheduleHubDescription(GuardianScheduleSnapshot? schedule) {
    if (schedule?.currentClass != null) {
      return 'Aula em andamento: ${schedule!.currentClass!.subjectName} · ${schedule.currentClass!.timeLabel}';
    }
    if (schedule?.nextClass != null) {
      return 'Próxima aula: ${schedule!.nextClass!.subjectName} · ${schedule.nextClass!.timeLabel}';
    }
    return 'Sem aulas em destaque no momento.';
  }

  String _buildAttendanceHomeSubtitle(GuardianAttendanceSummary? summary) {
    if (summary == null || summary.totalRecords == 0) {
      return 'Ainda não há registros suficientes para resumir a frequência.';
    }

    final recentAbsences = summary.recentAbsences;
    final absences = summary.absentCount;
    if (recentAbsences > 0) {
      return '$absences faltas registradas · $recentAbsences recentes';
    }
    return '$absences faltas registradas · presença dentro do esperado';
  }

  String _buildActivitiesHomeHeadline(GuardianActivitiesSummary? summary) {
    if (summary == null) return 'Sem dados';
    if (summary.pendingCount > 0) {
      return '${summary.pendingCount} pendentes';
    }
    return '${summary.recentCount} recentes';
  }

  String _buildActivitiesHomeSubtitle(GuardianActivitiesSummary? summary) {
    if (summary == null || summary.totalActivities == 0) {
      return 'As atividades registradas para responsáveis aparecerão aqui.';
    }

    final last = summary.lastActivity;
    if (last != null) {
      return '${summary.deliveredCount} entregues · última em ${last.subjectName}';
    }
    return '${summary.deliveredCount} entregues · ${summary.overdueCount} em atraso';
  }

  String _buildActivitiesHubDescription(GuardianActivitiesSummary? summary) {
    if (summary == null || summary.totalActivities == 0) {
      return 'Nenhuma atividade com visibilidade para responsáveis no momento.';
    }
    return '${summary.recentCount} atividades recentes · ${summary.pendingCount} pendentes · ${summary.overdueCount} em atraso';
  }

  Color _attendanceAccent(String? attentionLevel) {
    return attentionLevel == 'attention'
        ? const Color(0xFFF59E0B)
        : const Color(0xFF00A859);
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final invoices = context.watch<InvoiceProvider>();
    final session = auth.guardianSession;

    return Scaffold(
      backgroundColor: _guardianScreenBackground(context),
      extendBody: true,
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(session),
      body: Stack(
        children: [
          Positioned.fill(
            child: IndexedStack(
              index: _currentIndex,
              children: [
                _buildHomeTab(session, invoices),
                _buildTrackingTab(),
                _buildFinanceTab(session, invoices),
                _buildAccountTab(auth, session),
                GuardianDocumentsScreen(
                  selectedStudent: _selectedStudent,
                  focusRequestId: _focusedDocumentRequestId,
                  focusDocumentId: _focusedDocumentId,
                  focusNonce: _documentsFocusNonce,
                ),
                _buildAttendanceTab(),
              ],
            ),
          ),
          Positioned.fill(
            child: CustomSpeedDialMenu(
              currentIndex: _currentIndex,
              onTabSelected: _onTabTapped,
              onNavigateToStaff: () {},
              onNavigateToAttendance: () {},
              isGuardian: true,
              onGuardianRefresh: _refreshGuardianPortal,
              onGuardianDocuments: () => _onTabTapped(4),
              onGuardianAttendance: () => _onTabTapped(5),
              onGuardianAccount: () => _onTabTapped(3),
              onGuardianStudentSwitcher: (session?.linkedStudentsCount ?? 0) > 1
                  ? _showStudentPicker
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianInvoiceGroups {
  final List<Invoice> overdue;
  final List<Invoice> pending;
  final List<Invoice> paid;
  final Invoice? featured;

  const _GuardianInvoiceGroups({
    required this.overdue,
    required this.pending,
    required this.paid,
    required this.featured,
  });
}

class _NotificationBellButton extends StatelessWidget {
  final int unreadCount;
  final VoidCallback onTap;

  const _NotificationBellButton({
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;

    return Semantics(
      button: true,
      label: hasUnread
          ? '$unreadCount notificações não lidas'
          : 'Abrir notificações',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16.r),
        child: Container(
          width: 44.w,
          height: 44.w,
          decoration: BoxDecoration(
            color: _guardianSoftSurface(context),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(color: _guardianBorder(context)),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Icon(
                  hasUnread
                      ? PhosphorIcons.bell_ringing_fill
                      : PhosphorIcons.bell_fill,
                  color: hasUnread
                      ? const Color(0xFF00A859)
                      : _guardianTextSecondary(context),
                  size: 20.sp,
                ),
              ),
              if (hasUnread)
                Positioned(
                  right: -3.w,
                  top: -3.h,
                  child: Container(
                    constraints: BoxConstraints(minWidth: 18.w),
                    height: 18.w,
                    padding: EdgeInsets.symmetric(horizontal: 5.w),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(999.r),
                      border: Border.all(
                        color: _guardianAppBarBackground(context),
                        width: 2,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        unreadCount > 9 ? '9+' : '$unreadCount',
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _GuardianFinanceFilter { priority, overdue, pending, paid }

enum _InvoiceState { pending, overdue, paid, canceled }

bool _isDarkContext(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _guardianScreenBackground(BuildContext context) =>
    _isDarkContext(context) ? const Color(0xFF0B1117) : const Color(0xFFF4F7FB);

Color _guardianSurface(BuildContext context) => Theme.of(context).cardColor;

Color _guardianSoftSurface(BuildContext context) =>
    _isDarkContext(context) ? const Color(0xFF121A23) : const Color(0xFFF8FAFC);

Color _guardianBorder(BuildContext context) =>
    _isDarkContext(context) ? const Color(0xFF223042) : const Color(0xFFE5E7EB);

Color _guardianTextPrimary(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface;

Color _guardianTextSecondary(BuildContext context) =>
    _isDarkContext(context) ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

Color _guardianAppBarBackground(BuildContext context) => _isDarkContext(context)
    ? const Color(0xFF0B1117).withValues(alpha: 0.96)
    : Colors.white.withValues(alpha: 0.94);

String _guardianInitials(String? value) {
  final parts = (value ?? '')
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) return 'A';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'
      .toUpperCase();
}

List<Invoice> _sortInvoices(
  Iterable<Invoice> invoices, {
  bool descending = false,
}) {
  final items = invoices.toList();
  items.sort((left, right) {
    final comparison = left.dueDate.compareTo(right.dueDate);
    return descending ? -comparison : comparison;
  });
  return items;
}

_InvoiceState _resolveInvoiceState(Invoice invoice) {
  final status = invoice.status.toLowerCase().trim();
  if (status == 'paid' || status == 'pago') return _InvoiceState.paid;
  if (status == 'canceled' || status == 'cancelado') {
    return _InvoiceState.canceled;
  }
  if (status == 'overdue' || status == 'vencido') {
    return _InvoiceState.overdue;
  }

  final today = DateUtils.dateOnly(DateTime.now());
  final dueDate = DateUtils.dateOnly(invoice.dueDate);
  if (dueDate.isBefore(today)) {
    return _InvoiceState.overdue;
  }
  return _InvoiceState.pending;
}

String _buildStatusLabel(_InvoiceState state) {
  switch (state) {
    case _InvoiceState.overdue:
      return 'Em atraso';
    case _InvoiceState.paid:
      return 'Pago';
    case _InvoiceState.canceled:
      return 'Cancelado';
    case _InvoiceState.pending:
      return 'Pendente';
  }
}

String _scoreClassificationLabel(String classification) {
  switch (classification.toLowerCase().trim()) {
    case 'excellent':
      return 'Excelente';
    case 'good':
      return 'Bom';
    case 'risk':
      return 'Atenção';
    case 'high_risk':
      return 'Crítico';
    case 'moderate':
    default:
      return 'Moderado';
  }
}

Color _scoreClassificationColor(String classification) {
  switch (classification.toLowerCase().trim()) {
    case 'excellent':
      return const Color(0xFF00A859);
    case 'good':
      return const Color(0xFF2F80ED);
    case 'risk':
      return const Color(0xFFF59E0B);
    case 'high_risk':
      return const Color(0xFFEF4444);
    case 'moderate':
    default:
      return const Color(0xFF7C3AED);
  }
}

String _scoreConfidenceLabel(String confidenceLevel) {
  switch (confidenceLevel.toLowerCase().trim()) {
    case 'high':
      return 'Alta';
    case 'medium':
      return 'Média';
    case 'low':
    default:
      return 'Baixa';
  }
}

String _buildScoreReading(GuardianFinancialScore score) {
  final summary = score.summary;
  if (summary.unpaidOverdue > 0) {
    return 'Há boletos vencidos influenciando esta leitura. Regularizar os itens em atraso é o caminho mais importante agora.';
  }
  if (summary.paidLate > 0) {
    return 'A leitura considera pagamentos já quitados com atraso. Manter os próximos vencimentos em dia ajuda a estabilizar o score.';
  }
  if (summary.consecutiveOnTimePayments >= 3) {
    return 'Os pagamentos recentes em dia fortalecem esta leitura e indicam boa previsibilidade financeira.';
  }
  if (summary.totalInvoices == 0) {
    return 'Ainda há poucos dados financeiros para uma leitura completa deste responsável.';
  }
  return 'O score resume o comportamento financeiro atual registrado pela escola, sem histórico de variação nesta versão.';
}

String _buildFeaturedLabel(_InvoiceState state) {
  switch (state) {
    case _InvoiceState.overdue:
      return 'Boleto mais urgente';
    case _InvoiceState.pending:
      return 'Próximo vencimento';
    case _InvoiceState.paid:
      return 'Último boleto pago';
    case _InvoiceState.canceled:
      return 'Boleto cancelado';
  }
}

Color _buildStatusColor(_InvoiceState state) {
  switch (state) {
    case _InvoiceState.overdue:
      return const Color(0xFFEF4444);
    case _InvoiceState.paid:
      return const Color(0xFF00A859);
    case _InvoiceState.canceled:
      return const Color(0xFF64748B);
    case _InvoiceState.pending:
      return const Color(0xFFF59E0B);
  }
}

String _buildAccessStatusLabel(String status) {
  switch (status.toLowerCase().trim()) {
    case 'blocked':
      return 'Bloqueado';
    case 'inactive':
      return 'Desativado';
    case 'pending':
      return 'Pendente';
    case 'active':
    default:
      return 'Ativo';
  }
}

String _buildReferenceLabel(Invoice invoice) {
  final raw = DateFormat('MMMM yyyy', 'pt_BR').format(invoice.dueDate);
  return toBeginningOfSentenceCase(raw) ?? raw;
}

String _buildDate(DateTime date) {
  return DateFormat('dd/MM/yyyy', 'pt_BR').format(date);
}

String _scoreUpdatedLabel(DateTime? date) {
  if (date == null) return 'Ainda sem cálculo recente';
  return _buildDate(date);
}

String _buildDueText(Invoice invoice) {
  if (_resolveInvoiceState(invoice) == _InvoiceState.paid &&
      invoice.effectivePaidAt != null) {
    return 'Pago em ${_buildDate(invoice.effectivePaidAt!)}';
  }

  final dueDate = DateUtils.dateOnly(invoice.dueDate);
  final today = DateUtils.dateOnly(DateTime.now());
  final formatted = _buildDate(invoice.dueDate);

  if (_resolveInvoiceState(invoice) == _InvoiceState.overdue) {
    final days = today.difference(dueDate).inDays;
    return days <= 0
        ? 'Venceu em $formatted'
        : 'Vencido há $days ${days == 1 ? 'dia' : 'dias'}';
  }

  final diff = dueDate.difference(today).inDays;
  if (diff == 0) return 'Vence hoje · $formatted';
  if (diff == 1) return 'Vence amanhã · $formatted';
  return 'Vence em $diff dias · $formatted';
}

String _formatCurrency(int valueInCents) {
  return NumberFormat.currency(locale: 'pt_BR', symbol: 'R\$')
      .format(valueInCents / 100);
}

class _GuardianAccountContextCard extends StatelessWidget {
  final String schoolName;
  final Uint8List? schoolLogoBytes;
  final GuardianLinkedStudent? currentStudent;
  final int linkedStudentsCount;

  const _GuardianAccountContextCard({
    required this.schoolName,
    required this.schoolLogoBytes,
    required this.currentStudent,
    required this.linkedStudentsCount,
  });

  @override
  Widget build(BuildContext context) {
    final studentLabel = currentStudent == null
        ? 'Nenhum aluno selecionado'
        : currentStudent!.firstName;

    return Container(
      padding: EdgeInsets.all(14.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 46.w,
            height: 46.w,
            decoration: BoxDecoration(
              color: _guardianSoftSurface(context),
              shape: BoxShape.circle,
            ),
            clipBehavior: Clip.antiAlias,
            child: schoolLogoBytes != null && schoolLogoBytes!.isNotEmpty
                ? Image.memory(
                    schoolLogoBytes!,
                    fit: BoxFit.cover,
                  )
                : Center(
                    child: Text(
                      _guardianInitials(schoolName),
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF00A859),
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
                  'Escola atual',
                  style: GoogleFonts.inter(
                    fontSize: 11.sp,
                    fontWeight: FontWeight.w700,
                    color: _guardianTextSecondary(context),
                  ),
                ),
                SizedBox(height: 3.h),
                Text(
                  schoolName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w700,
                    color: _guardianTextPrimary(context),
                  ),
                ),
                SizedBox(height: 5.h),
                Wrap(
                  spacing: 8.w,
                  runSpacing: 8.h,
                  children: [
                    _AccountMiniBadge(
                      icon: PhosphorIcons.student_fill,
                      label: studentLabel,
                    ),
                    _AccountMiniBadge(
                      icon: PhosphorIcons.users_three_fill,
                      label:
                          '$linkedStudentsCount ${linkedStudentsCount == 1 ? 'filho vinculado' : 'filhos vinculados'}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountMiniBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AccountMiniBadge({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 9.w, vertical: 7.h),
      decoration: BoxDecoration(
        color: _guardianSoftSurface(context),
        borderRadius: BorderRadius.circular(999.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 12.sp,
            color: const Color(0xFF00A859),
          ),
          SizedBox(width: 6.w),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.5.sp,
              fontWeight: FontWeight.w600,
              color: _guardianTextPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianStudentOptionTile extends StatelessWidget {
  final GuardianLinkedStudent student;
  final bool selected;
  final VoidCallback onTap;

  const _GuardianStudentOptionTile({
    required this.student,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final classLabel = student.classInfo?.name ?? student.relationship;
    const accent = Color(0xFF00A859);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20.r),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.12)
              : _guardianSoftSurface(context),
          borderRadius: BorderRadius.circular(20.r),
          border: Border.all(
            color: selected ? accent : _guardianBorder(context),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: _guardianSurface(context),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                _guardianInitials(student.fullName),
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    student.fullName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: _guardianTextPrimary(context),
                    ),
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    classLabel,
                    style: GoogleFonts.inter(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w500,
                      color: _guardianTextSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(
                PhosphorIcons.check_circle_fill,
                color: accent,
                size: 20.sp,
              ),
          ],
        ),
      ),
    );
  }
}

class _SettingsSectionCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;

  const _SettingsSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(16.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              color: _guardianTextPrimary(context),
            ),
          ),
          if ((subtitle ?? '').trim().isNotEmpty) ...[
            SizedBox(height: 5.h),
            Text(
              subtitle!,
              style: GoogleFonts.inter(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
                height: 1.35,
              ),
            ),
          ],
          SizedBox(height: 12.h),
          child,
        ],
      ),
    );
  }
}

class _SettingsInfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? helper;

  const _SettingsInfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.helper,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 10.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34.w,
            height: 34.w,
            decoration: BoxDecoration(
              color: _guardianSoftSurface(context),
              borderRadius: BorderRadius.circular(12.r),
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 18.sp,
              color: const Color(0xFF00A859),
            ),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w600,
                    color: _guardianTextSecondary(context),
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 14.sp,
                    fontWeight: FontWeight.w700,
                    color: _guardianTextPrimary(context),
                    height: 1.3,
                  ),
                ),
                if ((helper ?? '').trim().isNotEmpty) ...[
                  SizedBox(height: 3.h),
                  Text(
                    helper!,
                    style: GoogleFonts.inter(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w500,
                      color: _guardianTextSecondary(context),
                      height: 1.4,
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
}

class _SettingsActionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String? badgeLabel;
  final VoidCallback? onTap;

  const _SettingsActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.badgeLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.all(12.r),
        decoration: BoxDecoration(
          color: _guardianSoftSurface(context),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: _guardianBorder(context)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 34.w,
              height: 34.w,
              decoration: BoxDecoration(
                color: _guardianSurface(context),
                borderRadius: BorderRadius.circular(12.r),
              ),
              alignment: Alignment.center,
              child: Icon(
                icon,
                size: 16.sp,
                color: const Color(0xFF00A859),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: GoogleFonts.inter(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w700,
                            color: _guardianTextPrimary(context),
                          ),
                        ),
                      ),
                      if ((badgeLabel ?? '').trim().isNotEmpty)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10.w,
                            vertical: 5.h,
                          ),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF00A859).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999.r),
                          ),
                          child: Text(
                            badgeLabel!,
                            style: GoogleFonts.inter(
                              fontSize: 10.sp,
                              fontWeight: FontWeight.w800,
                              color: const Color(0xFF00A859),
                            ),
                          ),
                        ),
                    ],
                  ),
                  SizedBox(height: 4.h),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 11.5.sp,
                      fontWeight: FontWeight.w500,
                      color: _guardianTextSecondary(context),
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
            if (onTap != null) ...[
              SizedBox(width: 10.w),
              Icon(
                PhosphorIcons.caret_right_bold,
                size: 15.sp,
                color: _guardianTextSecondary(context),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeSelected;

  const _ThemeModeSelector({
    required this.themeMode,
    required this.onThemeModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _ThemeModeChoiceChip(
                label: 'Sistema',
                icon: PhosphorIcons.gear_fill,
                selected: themeMode == ThemeMode.system,
                onTap: () => onThemeModeSelected(ThemeMode.system),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _ThemeModeChoiceChip(
                label: 'Claro',
                icon: PhosphorIcons.sun_fill,
                selected: themeMode == ThemeMode.light,
                onTap: () => onThemeModeSelected(ThemeMode.light),
              ),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: _ThemeModeChoiceChip(
                label: 'Escuro',
                icon: PhosphorIcons.moon_fill,
                selected: themeMode == ThemeMode.dark,
                onTap: () => onThemeModeSelected(ThemeMode.dark),
              ),
            ),
          ],
        ),
        SizedBox(height: 10.h),
        Text(
          'A preferência fica salva neste dispositivo e reaproveita o mesmo sistema de tema do aplicativo.',
          style: GoogleFonts.inter(
            fontSize: 11.sp,
            fontWeight: FontWeight.w500,
            color: _guardianTextSecondary(context),
            height: 1.45,
          ),
        ),
      ],
    );
  }
}

class _ThemeModeChoiceChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeModeChoiceChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const accent = Color(0xFF7A5AF8);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.14)
              : _guardianSoftSurface(context),
          borderRadius: BorderRadius.circular(18.r),
          border: Border.all(
            color: selected ? accent : _guardianBorder(context),
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18.sp,
              color: selected ? accent : _guardianTextSecondary(context),
            ),
            SizedBox(height: 8.h),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: selected ? accent : _guardianTextPrimary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardianLessonSummaryCard extends StatelessWidget {
  final GuardianScheduleSnapshot? schedule;
  final VoidCallback onOpenSchedule;

  const _GuardianLessonSummaryCard({
    required this.schedule,
    required this.onOpenSchedule,
  });

  @override
  Widget build(BuildContext context) {
    final currentLesson = schedule?.currentClass;
    final nextLesson = schedule?.nextClass;
    final spotlight = currentLesson ?? nextLesson;
    final isCurrent = currentLesson != null;
    final accent =
        isCurrent ? const Color(0xFF00A859) : const Color(0xFF2F80ED);

    if (spotlight == null) {
      return const _EmptyStateCard(
        title: 'Sem aulas em destaque',
        message:
            'Quando houver aulas programadas, a aula atual ou a próxima aula aparecerá aqui.',
      );
    }

    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            accent.withValues(alpha: _isDarkContext(context) ? 0.18 : 0.12),
            _guardianSurface(context),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28.r),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StatusChip(
            label: isCurrent ? 'Acontecendo agora' : 'Próxima aula',
            color: accent,
          ),
          SizedBox(height: 12.h),
          Text(
            spotlight.subjectName,
            style: GoogleFonts.inter(
              color: _guardianTextPrimary(context),
              fontSize: 20.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            spotlight.timeLabel,
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              fontWeight: FontWeight.w800,
              color: _guardianTextPrimary(context),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            [
              spotlight.teacherName,
              if ((spotlight.room ?? '').trim().isNotEmpty) spotlight.room!,
              if (spotlight.weekdayLabel.trim().isNotEmpty)
                spotlight.weekdayLabel,
            ].join(' · '),
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: _guardianTextSecondary(context),
              height: 1.35,
            ),
          ),
          if ((schedule?.todayCount ?? 0) > 0) ...[
            SizedBox(height: 10.h),
            Text(
              '${schedule!.todayCount} aula(s) programada(s) para hoje',
              style: GoogleFonts.inter(
                fontSize: 12.sp,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
          ],
          SizedBox(height: 14.h),
          ElevatedButton.icon(
            onPressed: onOpenSchedule,
            icon: Icon(PhosphorIcons.calendar_blank, size: 16.sp),
            label: const Text('Ver grade completa'),
            style: ElevatedButton.styleFrom(
              backgroundColor: accent,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}

class _GuardianHomeSummaryCard extends StatelessWidget {
  final String title;
  final Color accentColor;
  final IconData icon;
  final String headline;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;

  const _GuardianHomeSummaryCard({
    required this.title,
    required this.accentColor,
    required this.icon,
    required this.headline,
    required this.subtitle,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24.r),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: _guardianSurface(context),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: accentColor.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(icon, color: accentColor, size: 18.sp),
            ),
            SizedBox(height: 10.h),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w700,
                color: _guardianTextPrimary(context),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              headline,
              style: GoogleFonts.inter(
                color: _guardianTextPrimary(context),
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              subtitle,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
                height: 1.35,
              ),
            ),
            SizedBox(height: 10.h),
            Text(
              actionLabel,
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                color: accentColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardianHubCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color accent;
  final String description;
  final String footnote;
  final VoidCallback onTap;

  const _GuardianHubCard({
    required this.title,
    required this.icon,
    required this.accent,
    required this.description,
    required this.footnote,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(24.r),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: _guardianSurface(context),
          borderRadius: BorderRadius.circular(24.r),
          border: Border.all(color: accent.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14.r),
                  ),
                  child: Icon(icon, color: accent, size: 18.sp),
                ),
                SizedBox(width: 10.w),
                Expanded(
                  child: Text(
                    title,
                    style: GoogleFonts.inter(
                      color: _guardianTextPrimary(context),
                      fontSize: 16.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  PhosphorIcons.caret_right_bold,
                  color: accent,
                  size: 18.sp,
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              description,
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: _guardianTextPrimary(context),
                height: 1.35,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              footnote,
              style: GoogleFonts.inter(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuardianLoadingCard extends StatelessWidget {
  final String label;

  const _GuardianLoadingCard({
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Row(
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF00A859),
            strokeWidth: 2.4,
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12.5.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalShortcutCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _PortalShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22.r),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: _guardianSurface(context),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: color.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14.r),
              ),
              child: Icon(icon, color: color, size: 20.sp),
            ),
            SizedBox(height: 10.h),
            Text(
              title,
              style: GoogleFonts.inter(
                fontSize: 14.sp,
                fontWeight: FontWeight.w700,
                color: _guardianTextPrimary(context),
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              subtitle,
              style: GoogleFonts.inter(
                fontSize: 11.5.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
                height: 1.35,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Abrir módulo',
              style: GoogleFonts.inter(
                fontSize: 11.sp,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalFinanceSpotlight extends StatelessWidget {
  final Invoice invoice;
  final VoidCallback onOpenFinance;
  final Future<void> Function() onCopyCode;
  final Future<void> Function() onOpenBoleto;

  const _PortalFinanceSpotlight({
    required this.invoice,
    required this.onOpenFinance,
    required this.onCopyCode,
    required this.onOpenBoleto,
  });

  @override
  Widget build(BuildContext context) {
    final state = _resolveInvoiceState(invoice);
    final accent = _buildStatusColor(state);

    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Destaque do financeiro',
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w800,
              color: accent,
              letterSpacing: 0.3,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            invoice.description,
            style: GoogleFonts.inter(
              color: _guardianTextPrimary(context),
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            '${_buildStatusLabel(state)} · ${_buildDueText(invoice)}',
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w500,
              color: _guardianTextSecondary(context),
              height: 1.3,
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            _formatCurrency(invoice.value),
            style: GoogleFonts.inter(
              fontSize: 18.sp,
              fontWeight: FontWeight.w800,
              color: _guardianTextPrimary(context),
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onOpenFinance,
                  icon: Icon(PhosphorIcons.money_fill, size: 16.sp),
                  label: const Text('Ir para financeiro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00A859),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    minimumSize: Size.fromHeight(44.h),
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopyCode,
                  icon: Icon(PhosphorIcons.copy_simple, size: 15.sp),
                  label: const Text('Copiar código'),
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onOpenBoleto,
                  icon: Icon(PhosphorIcons.download_simple, size: 15.sp),
                  label: const Text('Abrir boleto'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GuardianFinancialScoreCard extends StatelessWidget {
  final GuardianFinancialScoreContext scoreContext;
  final VoidCallback onDetails;

  const _GuardianFinancialScoreCard({
    required this.scoreContext,
    required this.onDetails,
  });

  @override
  Widget build(BuildContext context) {
    final score = scoreContext.score!;
    final accent = _scoreClassificationColor(score.classification);
    final normalized = score.value.clamp(0, 1000).toDouble() / 1000;
    final ownerName = (scoreContext.owner?.fullName ?? '').trim();

    return Container(
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42.w,
                height: 42.w,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16.r),
                ),
                child: Icon(
                  PhosphorIcons.chart_line_up,
                  color: accent,
                  size: 22.sp,
                ),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Score financeiro',
                      style: GoogleFonts.inter(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w800,
                        color: _guardianTextPrimary(context),
                      ),
                    ),
                    SizedBox(height: 3.h),
                    Text(
                      ownerName.isEmpty
                          ? 'Leitura do responsável autenticado.'
                          : 'Leitura de $ownerName.',
                      style: GoogleFonts.inter(
                        fontSize: 11.5.sp,
                        fontWeight: FontWeight.w500,
                        color: _guardianTextSecondary(context),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: onDetails,
                style: TextButton.styleFrom(
                  minimumSize: Size(44.w, 36.h),
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                ),
                child: const Text('Entender'),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${score.value}',
                style: GoogleFonts.inter(
                  fontSize: 30.sp,
                  fontWeight: FontWeight.w900,
                  color: _guardianTextPrimary(context),
                  height: 1,
                ),
              ),
              SizedBox(width: 5.w),
              Padding(
                padding: EdgeInsets.only(bottom: 2.h),
                child: Text(
                  '/1000',
                  style: GoogleFonts.inter(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    color: _guardianTextSecondary(context),
                  ),
                ),
              ),
              const Spacer(),
              _StatusChip(
                label: _scoreClassificationLabel(score.classification),
                color: accent,
              ),
            ],
          ),
          SizedBox(height: 12.h),
          ClipRRect(
            borderRadius: BorderRadius.circular(999.r),
            child: LinearProgressIndicator(
              minHeight: 7.h,
              value: normalized,
              backgroundColor: _guardianBorder(context),
              valueColor: AlwaysStoppedAnimation<Color>(accent),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            _buildScoreReading(score),
            style: GoogleFonts.inter(
              fontSize: 12.5.sp,
              fontWeight: FontWeight.w500,
              color: _guardianTextSecondary(context),
              height: 1.45,
            ),
          ),
          SizedBox(height: 12.h),
          Row(
            children: [
              Expanded(
                child: _ScoreMetaPill(
                  label: 'Confiança',
                  value: _scoreConfidenceLabel(score.confidenceLevel),
                ),
              ),
              SizedBox(width: 8.w),
              Expanded(
                child: _ScoreMetaPill(
                  label: 'Atualizado',
                  value: _scoreUpdatedLabel(score.summary.lastCalculatedAt),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreMetaPill extends StatelessWidget {
  final String label;
  final String value;

  const _ScoreMetaPill({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: _guardianSoftSurface(context),
        borderRadius: BorderRadius.circular(16.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10.sp,
              fontWeight: FontWeight.w700,
              color: _guardianTextSecondary(context),
            ),
          ),
          SizedBox(height: 3.h),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w800,
              color: _guardianTextPrimary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceFilterPill extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _FinanceFilterPill({
    required this.label,
    required this.count,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        constraints: BoxConstraints(minHeight: 48.h),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: _isDarkContext(context) ? 0.2 : 0.12)
              : _guardianSurface(context),
          borderRadius: BorderRadius.circular(999.r),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.55)
                : _guardianBorder(context),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w800,
                  color: selected ? color : _guardianTextPrimary(context),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 3.h),
              decoration: BoxDecoration(
                color: selected
                    ? color.withValues(alpha: 0.16)
                    : _guardianSoftSurface(context),
                borderRadius: BorderRadius.circular(999.r),
              ),
              child: Text(
                '$count',
                style: GoogleFonts.inter(
                  fontSize: 10.sp,
                  fontWeight: FontWeight.w900,
                  color: selected ? color : _guardianTextSecondary(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceListTileCard extends StatelessWidget {
  final Invoice invoice;
  final bool highlightPaid;
  final VoidCallback onDetails;
  final Future<void> Function() onCopyCode;
  final Future<void> Function() onOpenBoleto;

  const _InvoiceListTileCard({
    required this.invoice,
    required this.highlightPaid,
    required this.onDetails,
    required this.onCopyCode,
    required this.onOpenBoleto,
  });

  @override
  Widget build(BuildContext context) {
    final state = _resolveInvoiceState(invoice);
    final accent =
        highlightPaid ? const Color(0xFF00A859) : _buildStatusColor(state);

    return InkWell(
      onTap: onDetails,
      borderRadius: BorderRadius.circular(22.r),
      child: Container(
        padding: EdgeInsets.all(16.r),
        decoration: BoxDecoration(
          color: _guardianSurface(context),
          borderRadius: BorderRadius.circular(22.r),
          border: Border.all(color: accent.withValues(alpha: 0.15)),
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
                        _buildReferenceLabel(invoice),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 10.5.sp,
                          fontWeight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      Text(
                        invoice.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w700,
                          color: _guardianTextPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                _StatusChip(label: _buildStatusLabel(state), color: accent),
                SizedBox(width: 4.w),
                SizedBox(
                  width: 36.w,
                  height: 36.w,
                  child: IconButton(
                    tooltip: 'Detalhes',
                    onPressed: onDetails,
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      PhosphorIcons.info,
                      size: 18.sp,
                      color: _guardianTextSecondary(context),
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: 10.h),
            Text(
              _formatCurrency(invoice.value),
              style: GoogleFonts.inter(
                color: _guardianTextPrimary(context),
                fontSize: 20.sp,
                fontWeight: FontWeight.w800,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              _buildDueText(invoice),
              style: GoogleFonts.inter(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: _guardianTextSecondary(context),
              ),
            ),
            SizedBox(height: 14.h),
            _InvoiceCardActionBar(
              accent: accent,
              onOpenBoleto: onOpenBoleto,
              onCopyCode: onCopyCode,
            ),
          ],
        ),
      ),
    );
  }
}

class _InvoiceCardActionBar extends StatelessWidget {
  final Color accent;
  final Future<void> Function() onOpenBoleto;
  final Future<void> Function() onCopyCode;

  const _InvoiceCardActionBar({
    required this.accent,
    required this.onOpenBoleto,
    required this.onCopyCode,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 340.w;
        final openButton = ElevatedButton.icon(
          onPressed: onOpenBoleto,
          icon: Icon(PhosphorIcons.download_simple, size: 16.sp),
          label: const Text(
            'Abrir boleto',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: accent,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: Size.fromHeight(44.h),
          ),
        );
        final copyButton = OutlinedButton.icon(
          onPressed: onCopyCode,
          icon: Icon(PhosphorIcons.copy_simple, size: 15.sp),
          label: const Text(
            'Copiar código',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: OutlinedButton.styleFrom(
            minimumSize: Size.fromHeight(44.h),
          ),
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              openButton,
              SizedBox(height: 8.h),
              copyButton,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: openButton),
            SizedBox(width: 10.w),
            Expanded(child: copyButton),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _MetricCard({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(22.r),
        border: Border.all(color: color.withValues(alpha: 0.16)),
      ),
      child: Column(
        children: [
          Text(
            '$count',
            style: GoogleFonts.inter(
              color: color,
              fontSize: 22.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 4.h),
          Text(
            label,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11.5.sp,
              fontWeight: FontWeight.w600,
              color: _guardianTextSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusChip({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999.r),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 11.sp,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String label;
  final String value;

  const _InfoCard({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(18.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: _guardianTextSecondary(context),
            ),
          ),
          SizedBox(height: 6.h),
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 14.sp,
              fontWeight: FontWeight.w700,
              color: _guardianTextPrimary(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyStateCard extends StatelessWidget {
  final String title;
  final String message;

  const _EmptyStateCard({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: _guardianBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.inter(
              color: _guardianTextPrimary(context),
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: _guardianTextSecondary(context),
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorCard({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(20.r),
      decoration: BoxDecoration(
        color: _guardianSurface(context),
        borderRadius: BorderRadius.circular(24.r),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Não foi possível carregar tudo agora',
            style: GoogleFonts.inter(
              color: const Color(0xFF991B1B),
              fontSize: 18.sp,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: 10.h),
          Text(
            message,
            style: GoogleFonts.inter(
              fontSize: 13.sp,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF7F1D1D),
              height: 1.45,
            ),
          ),
          SizedBox(height: 16.h),
          ElevatedButton.icon(
            onPressed: onRetry,
            icon: Icon(PhosphorIcons.arrow_clockwise, size: 16.sp),
            label: const Text('Tentar novamente'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF111827),
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}
