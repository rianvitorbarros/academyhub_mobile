import 'dart:convert';
import 'package:academyhub_mobile/model/report_card_exam_import_model.dart';
import 'package:academyhub_mobile/model/report_card_model.dart';
import 'package:academyhub_mobile/config/api_client.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

void _logExamMobile(String tag, Map<String, Object?> data) {
  if (!kDebugMode) return;
  debugPrint('[ExamMobile][$tag] ${jsonEncode(data)}');
}

class ReportCardService {
  final String baseUrl;
  int lastExamListResponseBytes = 0;
  int lastExamListHttpDurationMs = 0;

  ReportCardService({
    required this.baseUrl,
  });

  Map<String, String> _headers(String token) {
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, dynamic>? queryParams]) {
    final uri = Uri.parse('$baseUrl$path');

    if (queryParams == null || queryParams.isEmpty) return uri;

    return uri.replace(
      queryParameters: queryParams.map(
        (key, value) => MapEntry(key, value?.toString() ?? ''),
      ),
    );
  }

  Future<List<ReportCardModel>> generateClassReportCards({
    required String token,
    required String classId,
    required String termId,
    required int schoolYear,
  }) async {
    final response = await ApiClient.post(
      _uri('/api/report-cards/generate'),
      headers: _headers(token),
      body: jsonEncode({
        'classId': classId,
        'termId': termId,
        'schoolYear': schoolYear,
      }),
    );

    final data = _decodeResponse(response);

    final list = (data['data'] as List<dynamic>? ?? [])
        .map((e) => ReportCardModel.fromJson(e))
        .toList();

    return list;
  }

  Future<ReportCardModel> getStudentReportCard({
    required String token,
    required String classId,
    required String termId,
    required int schoolYear,
    required String studentId,
  }) async {
    final response = await ApiClient.get(
      _uri('/api/report-cards/student', {
        'classId': classId,
        'termId': termId,
        'schoolYear': schoolYear,
        'studentId': studentId,
      }),
      headers: _headers(token),
    );

    final data = _decodeResponse(response);
    return ReportCardModel.fromJson(data['data']);
  }

  Future<ReportCardModel> getReportCardById({
    required String token,
    required String reportCardId,
  }) async {
    final response = await ApiClient.get(
      _uri('/api/report-cards/$reportCardId'),
      headers: _headers(token),
    );

    final data = _decodeResponse(response);
    return ReportCardModel.fromJson(data['data']);
  }

  Future<ReportCardModel> updateTeacherSubjectScore({
    required String token,
    required String reportCardId,
    required String subjectId,
    double? score,
    double? testScore,
    double? activityScore,
    double? participationScore,
    String observation = '',
  }) async {
    final bodyData = <String, dynamic>{
      'observation': observation,
    };
    if (score != null) bodyData['score'] = score;
    if (testScore != null) bodyData['testScore'] = testScore;
    if (activityScore != null) bodyData['activityScore'] = activityScore;
    if (participationScore != null) {
      bodyData['participationScore'] = participationScore;
    }

    final response = await ApiClient.patch(
      _uri('/api/report-cards/$reportCardId/subjects/$subjectId/score'),
      headers: _headers(token),
      body: jsonEncode(bodyData),
    );

    final data = _decodeResponse(response);
    return ReportCardModel.fromJson(data['data']);
  }

  Future<ReportCardModel> updateTeacherSubjectDevelopmentalAssessment({
    required String token,
    required String reportCardId,
    required String subjectId,
    required List<DevelopmentalCriterionAssessmentModel> criteria,
    String generalObservation = '',
  }) async {
    final response = await ApiClient.patch(
      _uri(
        '/api/report-cards/$reportCardId/subjects/$subjectId/developmental-assessment',
      ),
      headers: _headers(token),
      body: jsonEncode({
        'criteria': criteria.map((item) => item.toJson()).toList(),
        'generalObservation': generalObservation,
      }),
    );

    final data = _decodeResponse(response);
    return ReportCardModel.fromJson(data['data']);
  }

  Future<ReportCardModel> recalculateReportCardStatus({
    required String token,
    required String reportCardId,
  }) async {
    final response = await ApiClient.patch(
      _uri('/api/report-cards/$reportCardId/recalculate-status'),
      headers: _headers(token),
    );

    final data = _decodeResponse(response);
    return ReportCardModel.fromJson(data['data']);
  }

  Future<List<ImportableExamModel>> listImportableExams({
    required String token,
    required String classId,
    String? termId,
    String? subjectId,
    int? requestId,
  }) async {
    final url = _uri('/api/report-cards/import/exams', {
      'classId': classId,
      if (termId != null && termId.isNotEmpty) 'termId': termId,
      if (subjectId != null && subjectId.isNotEmpty) 'subjectId': subjectId,
      if (requestId != null) 'requestId': requestId,
      if (kDebugMode) 'perf': 'true',
    });
    final stopwatch = Stopwatch()..start();
    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][HttpStart] ${jsonEncode({
            'requestId': requestId,
            'method': 'GET',
            'url': url.toString(),
            'screen': 'TeacherExams',
          })}');
    }
    final response = await ApiClient.get(
      url,
      headers: _headers(token),
    );
    stopwatch.stop();
    lastExamListResponseBytes = response.bodyBytes.length;
    lastExamListHttpDurationMs = stopwatch.elapsedMilliseconds;

    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][HttpEnd] ${jsonEncode({
            'requestId': requestId,
            'method': 'GET',
            'url': url.toString(),
            'status': response.statusCode,
            'durationMs': stopwatch.elapsedMilliseconds,
            'responseBytes': response.bodyBytes.length,
            'screen': 'TeacherExams',
          })}');
    }

    _logExamMobile('HttpTiming', {
      'method': 'GET',
      'url': url.toString(),
      'status': response.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'screen': 'ExamList',
    });

    final parseStopwatch = Stopwatch()..start();
    final data = _decodeResponse(response);
    final items = (data['data'] as List<dynamic>? ?? [])
        .whereType<Map>()
        .map((item) =>
            ImportableExamModel.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    parseStopwatch.stop();

    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][ParseEnd] ${jsonEncode({
            'requestId': requestId,
            'items': items.length,
            'durationMs': parseStopwatch.elapsedMilliseconds,
          })}');
    }

    _logExamMobile('ExamListResponse', {
      'durationMs': stopwatch.elapsedMilliseconds,
      'total': items.length,
      'items': items
          .map((exam) => {
                'examId': exam.examId,
                'title': exam.title,
                'classId': exam.classId,
                'className': exam.className,
                'subjectId': exam.subjectId,
                'subjectName': exam.subjectName,
                'termId': exam.termId,
                'termName': exam.termName,
                'sheetsCount': exam.totalSheets,
                'correctedCount': exam.correctedSheets,
                'pendingCount': exam.pendingCount,
                'importableCount': exam.importableCount,
                'conflictsCount': exam.conflictCount,
                'blockedCount': exam.blockedCount,
                'alreadyImportedCount': exam.alreadyImportedCount,
                'scoreMode': exam.scoreMode,
                'importSummaryError': exam.importSummaryError,
              })
          .toList(),
    });

    return items;
  }

  Future<ReportCardExamImportPreview> previewExamImport({
    required String token,
    required String examId,
    required String classId,
    required String subjectId,
    required String termId,
    String? targetAcademicYearId,
    String scoreMode = 'raw',
    int? requestId,
  }) async {
    final url = _uri('/api/report-cards/import/exams/$examId/preview', {
      'classId': classId,
      'subjectId': subjectId,
      'termId': termId,
      if (targetAcademicYearId != null && targetAcademicYearId.isNotEmpty)
        'targetAcademicYearId': targetAcademicYearId,
      'scoreMode': scoreMode,
      if (requestId != null) 'requestId': requestId,
      if (kDebugMode) 'perf': 'true',
    });
    final stopwatch = Stopwatch()..start();
    final response = await ApiClient.get(
      url,
      headers: _headers(token),
    );
    stopwatch.stop();

    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][ExamResultHttpEnd] ${jsonEncode({
            'endpoint': 'preview',
            'examId': examId,
            'url': url.toString(),
            'status': response.statusCode,
            'durationMs': stopwatch.elapsedMilliseconds,
            'responseBytes': response.bodyBytes.length,
          })}');
    }

    _logExamMobile('HttpTiming', {
      'method': 'GET',
      'url': url.toString(),
      'status': response.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'screen': 'ExamResult',
    });

    final parseStopwatch = Stopwatch()..start();
    final data = _decodeResponse(response);
    final preview = ReportCardExamImportPreview.fromJson(
      Map<String, dynamic>.from(data['data'] as Map),
    );
    parseStopwatch.stop();
    if (kDebugMode) {
      debugPrint('[ExamPerfMobile][ExamResultParseEnd] ${jsonEncode({
            'endpoint': 'preview',
            'examId': examId,
            'students': preview.items.length,
            'durationMs': parseStopwatch.elapsedMilliseconds,
          })}');
    }
    final blockedReasons = <String, int>{};
    for (final item in preview.items.where((item) => item.isBlocked)) {
      final reason = item.missingReportCardDiagnosis?.trim().isNotEmpty == true
          ? item.missingReportCardDiagnosis!.trim()
          : item.blockReason;
      blockedReasons[reason] = (blockedReasons[reason] ?? 0) + 1;
    }
    _logExamMobile('PreviewResponse', {
      'examId': preview.exam.examId,
      'targetClassName': preview.target.className,
      'targetTermName': preview.target.termName,
      'total': preview.summary.totalStudents,
      'fill': preview.summary.importableCount,
      'same': preview.summary.noopCount,
      'conflicts': preview.summary.conflictCount,
      'pending': preview.summary.pendingCount,
      'blocked': preview.summary.blockedCount,
      'blockedReasons': blockedReasons,
    });
    _logExamMobile('ExamResultSummary', {
      'examId': preview.exam.examId,
      'title': preview.exam.title,
      'className': preview.exam.className,
      'subjectName': preview.exam.subjectName,
      'termName': preview.exam.termName,
      'importable': preview.summary.importableCount,
      'conflicts': preview.summary.conflictCount,
      'blocked': preview.summary.blockedCount,
      'alreadyImported': preview.summary.noopCount,
      'pending': preview.summary.pendingCount,
      'studentsTotal': preview.summary.totalStudents,
      'scoreMode': preview.target.scoreMode,
      'canCommit': preview.canCommit,
    });
    for (final item in preview.items) {
      _logExamMobile('ExamResultStudent', {
        'studentId': item.studentId,
        'studentName': item.studentName,
        'sheetId': item.sheetId,
        'status': item.status,
        'score': item.examGrade,
        'maxScore': item.examMaxGrade,
        'isCorrected': item.correctionStatus == 'corrected',
        'isImportable': item.isImportable,
        'isAlreadyImported': item.isAlreadyImported,
        'isBlocked': item.isBlocked,
        'blockReason': item.isBlocked ? item.blockReason : null,
        'missingReportCardDiagnosis': item.missingReportCardDiagnosis,
        'conflictReason': item.isConflict ? item.message : null,
        'gradebookEntryId': item.reportCardId,
        'assessmentId': null,
        'targetClassId': preview.target.classId,
        'targetSubjectId': preview.target.subjectId,
        'targetTermId': preview.target.termId,
      });
    }
    return preview;
  }

  Future<ReportCardExamImportCommitResult> commitExamImport({
    required String token,
    required String examId,
    required String classId,
    required String subjectId,
    required String termId,
    String? targetAcademicYearId,
    required List<String> selectedStudentIds,
    required Map<String, dynamic> conflictDecisions,
    required String reason,
    String scoreMode = 'raw',
  }) async {
    final url = _uri('/api/report-cards/import/exams/$examId/commit');
    final stopwatch = Stopwatch()..start();
    final response = await ApiClient.post(
      url,
      headers: _headers(token),
      body: jsonEncode({
        'classId': classId,
        'subjectId': subjectId,
        'termId': termId,
        if (targetAcademicYearId != null && targetAcademicYearId.isNotEmpty)
          'targetAcademicYearId': targetAcademicYearId,
        'selectedStudentIds': selectedStudentIds,
        'conflictDecisions': conflictDecisions,
        'reason': reason,
        'scoreMode': scoreMode,
      }),
    );
    stopwatch.stop();

    _logExamMobile('HttpTiming', {
      'method': 'POST',
      'url': url.toString(),
      'status': response.statusCode,
      'durationMs': stopwatch.elapsedMilliseconds,
      'screen': 'ExamImportCommit',
    });

    final data = _decodeResponse(response);
    return ReportCardExamImportCommitResult.fromJson(
      Map<String, dynamic>.from(data['data'] as Map),
    );
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    final body = jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body as Map<String, dynamic>;
    }

    final message =
        (body is Map<String, dynamic> ? body['message'] : null)?.toString() ??
            'Erro ao processar a requisição.';
    throw Exception(message);
  }
}
