class ActivityCriteriaTemplateItem {
  final String key;
  final String label;
  final List<String> scale;

  const ActivityCriteriaTemplateItem({
    required this.key,
    required this.label,
    required this.scale,
  });

  factory ActivityCriteriaTemplateItem.fromJson(Map<String, dynamic> json) {
    return ActivityCriteriaTemplateItem(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      scale: (json['scale'] as List? ?? const [])
          .map((item) => '$item')
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false),
    );
  }
}

class ActivityCorrectionCriterionValue {
  final String key;
  final String label;
  final String value;
  final String note;

  const ActivityCorrectionCriterionValue({
    required this.key,
    required this.label,
    required this.value,
    required this.note,
  });

  factory ActivityCorrectionCriterionValue.fromJson(Map<String, dynamic> json) {
    return ActivityCorrectionCriterionValue(
      key: '${json['key'] ?? ''}',
      label: '${json['label'] ?? ''}',
      value: '${json['value'] ?? ''}',
      note: '${json['note'] ?? ''}',
    );
  }

  Map<String, dynamic> toRequestJson() {
    return {
      'key': key,
      'value': value,
      'note': note,
    };
  }
}

class ActivityCorrectionSummary {
  final bool exists;
  final String? id;
  final String status;
  final List<ActivityCorrectionCriterionValue> criteria;
  final String? generalObservation;

  const ActivityCorrectionSummary({
    required this.exists,
    required this.id,
    required this.status,
    required this.criteria,
    required this.generalObservation,
  });

