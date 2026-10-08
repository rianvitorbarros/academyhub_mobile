class ReEnrollmentClassSummary {
  final String? id;
  final String name;
  final String grade;
  final String shift;
  const ReEnrollmentClassSummary(
      {this.id, this.name = '', this.grade = '', this.shift = ''});
  factory ReEnrollmentClassSummary.fromJson(dynamic value) {
    final json = value is Map
        ? Map<String, dynamic>.from(value)
        : const <String, dynamic>{};
    return ReEnrollmentClassSummary(
        id: json['id']?.toString(),
        name: json['name']?.toString() ?? '',
        grade: json['grade']?.toString() ?? '',
        shift: json['shift']?.toString() ?? '');
  }
}

class GuardianReEnrollmentItem {
  final String studentId;
  final String studentName;
  final int targetAcademicYear;
  final String eligibility;
  final ReEnrollmentClassSummary? currentClass;
  final ReEnrollmentClassSummary? targetClass;
  final String targetGrade;
  final String targetLevel;
  final String targetShift;
  final int? publishedMonthlyFeeCents;
  final int? pricingVersion;
  final Map<String, dynamic>? request;
  const GuardianReEnrollmentItem(
      {required this.studentId,
      required this.studentName,
      required this.targetAcademicYear,
      required this.eligibility,
      this.currentClass,
      this.targetClass,
      this.targetGrade = '',
      this.targetLevel = '',
      this.targetShift = '',
      this.publishedMonthlyFeeCents,
      this.pricingVersion,
      this.request});
  factory GuardianReEnrollmentItem.fromJson(Map<String, dynamic> json) {
    final student = json['student'] is Map
        ? Map<String, dynamic>.from(json['student'])
        : const <String, dynamic>{};
    final enrollment = json['currentEnrollment'] is Map
        ? Map<String, dynamic>.from(json['currentEnrollment'])
        : const <String, dynamic>{};
    final grade = json['suggestedNextGrade'] is Map
        ? Map<String, dynamic>.from(json['suggestedNextGrade'])
        : const <String, dynamic>{};
    return GuardianReEnrollmentItem(
        studentId: student['id']?.toString() ?? '',
        studentName: student['fullName']?.toString() ?? '',
        targetAcademicYear: (json['targetAcademicYear'] as num?)?.toInt() ?? 0,
        eligibility: json['eligibility']?.toString() ?? 'UNAVAILABLE',
        currentClass: enrollment['class'] == null
            ? null
            : ReEnrollmentClassSummary.fromJson(enrollment['class']),
        targetClass: json['suggestedNextClass'] == null
            ? null
            : ReEnrollmentClassSummary.fromJson(json['suggestedNextClass']),
        targetGrade: grade['grade']?.toString() ?? '',
        targetLevel:
            json['targetLevel']?.toString() ?? grade['level']?.toString() ?? '',
        targetShift:
            json['targetShift']?.toString() ?? grade['shift']?.toString() ?? '',
        publishedMonthlyFeeCents:
            (json['publishedMonthlyFeeCents'] as num?)?.toInt(),
        pricingVersion: (json['pricingVersion'] as num?)?.toInt(),
        request: json['request'] is Map
            ? Map<String, dynamic>.from(json['request'])
            : null);
  }
  bool get canRequest => eligibility == 'ELIGIBLE';
  bool get financialBlocked => eligibility == 'FINANCIAL_BLOCK';
  bool get progressionMissing =>
      eligibility == 'NO_ACADEMIC_PROGRESSION' ||
      eligibility == 'TERMINAL_PROGRESSION';
  String get rejectionReason =>
      request?['rejectionReason']?.toString().trim() ?? '';
  bool get enrollmentEffectivated => request?['approvalEnrollmentId'] != null;
  String get targetLabel =>
      targetClass?.name.isNotEmpty == true ? targetClass!.name : targetGrade;
  String get formattedMonthlyFee {
    final cents = publishedMonthlyFeeCents;
    if (cents == null) return '';
    final value = cents / 100;
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }
}

class GuardianReEnrollmentEligibility {
  final int? academicYearTo;
  final List<GuardianReEnrollmentItem> items;
  const GuardianReEnrollmentEligibility(
      {this.academicYearTo, this.items = const []});
  factory GuardianReEnrollmentEligibility.fromJson(Map<String, dynamic> json) {
    final period = json['period'] is Map
        ? Map<String, dynamic>.from(json['period'])
        : const <String, dynamic>{};
    final items = json['items'] is List
        ? (json['items'] as List)
            .whereType<Map>()
            .map((e) =>
                GuardianReEnrollmentItem.fromJson(Map<String, dynamic>.from(e)))
            .toList()
        : <GuardianReEnrollmentItem>[];
    return GuardianReEnrollmentEligibility(
        academicYearTo: (period['academicYearTo'] as num?)?.toInt(),
        items: items);
  }
}
