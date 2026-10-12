import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:flutter/foundation.dart';
import '../services/report_card_service.dart';

class ReportCardProvider extends ChangeNotifier {
  final ReportCardService service;

  ReportCardProvider({
    required this.service,
  });

  bool _isLoading = false;
  bool _isGenerating = false;
  bool _isSaving = false;

  String? _errorMessage;

  ReportCardModel? _currentReportCard;
  List<ReportCardModel> _classReportCards = [];
  int _generationRequest = 0;

  bool get isLoading => _isLoading;
  bool get isGenerating => _isGenerating;
  bool get isSaving => _isSaving;
  String? get errorMessage => _errorMessage;

  ReportCardModel? get currentReportCard => _currentReportCard;
  List<ReportCardModel> get classReportCards => _classReportCards;

  void replaceClassReportCards(List<ReportCardModel> reportCards) {
    _classReportCards = List<ReportCardModel>.from(reportCards);
    notifyListeners();
  }

  void upsertReportCard(ReportCardModel reportCard) {
    _upsertReportCardInCache(reportCard);
    notifyListeners();
  }

  ReportCardModel? getCachedReportCardById(String reportCardId) {
    try {
      return _classReportCards.firstWhere((item) => item.id == reportCardId);
    } catch (_) {
      return null;
    }
  }

  void _upsertReportCardInCache(ReportCardModel reportCard) {
    final index =
        _classReportCards.indexWhere((item) => item.id == reportCard.id);
    if (index == -1) {
      _classReportCards = [reportCard, ..._classReportCards];
    } else {
      _classReportCards[index] = reportCard;
    }
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  void clearCurrentReportCard() {
    _currentReportCard = null;
    notifyListeners();
  }

  void clearClassReportCards() {
    _classReportCards = [];
    notifyListeners();
  }

  void clear() {
    _generationRequest++;
    _isLoading = false;
    _isGenerating = false;
    _isSaving = false;
    _errorMessage = null;
    _currentReportCard = null;
    _classReportCards = [];
    notifyListeners();
    debugPrint('🧹 [ReportCardProvider] Provider state cleared.');
  }

  Future<List<ReportCardModel>> generateClassReportCards({
    required String token,
    required String classId,
    required String termId,
    required int schoolYear,
  }) async {
    final request = ++_generationRequest;
    _isGenerating = true;
    _errorMessage = null;
    _classReportCards = [];
    notifyListeners();

    try {
      final result = await service.generateClassReportCards(
        token: token,
        classId: classId,
        termId: termId,
        schoolYear: schoolYear,
      );

      if (request == _generationRequest) _classReportCards = result;
      return result;
    } catch (e) {
      if (request == _generationRequest) _errorMessage = e.toString();
      rethrow;
    } finally {
      if (request == _generationRequest) {
        _isGenerating = false;
        notifyListeners();
      }
    }
  }

  Future<ReportCardModel?> fetchStudentReportCard({
    required String token,
    required String classId,
    required String termId,
    required int schoolYear,
    required String studentId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await service.getStudentReportCard(
        token: token,
        classId: classId,
        termId: termId,
        schoolYear: schoolYear,
        studentId: studentId,
      );

      _currentReportCard = result;
      _upsertReportCardInCache(result);
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<ReportCardModel?> fetchReportCardById({
    required String token,
    required String reportCardId,
  }) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final result = await service.getReportCardById(
        token: token,
        reportCardId: reportCardId,
      );

      _currentReportCard = result;
      _upsertReportCardInCache(result);
      return result;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> updateTeacherSubjectScore({
    required String token,
    required String reportCardId,
    required String subjectId,
    double? score,
    double? testScore,
    double? activityScore,
    double? participationScore,
    String observation = '',
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      await service.updateTeacherSubjectScore(
        token: token,
        reportCardId: reportCardId,
        subjectId: subjectId,
        score: score,
        testScore: testScore,
        activityScore: activityScore,
        participationScore: participationScore,
        observation: observation,
      );

      final recalculated = await service.recalculateReportCardStatus(
        token: token,
        reportCardId: reportCardId,
      );

      _currentReportCard = recalculated;
      _upsertReportCardInCache(recalculated);

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> updateTeacherSubjectDevelopmentalAssessment({
    required String token,
    required String reportCardId,
    required String subjectId,
    required List<DevelopmentalCriterionAssessmentModel> criteria,
    String generalObservation = '',
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await service.updateTeacherSubjectDevelopmentalAssessment(
        token: token,
        reportCardId: reportCardId,
        subjectId: subjectId,
        criteria: criteria,
        generalObservation: generalObservation,
      );

      _currentReportCard = updated;
      _upsertReportCardInCache(updated);

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<bool> recalculateReportCardStatus({
    required String token,
    required String reportCardId,
  }) async {
    _isSaving = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final updated = await service.recalculateReportCardStatus(
        token: token,
        reportCardId: reportCardId,
      );

      _currentReportCard = updated;
      _upsertReportCardInCache(updated);

      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  ReportCardSubjectModel? getEditableSubjectForTeacher(String teacherUserId) {
    if (_currentReportCard == null) return null;

    try {
      return _currentReportCard!.subjects.firstWhere(
        (subject) => subject.teacherId == teacherUserId,
      );
    } catch (_) {
      return null;
    }
  }

  List<ReportCardSubjectModel> getFilledSubjects() {
    if (_currentReportCard == null) return [];
    return _currentReportCard!.subjects.where((e) => e.isFilled).toList();
  }

  List<ReportCardSubjectModel> getPendingSubjects() {
    if (_currentReportCard == null) return [];
    return _currentReportCard!.subjects.where((e) => !e.isFilled).toList();
  }

  int get filledSubjectsCount => getFilledSubjects().length;
  int get pendingSubjectsCount => getPendingSubjects().length;
}