  factory ActivityCorrectionSummary.fromJson(Map<String, dynamic> json) {
    return ActivityCorrectionSummary(
      exists: json['exists'] == true,
      id: json['id']?.toString(),
      status: '${json['status'] ?? 'pending'}',
      criteria: (json['criteria'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ActivityCorrectionCriterionValue.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      generalObservation: json['generalObservation']?.toString(),
    );
  }
}

class ActivityResolveActivityData {
  final String activityPrintRunId;
  final String qrCodePayload;
  final String activityPageId;
  final String bookId;
  final String bookTitle;
  final String activityTitle;
  final int pageNumber;
  final String subject;
  final String? printDate;

  const ActivityResolveActivityData({
    required this.activityPrintRunId,
    required this.qrCodePayload,
    required this.activityPageId,
    required this.bookId,
    required this.bookTitle,
    required this.activityTitle,
    required this.pageNumber,
    required this.subject,
    required this.printDate,
  });

  factory ActivityResolveActivityData.fromJson(Map<String, dynamic> json) {
    return ActivityResolveActivityData(
      activityPrintRunId: '${json['activityPrintRunId'] ?? ''}',
      qrCodePayload: '${json['qrCodePayload'] ?? ''}',
      activityPageId: '${json['activityPageId'] ?? ''}',
      bookId: '${json['bookId'] ?? ''}',
      bookTitle: '${json['bookTitle'] ?? ''}',
      activityTitle: '${json['activityTitle'] ?? ''}',
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 0,
      subject: '${json['subject'] ?? ''}',
      printDate: json['printDate']?.toString(),
    );
  }
}

class ActivityResolveNamedEntity {
  final String id;
  final String name;

  const ActivityResolveNamedEntity({
    required this.id,
    required this.name,
  });

  factory ActivityResolveNamedEntity.fromJson(Map<String, dynamic> json) {
    return ActivityResolveNamedEntity(
      id: '${json['id'] ?? ''}',
      name: '${json['name'] ?? ''}',
    );
  }
}

class ActivityQrResolveResult {
  final String type;
  final ActivityResolveActivityData activity;
  final ActivityResolveNamedEntity student;
  final ActivityResolveNamedEntity classInfo;
  final ActivityResolveNamedEntity teacher;
  final ActivityCorrectionSummary correction;
  final List<ActivityCriteriaTemplateItem> criteriaTemplate;

  const ActivityQrResolveResult({
    required this.type,
    required this.activity,
    required this.student,
    required this.classInfo,
    required this.teacher,
    required this.correction,
    required this.criteriaTemplate,
  });

  factory ActivityQrResolveResult.fromJson(Map<String, dynamic> json) {
    return ActivityQrResolveResult(
      type: '${json['type'] ?? 'activity'}',
      activity: ActivityResolveActivityData.fromJson(
        Map<String, dynamic>.from(json['activity'] as Map? ?? const {}),
      ),
      student: ActivityResolveNamedEntity.fromJson(
        Map<String, dynamic>.from(json['student'] as Map? ?? const {}),
      ),
      classInfo: ActivityResolveNamedEntity.fromJson(
        Map<String, dynamic>.from(json['class'] as Map? ?? const {}),
      ),
      teacher: ActivityResolveNamedEntity.fromJson(
        Map<String, dynamic>.from(json['teacher'] as Map? ?? const {}),
      ),
      correction: ActivityCorrectionSummary.fromJson(
        Map<String, dynamic>.from(json['correction'] as Map? ?? const {}),
      ),
      criteriaTemplate: (json['criteriaTemplate'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ActivityCriteriaTemplateItem.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
    );
  }
}

class ActivityCorrectionRecord {
  final String id;
  final String status;
  final String qrCodePayload;
  final String studentId;
  final String activityPageId;
  final String activityBookId;
  final List<ActivityCorrectionCriterionValue> criteria;
  final String generalObservation;
  final DateTime? correctedAt;

  const ActivityCorrectionRecord({
    required this.id,
    required this.status,
    required this.qrCodePayload,
    required this.studentId,
    required this.activityPageId,
    required this.activityBookId,
    required this.criteria,
    required this.generalObservation,
    required this.correctedAt,
  });

  factory ActivityCorrectionRecord.fromJson(Map<String, dynamic> json) {
    return ActivityCorrectionRecord(
      id: '${json['id'] ?? ''}',
      status: '${json['status'] ?? 'corrected'}',
      qrCodePayload: '${json['qrCodePayload'] ?? ''}',
      studentId: '${json['studentId'] ?? ''}',
      activityPageId: '${json['activityPageId'] ?? ''}',
      activityBookId: '${json['activityBookId'] ?? ''}',
      criteria: (json['criteria'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ActivityCorrectionCriterionValue.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
      generalObservation: '${json['generalObservation'] ?? ''}',
      correctedAt: DateTime.tryParse('${json['correctedAt'] ?? ''}'),
    );
  }
}

class ActivityCorrectionPrintRunStudent {
  final String studentId;
  final String studentName;
  final String qrCodePayload;
  final int pageNumber;
  final String status;

  const ActivityCorrectionPrintRunStudent({
    required this.studentId,
    required this.studentName,
    required this.qrCodePayload,
    required this.pageNumber,
    required this.status,
  });

  factory ActivityCorrectionPrintRunStudent.fromJson(
      Map<String, dynamic> json) {
    return ActivityCorrectionPrintRunStudent(
      studentId: '${json['studentId'] ?? ''}',
      studentName: '${json['studentName'] ?? ''}',
      qrCodePayload: '${json['qrCodePayload'] ?? ''}',
      pageNumber: (json['pageNumber'] as num?)?.toInt() ?? 1,
      status: '${json['status'] ?? 'pending'}',
    );
  }

  bool get isPending => status == 'pending';
}

class ActivityCorrectionPrintRun {
  final String id;
  final String activityPageId;
  final String bookTitle;
  final String activityTitle;
  final String subject;
  final String? printDate;
  final int totalStudents;
  final int pendingCount;
  final int correctedCount;
  final List<ActivityCorrectionPrintRunStudent> students;

  const ActivityCorrectionPrintRun({
    required this.id,
    required this.activityPageId,
    required this.bookTitle,
    required this.activityTitle,
    required this.subject,
    required this.printDate,
    required this.totalStudents,
    required this.pendingCount,
    required this.correctedCount,
    required this.students,
  });

  factory ActivityCorrectionPrintRun.fromJson(Map<String, dynamic> json) {
    return ActivityCorrectionPrintRun(
      id: '${json['id'] ?? ''}',
      activityPageId: '${json['activityPageId'] ?? ''}',
      bookTitle: '${json['bookTitle'] ?? ''}',
      activityTitle: '${json['activityTitle'] ?? ''}',
      subject: '${json['subject'] ?? ''}',
      printDate: json['printDate']?.toString(),
      totalStudents: (json['totalStudents'] as num?)?.toInt() ?? 0,
      pendingCount: (json['pendingCount'] as num?)?.toInt() ?? 0,
      correctedCount: (json['correctedCount'] as num?)?.toInt() ?? 0,
      students: (json['students'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => ActivityCorrectionPrintRunStudent.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(growable: false),
    );
  }
}
