class GuardianSchoolOption {
  final String schoolPublicId;
  final String schoolId;
  final String schoolName;

  const GuardianSchoolOption({
    required this.schoolPublicId,
    this.schoolId = '',
    required this.schoolName,
  });

  factory GuardianSchoolOption.fromJson(Map<String, dynamic> json) {
    return GuardianSchoolOption(
      schoolPublicId: (json['schoolPublicId'] ?? '').toString(),
      schoolName: (json['schoolName'] ?? '').toString(),
    );
  }
}

class GuardianCandidate {
  final String optionId;
  final String displayName;
  final String relationship;

  const GuardianCandidate({
    required this.optionId,
    required this.displayName,
    required this.relationship,
  });

  factory GuardianCandidate.fromJson(Map<String, dynamic> json) {
    return GuardianCandidate(
      optionId: (json['optionId'] ?? '').toString(),
      displayName: (json['displayName'] ?? '').toString(),
      relationship: (json['relationship'] ?? 'Responsável').toString(),
    );
  }
}

class GuardianFirstAccessStartResult {
  final String status;
  final String challengeId;
  final List<GuardianCandidate> guardians;
  final String message;
  final String? ambiguityType;
  final List<GuardianSchoolOption> candidateSchools;
  final String? schoolPublicId;
  final String? schoolName;

  const GuardianFirstAccessStartResult({
    required this.status,
    required this.challengeId,
    required this.guardians,
    required this.message,
    this.ambiguityType,
    this.candidateSchools = const [],
    this.schoolPublicId,
    this.schoolName,
  });

  bool get isChallengeStarted => status == 'challenge_started';
  bool get requiresSchoolSelection =>
      status == 'student_ambiguous' && candidateSchools.isNotEmpty;
  bool get isStudentAmbiguous => status == 'student_ambiguous';

  factory GuardianFirstAccessStartResult.fromJson(Map<String, dynamic> json) {
    final rawGuardians = json['guardians'] as List<dynamic>? ?? const [];
    final rawCandidateSchools =
        json['candidateSchools'] as List<dynamic>? ?? const [];
    final schoolJson = json['school'] as Map<String, dynamic>? ?? const {};

    return GuardianFirstAccessStartResult(
      status: (json['status'] ??
              ((json['challengeId'] != null) ? 'challenge_started' : ''))
          .toString(),
      challengeId: (json['challengeId'] ?? '').toString(),
      guardians: rawGuardians
          .whereType<Map<String, dynamic>>()
          .map(GuardianCandidate.fromJson)
          .toList(),
      message: (json['message'] ?? '').toString(),
      ambiguityType: json['ambiguityType']?.toString(),
      candidateSchools: rawCandidateSchools
          .whereType<Map<String, dynamic>>()
          .map(GuardianSchoolOption.fromJson)
          .where((school) => school.schoolPublicId.trim().isNotEmpty)
          .toList(),
      schoolPublicId: schoolJson['publicIdentifier']?.toString(),
      schoolName: schoolJson['name']?.toString(),
    );
  }
}

class GuardianVerificationResult {
  final String status;
  final String? verificationToken;
  final String? identifierType;
  final String? identifierMasked;
  final String message;

  const GuardianVerificationResult({
    required this.status,
    required this.verificationToken,
    required this.identifierType,
    required this.identifierMasked,
    required this.message,
  });

  bool get requiresPinCreation => status == 'new_account_requires_pin';
  bool get requiresExistingPin => status == 'existing_account_requires_pin';
  bool get isAlreadyLinked => status == 'student_already_linked';
  bool get requiresPinStep => requiresPinCreation || requiresExistingPin;

  factory GuardianVerificationResult.fromJson(Map<String, dynamic> json) {
    return GuardianVerificationResult(
      status: (json['status'] ??
              ((json['verificationToken'] != null)
                  ? 'new_account_requires_pin'
                  : ''))
          .toString(),
      verificationToken: json['verificationToken']?.toString(),
      identifierType: json['identifierType']?.toString(),
      identifierMasked: json['identifierMasked']?.toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class GuardianPinSetupResult {
  final String status;
  final String identifierType;
  final String identifierMasked;
  final String message;

  const GuardianPinSetupResult({
    required this.status,
    required this.identifierType,
    required this.identifierMasked,
    required this.message,
  });

  factory GuardianPinSetupResult.fromJson(Map<String, dynamic> json) {
    return GuardianPinSetupResult(
      status: (json['status'] ?? '').toString(),
      identifierType: (json['identifierType'] ?? '').toString(),
      identifierMasked: (json['identifierMasked'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class GuardianPinRecoveryStartResult {
  final bool schoolSelectionRequired;
  final String? challengeId;
  final String? verificationToken;
  final int expiresInSeconds;
  final List<GuardianSchoolOption> options;

  const GuardianPinRecoveryStartResult({
    required this.schoolSelectionRequired,
    required this.challengeId,
    required this.verificationToken,
    required this.expiresInSeconds,
    this.options = const [],
  });

  bool get isReadyForPin =>
      !schoolSelectionRequired &&
      (challengeId ?? '').isNotEmpty &&
      (verificationToken ?? '').isNotEmpty;

  factory GuardianPinRecoveryStartResult.fromJson(
    Map<String, dynamic> json,
  ) {
    final rawOptions = json['options'] as List<dynamic>? ?? const [];

    return GuardianPinRecoveryStartResult(
      schoolSelectionRequired: json['schoolSelectionRequired'] == true,
      challengeId: json['challengeId']?.toString(),
      verificationToken: json['verificationToken']?.toString(),
      expiresInSeconds: int.tryParse('${json['expiresInSeconds'] ?? 0}') ?? 0,
      options: rawOptions
          .whereType<Map<String, dynamic>>()
          .map(GuardianSchoolOption.fromJson)
          .where((option) => option.schoolPublicId.trim().isNotEmpty)
          .toList(),
    );
  }
}

class GuardianPinRecoveryResult {
  final String status;
  final String identifierType;
  final String identifierMasked;
  final String message;

  const GuardianPinRecoveryResult({
    required this.status,
    required this.identifierType,
    required this.identifierMasked,
    required this.message,
  });

  bool get isSuccess => status == 'pin_updated';

  factory GuardianPinRecoveryResult.fromJson(Map<String, dynamic> json) {
    return GuardianPinRecoveryResult(
      status: (json['status'] ?? '').toString(),
      identifierType: (json['identifierType'] ?? 'cpf').toString(),
      identifierMasked: (json['identifierMasked'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
    );
  }
}

class GuardianPinRecoveryException implements Exception {
  final String message;
  final String? code;
  final int? statusCode;

  const GuardianPinRecoveryException(
    this.message, {
    this.code,
    this.statusCode,
  });

  bool get isRateLimited =>
      statusCode == 429 || code == 'pin_recovery_rate_limited';

  bool get isExpired =>
      statusCode == 410 || code == 'pin_recovery_challenge_expired';

  /// The recovery proof cannot safely be reused. Start the official flow again
  /// instead of leaving the guardian on a PIN form that will always fail.
  bool get requiresRestart =>
      statusCode == 409 ||
      const {
        'pin_recovery_challenge_used',
        'pin_recovery_challenge_invalid',
        'pin_recovery_scope_changed',
      }.contains(code);

  bool get isTemporarilyUnavailable =>
      statusCode == 503 || code == 'guardian_audit_transaction_unavailable';

  @override
  String toString() => message;
}

class GuardianSession {
  final String token;
  final String identifierType;
  final String identifierMasked;
  final String status;
  final int linkedStudentsCount;
  final String schoolPublicId;
  final String schoolId;
  final String schoolName;
  final List<GuardianLinkedStudent> linkedStudents;
  final GuardianLinkedStudent? defaultStudent;
  final String? selectedStudentId;

  const GuardianSession({
    required this.token,
    required this.identifierType,
    required this.identifierMasked,
    required this.status,
    required this.linkedStudentsCount,
    required this.schoolPublicId,
    required this.schoolId,
    required this.schoolName,
    this.linkedStudents = const [],
    this.defaultStudent,
    this.selectedStudentId,
  });

  bool hasLinkedStudent(String? studentId) {
    final normalizedStudentId = (studentId ?? '').trim();
    if (normalizedStudentId.isEmpty) return false;

    return linkedStudents.any((student) => student.id == normalizedStudentId);
  }

  GuardianSession copyWith({
    String? token,
    String? identifierType,
    String? identifierMasked,
    String? status,
    int? linkedStudentsCount,
    String? schoolPublicId,
    String? schoolId,
    String? schoolName,
    List<GuardianLinkedStudent>? linkedStudents,
    GuardianLinkedStudent? defaultStudent,
    String? selectedStudentId,
    bool clearSelectedStudentId = false,
  }) {
    return GuardianSession(
      token: token ?? this.token,
      identifierType: identifierType ?? this.identifierType,
      identifierMasked: identifierMasked ?? this.identifierMasked,
      status: status ?? this.status,
      linkedStudentsCount: linkedStudentsCount ?? this.linkedStudentsCount,
      schoolPublicId: schoolPublicId ?? this.schoolPublicId,
      schoolId: schoolId ?? this.schoolId,
      schoolName: schoolName ?? this.schoolName,
      linkedStudents: linkedStudents ?? this.linkedStudents,
      defaultStudent: defaultStudent ?? this.defaultStudent,
      selectedStudentId: clearSelectedStudentId
          ? null
          : (selectedStudentId ?? this.selectedStudentId),
    );
  }

  factory GuardianSession.fromLoginJson(
    Map<String, dynamic> json, {
    String? schoolPublicId,
  }) {
    final guardianJson = json['guardian'] as Map<String, dynamic>? ?? const {};
    final schoolJson = json['school'] as Map<String, dynamic>? ?? const {};
    final rawLinkedStudents =
        json['linkedStudents'] as List<dynamic>? ?? const [];
    final linkedStudents = rawLinkedStudents
        .whereType<Map<String, dynamic>>()
        .map(GuardianLinkedStudent.fromJson)
        .toList();
    final defaultStudentJson = json['defaultStudent'] as Map<String, dynamic>?;

    return GuardianSession(
      token: (json['token'] ?? '').toString(),
      identifierType: (guardianJson['identifierType'] ?? 'cpf').toString(),
      identifierMasked: (guardianJson['identifierMasked'] ?? '').toString(),
      status: (guardianJson['status'] ?? 'active').toString(),
      linkedStudentsCount:
          int.tryParse('${guardianJson['linkedStudentsCount'] ?? 0}') ?? 0,
      schoolPublicId:
          (schoolJson['publicIdentifier'] ?? schoolPublicId ?? '').toString(),
      schoolId: (schoolJson['_id'] ??
              schoolJson['id'] ??
              schoolJson['schoolId'] ??
              '')
          .toString(),
      schoolName: (schoolJson['name'] ?? '').toString(),
      linkedStudents: linkedStudents,
      defaultStudent: defaultStudentJson == null
          ? null
          : GuardianLinkedStudent.fromJson(defaultStudentJson),
      selectedStudentId: json['selectedStudentId']?.toString(),
    );
  }

  factory GuardianSession.fromJson(Map<String, dynamic> json) {
    final rawLinkedStudents =
        json['linkedStudents'] as List<dynamic>? ?? const [];
    final linkedStudents = rawLinkedStudents
        .whereType<Map<String, dynamic>>()
        .map(GuardianLinkedStudent.fromJson)
        .toList();
    final defaultStudentJson = json['defaultStudent'] as Map<String, dynamic>?;

    return GuardianSession(
      token: (json['token'] ?? '').toString(),
      identifierType: (json['identifierType'] ?? 'cpf').toString(),
      identifierMasked: (json['identifierMasked'] ?? '').toString(),
      status: (json['status'] ?? 'active').toString(),
      linkedStudentsCount:
          int.tryParse('${json['linkedStudentsCount'] ?? 0}') ?? 0,
      schoolPublicId: (json['schoolPublicId'] ?? '').toString(),
      schoolId: (json['schoolId'] ?? '').toString(),
      schoolName: (json['schoolName'] ?? '').toString(),
      linkedStudents: linkedStudents,
      defaultStudent: defaultStudentJson == null
          ? null
          : GuardianLinkedStudent.fromJson(defaultStudentJson),
      selectedStudentId: json['selectedStudentId']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'token': token,
      'identifierType': identifierType,
      'identifierMasked': identifierMasked,
      'status': status,
      'linkedStudentsCount': linkedStudentsCount,
      'schoolPublicId': schoolPublicId,
      'schoolId': schoolId,
      'schoolName': schoolName,
      'linkedStudents': linkedStudents
          .map(
            (student) => {
              'id': student.id,
              'fullName': student.fullName,
              'relationship': student.relationship,
              'birthDate': student.birthDate?.toIso8601String(),
              'class': student.classInfo == null
                  ? null
                  : {
                      'id': student.classInfo!.id,
                      'name': student.classInfo!.name,
                      'grade': student.classInfo!.grade,
                      'shift': student.classInfo!.shift,
                      'schoolYear': student.classInfo!.schoolYear,
                      'room': student.classInfo!.room,
                    },
              'enrollment': student.enrollment == null
                  ? null
                  : {
                      'id': student.enrollment!.id,
                      'academicYear': student.enrollment!.academicYear,
                      'enrollmentDate':
                          student.enrollment!.enrollmentDate?.toIso8601String(),
                      'status': student.enrollment!.status,
                    },
            },
          )
          .toList(),
      'defaultStudent': defaultStudent == null
          ? null
          : {
              'id': defaultStudent!.id,
              'fullName': defaultStudent!.fullName,
              'relationship': defaultStudent!.relationship,
              'birthDate': defaultStudent!.birthDate?.toIso8601String(),
              'class': defaultStudent!.classInfo == null
                  ? null
                  : {
                      'id': defaultStudent!.classInfo!.id,
                      'name': defaultStudent!.classInfo!.name,
                      'grade': defaultStudent!.classInfo!.grade,
                      'shift': defaultStudent!.classInfo!.shift,
                      'schoolYear': defaultStudent!.classInfo!.schoolYear,
                      'room': defaultStudent!.classInfo!.room,
                    },
              'enrollment': defaultStudent!.enrollment == null
                  ? null
                  : {
                      'id': defaultStudent!.enrollment!.id,
                      'academicYear': defaultStudent!.enrollment!.academicYear,
                      'enrollmentDate': defaultStudent!
                          .enrollment!.enrollmentDate
                          ?.toIso8601String(),
                      'status': defaultStudent!.enrollment!.status,
                    },
            },
      'selectedStudentId': selectedStudentId,
    };
  }
}

class GuardianLoginResult {
  final String status;
  final String message;
  final GuardianSession? session;
  final List<GuardianSchoolOption> candidateSchools;

  const GuardianLoginResult({
    required this.status,
    required this.message,
    this.session,
    this.candidateSchools = const [],
  });

  bool get isAuthenticated => status == 'authenticated' && session != null;
  bool get requiresSchoolSelection =>
      status == 'school_selection_required' && candidateSchools.isNotEmpty;

  factory GuardianLoginResult.fromJson(
    Map<String, dynamic> json, {
    String? schoolPublicId,
  }) {
    final rawCandidateSchools =
        json['candidateSchools'] as List<dynamic>? ?? const [];

    if ((json['token'] ?? '').toString().isNotEmpty) {
      return GuardianLoginResult(
        status: 'authenticated',
        message: (json['message'] ?? '').toString(),
        session:
            GuardianSession.fromLoginJson(json, schoolPublicId: schoolPublicId),
      );
    }

    return GuardianLoginResult(
      status: (json['status'] ?? '').toString(),
      message: (json['message'] ?? '').toString(),
      candidateSchools: rawCandidateSchools
          .whereType<Map<String, dynamic>>()
          .map(GuardianSchoolOption.fromJson)
          .where((school) => school.schoolPublicId.trim().isNotEmpty)
          .toList(),
    );
  }
}

class GuardianStudentClassInfo {
  final String id;
  final String name;
  final String grade;
  final String shift;
  final int? schoolYear;
  final String? room;

  const GuardianStudentClassInfo({
    required this.id,
    required this.name,
    required this.grade,
    required this.shift,
    required this.schoolYear,
    required this.room,
  });

  factory GuardianStudentClassInfo.fromJson(Map<String, dynamic> json) {
    final room = (json['room'] ?? '').toString().trim();
    return GuardianStudentClassInfo(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      grade: (json['grade'] ?? '').toString(),
      shift: (json['shift'] ?? '').toString(),
      schoolYear: int.tryParse('${json['schoolYear'] ?? ''}'),
      room: room.isEmpty ? null : room,
    );
  }
}

class GuardianStudentEnrollmentInfo {
  final String id;
  final int? academicYear;
  final DateTime? enrollmentDate;
  final String? status;

  const GuardianStudentEnrollmentInfo({
    required this.id,
    required this.academicYear,
    required this.enrollmentDate,
    required this.status,
  });

  factory GuardianStudentEnrollmentInfo.fromJson(Map<String, dynamic> json) {
    return GuardianStudentEnrollmentInfo(
      id: (json['id'] ?? '').toString(),
      academicYear: int.tryParse('${json['academicYear'] ?? ''}'),
      enrollmentDate: DateTime.tryParse('${json['enrollmentDate'] ?? ''}'),
      status: json['status']?.toString(),
    );
  }
}

class GuardianLinkedStudent {
  final String id;
  final String fullName;
  final String relationship;
  final DateTime? birthDate;
  final GuardianStudentClassInfo? classInfo;
  final GuardianStudentEnrollmentInfo? enrollment;

  const GuardianLinkedStudent({
    required this.id,
    required this.fullName,
    required this.relationship,
    required this.birthDate,
    required this.classInfo,
    required this.enrollment,
  });

  String get firstName {
    final parts = fullName.trim().split(RegExp(r'\s+'));
    return parts.isEmpty ? fullName : parts.first;
  }

  factory GuardianLinkedStudent.fromJson(Map<String, dynamic> json) {
    return GuardianLinkedStudent(
      id: (json['id'] ?? '').toString(),
      fullName: (json['fullName'] ?? '').toString(),
      relationship: (json['relationship'] ?? 'Responsável').toString(),
      birthDate: DateTime.tryParse('${json['birthDate'] ?? ''}'),
      classInfo: json['class'] is Map<String, dynamic>
          ? GuardianStudentClassInfo.fromJson(
              json['class'] as Map<String, dynamic>,
            )
          : null,
      enrollment: json['enrollment'] is Map<String, dynamic>
          ? GuardianStudentEnrollmentInfo.fromJson(
              json['enrollment'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class GuardianTermInfo {
  final String id;
  final String title;
  final DateTime? startDate;
  final DateTime? endDate;

  const GuardianTermInfo({
    required this.id,
    required this.title,
    required this.startDate,
    required this.endDate,
  });

  factory GuardianTermInfo.fromJson(Map<String, dynamic> json) {
    return GuardianTermInfo(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      startDate: DateTime.tryParse('${json['startDate'] ?? ''}'),
      endDate: DateTime.tryParse('${json['endDate'] ?? ''}'),
    );
  }
}

class GuardianLesson {
  final String id;
  final int dayOfWeek;
  final String weekdayLabel;
  final String startTime;
  final String endTime;
  final String timeLabel;
  final String subjectName;
  final String teacherName;
  final String? room;
  final String className;
  final String grade;
  final String shift;

  const GuardianLesson({
    required this.id,
    required this.dayOfWeek,
    required this.weekdayLabel,
    required this.startTime,
    required this.endTime,
    required this.timeLabel,
    required this.subjectName,
    required this.teacherName,
    required this.room,
    required this.className,
    required this.grade,
    required this.shift,
  });

  factory GuardianLesson.fromJson(Map<String, dynamic> json) {
    final room = (json['room'] ?? '').toString().trim();
    return GuardianLesson(
      id: (json['id'] ?? '').toString(),
      dayOfWeek: int.tryParse('${json['dayOfWeek'] ?? 0}') ?? 0,
      weekdayLabel: (json['weekdayLabel'] ?? '').toString(),
      startTime: (json['startTime'] ?? '').toString(),
      endTime: (json['endTime'] ?? '').toString(),
      timeLabel: (json['timeLabel'] ?? '').toString(),
      subjectName: (json['subjectName'] ?? 'Disciplina').toString(),
      teacherName: (json['teacherName'] ?? 'Professor').toString(),
      room: room.isEmpty ? null : room,
      className: (json['className'] ?? '').toString(),
      grade: (json['grade'] ?? '').toString(),
      shift: (json['shift'] ?? '').toString(),
    );
  }
}

class GuardianWeekScheduleDay {
  final int dayOfWeek;
  final String label;
  final List<GuardianLesson> items;

  const GuardianWeekScheduleDay({
    required this.dayOfWeek,
    required this.label,
    required this.items,
  });

  factory GuardianWeekScheduleDay.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return GuardianWeekScheduleDay(
      dayOfWeek: int.tryParse('${json['dayOfWeek'] ?? 0}') ?? 0,
      label: (json['label'] ?? '').toString(),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(GuardianLesson.fromJson)
          .toList(),
    );
  }
}

class GuardianScheduleSnapshot {
  final GuardianTermInfo? term;
  final GuardianLesson? currentClass;
  final GuardianLesson? nextClass;
  final int todayCount;
  final List<GuardianLesson> today;
  final List<GuardianWeekScheduleDay> week;

  const GuardianScheduleSnapshot({
    required this.term,
    required this.currentClass,
    required this.nextClass,
    required this.todayCount,
    required this.today,
    required this.week,
  });

  bool get hasCurrentClass => currentClass != null;
  bool get hasNextClass => nextClass != null;

  factory GuardianScheduleSnapshot.fromJson(Map<String, dynamic> json) {
    final rawToday = json['today'] as List<dynamic>? ?? const [];
    final rawWeek = json['week'] as List<dynamic>? ?? const [];
    return GuardianScheduleSnapshot(
      term: json['term'] is Map<String, dynamic>
          ? GuardianTermInfo.fromJson(json['term'] as Map<String, dynamic>)
          : null,
      currentClass: json['currentClass'] is Map<String, dynamic>
          ? GuardianLesson.fromJson(
              json['currentClass'] as Map<String, dynamic>,
            )
          : null,
      nextClass: json['nextClass'] is Map<String, dynamic>
          ? GuardianLesson.fromJson(json['nextClass'] as Map<String, dynamic>)
          : null,
      todayCount: int.tryParse('${json['todayCount'] ?? 0}') ?? 0,
      today: rawToday
          .whereType<Map<String, dynamic>>()
          .map(GuardianLesson.fromJson)
          .toList(),
      week: rawWeek
          .whereType<Map<String, dynamic>>()
          .map(GuardianWeekScheduleDay.fromJson)
          .toList(),
    );
  }
}

class GuardianAttendanceRecord {
  final DateTime? date;
  final String status;
  final String absenceState;
  final String label;
  final String observation;
  final DateTime? updatedAt;

  const GuardianAttendanceRecord({
    required this.date,
    required this.status,
    required this.absenceState,
    required this.label,
    required this.observation,
    required this.updatedAt,
  });

  bool get isAbsent => status.toUpperCase() == 'ABSENT';
  bool get isPresent => status.toUpperCase() == 'PRESENT';

  factory GuardianAttendanceRecord.fromJson(Map<String, dynamic> json) {
    return GuardianAttendanceRecord(
      date: DateTime.tryParse('${json['date'] ?? ''}'),
      status: (json['status'] ?? 'PRESENT').toString(),
      absenceState: (json['absenceState'] ?? 'NONE').toString(),
      label: (json['label'] ?? '').toString(),
      observation: (json['observation'] ?? '').toString(),
      updatedAt: DateTime.tryParse('${json['updatedAt'] ?? ''}'),
    );
  }
}

class GuardianAttendanceSummary {
  final int totalRecords;
  final int presentCount;
  final int absentCount;
  final int justifiedAbsences;
  final int pendingJustifications;
  final int rejectedJustifications;
  final int expiredJustifications;
  final double presenceRate;
  final DateTime? lastRecordedAt;
  final int recentAbsences;
  final String attentionLevel;

  const GuardianAttendanceSummary({
    required this.totalRecords,
    required this.presentCount,
    required this.absentCount,
    required this.justifiedAbsences,
    required this.pendingJustifications,
    required this.rejectedJustifications,
    required this.expiredJustifications,
    required this.presenceRate,
    required this.lastRecordedAt,
    required this.recentAbsences,
    required this.attentionLevel,
  });

  factory GuardianAttendanceSummary.fromJson(Map<String, dynamic> json) {
    return GuardianAttendanceSummary(
      totalRecords: int.tryParse('${json['totalRecords'] ?? 0}') ?? 0,
      presentCount: int.tryParse('${json['presentCount'] ?? 0}') ?? 0,
      absentCount: int.tryParse('${json['absentCount'] ?? 0}') ?? 0,
      justifiedAbsences: int.tryParse('${json['justifiedAbsences'] ?? 0}') ?? 0,
      pendingJustifications:
          int.tryParse('${json['pendingJustifications'] ?? 0}') ?? 0,
      rejectedJustifications:
          int.tryParse('${json['rejectedJustifications'] ?? 0}') ?? 0,
      expiredJustifications:
          int.tryParse('${json['expiredJustifications'] ?? 0}') ?? 0,
      presenceRate: double.tryParse('${json['presenceRate'] ?? 0}') ?? 0,
      lastRecordedAt: DateTime.tryParse('${json['lastRecordedAt'] ?? ''}'),
      recentAbsences: int.tryParse('${json['recentAbsences'] ?? 0}') ?? 0,
      attentionLevel: (json['attentionLevel'] ?? 'neutral').toString(),
    );
  }
}

class GuardianAttendanceData {
  final GuardianAttendanceSummary summary;
  final List<GuardianAttendanceRecord> recentRecords;

  const GuardianAttendanceData({
    required this.summary,
    required this.recentRecords,
  });

  factory GuardianAttendanceData.fromJson(Map<String, dynamic> json) {
    final rawRecords = json['recentRecords'] as List<dynamic>? ?? const [];
    return GuardianAttendanceData(
      summary: GuardianAttendanceSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      recentRecords: rawRecords
          .whereType<Map<String, dynamic>>()
          .map(GuardianAttendanceRecord.fromJson)
          .toList(),
    );
  }
}

class GuardianActivityPreview {
  final String id;
  final String title;
  final DateTime? dueDate;
  final String subjectName;
  final String teacherName;
  final String deliveryStatus;

  const GuardianActivityPreview({
    required this.id,
    required this.title,
    required this.dueDate,
    required this.subjectName,
    required this.teacherName,
    required this.deliveryStatus,
  });

  factory GuardianActivityPreview.fromJson(Map<String, dynamic> json) {
    return GuardianActivityPreview(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      dueDate: DateTime.tryParse('${json['dueDate'] ?? ''}'),
      subjectName: (json['subjectName'] ?? '').toString(),
      teacherName: (json['teacherName'] ?? '').toString(),
      deliveryStatus: (json['deliveryStatus'] ?? 'PENDING').toString(),
    );
  }
}

class GuardianActivitiesSummary {
  final int totalActivities;
  final int deliveredCount;
  final int pendingCount;
  final int overdueCount;
  final int recentCount;
  final GuardianActivityPreview? lastActivity;

  const GuardianActivitiesSummary({
    required this.totalActivities,
    required this.deliveredCount,
    required this.pendingCount,
    required this.overdueCount,
    required this.recentCount,
    required this.lastActivity,
  });

  factory GuardianActivitiesSummary.fromJson(Map<String, dynamic> json) {
    return GuardianActivitiesSummary(
      totalActivities: int.tryParse('${json['totalActivities'] ?? 0}') ?? 0,
      deliveredCount: int.tryParse('${json['deliveredCount'] ?? 0}') ?? 0,
      pendingCount: int.tryParse('${json['pendingCount'] ?? 0}') ?? 0,
      overdueCount: int.tryParse('${json['overdueCount'] ?? 0}') ?? 0,
      recentCount: int.tryParse('${json['recentCount'] ?? 0}') ?? 0,
      lastActivity: json['lastActivity'] is Map<String, dynamic>
          ? GuardianActivityPreview.fromJson(
              json['lastActivity'] as Map<String, dynamic>,
            )
          : null,
    );
  }
}

class GuardianActivityItem {
  final String id;
  final String title;
  final String description;
  final DateTime? assignedAt;
  final DateTime? dueDate;
  final DateTime? correctionDate;
  final String status;
  final String workflowState;
  final String subjectName;
  final String teacherName;
  final String deliveryStatus;
  final DateTime? submittedAt;
  final bool isCorrected;
  final DateTime? correctedAt;
  final double? score;
  final String teacherNote;
  final bool isDelivered;
  final bool isPending;
  final bool isOverdue;

  const GuardianActivityItem({
    required this.id,
    required this.title,
    required this.description,
    required this.assignedAt,
    required this.dueDate,
    required this.correctionDate,
    required this.status,
    required this.workflowState,
    required this.subjectName,
    required this.teacherName,
    required this.deliveryStatus,
    required this.submittedAt,
    required this.isCorrected,
    required this.correctedAt,
    required this.score,
    required this.teacherNote,
    required this.isDelivered,
    required this.isPending,
    required this.isOverdue,
  });

  factory GuardianActivityItem.fromJson(Map<String, dynamic> json) {
    return GuardianActivityItem(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      assignedAt: DateTime.tryParse('${json['assignedAt'] ?? ''}'),
      dueDate: DateTime.tryParse('${json['dueDate'] ?? ''}'),
      correctionDate: DateTime.tryParse('${json['correctionDate'] ?? ''}'),
      status: (json['status'] ?? 'ACTIVE').toString(),
      workflowState: (json['workflowState'] ?? 'ACTIVE').toString(),
      subjectName: (json['subjectName'] ?? '').toString(),
      teacherName: (json['teacherName'] ?? '').toString(),
      deliveryStatus: (json['deliveryStatus'] ?? 'PENDING').toString(),
      submittedAt: DateTime.tryParse('${json['submittedAt'] ?? ''}'),
      isCorrected: json['isCorrected'] == true,
      correctedAt: DateTime.tryParse('${json['correctedAt'] ?? ''}'),
      score: double.tryParse('${json['score'] ?? ''}'),
      teacherNote: (json['teacherNote'] ?? '').toString(),
      isDelivered: json['isDelivered'] == true,
      isPending: json['isPending'] == true,
      isOverdue: json['isOverdue'] == true,
    );
  }
}

class GuardianActivitiesData {
  final GuardianActivitiesSummary summary;
  final List<GuardianActivityItem> items;

  const GuardianActivitiesData({
    required this.summary,
    required this.items,
  });

  factory GuardianActivitiesData.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    return GuardianActivitiesData(
      summary: GuardianActivitiesSummary.fromJson(
        json['summary'] as Map<String, dynamic>? ?? const {},
      ),
      items: rawItems
          .whereType<Map<String, dynamic>>()
          .map(GuardianActivityItem.fromJson)
          .toList(),
    );
  }
}

class GuardianPortalHomeData {
  final List<GuardianLinkedStudent> linkedStudents;
  final GuardianLinkedStudent? selectedStudent;
  final GuardianScheduleSnapshot schedule;
  final GuardianAttendanceData attendance;
  final GuardianActivitiesSummary activitiesSummary;

  const GuardianPortalHomeData({
    required this.linkedStudents,
    required this.selectedStudent,
    required this.schedule,
    required this.attendance,
    required this.activitiesSummary,
  });

  factory GuardianPortalHomeData.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['linkedStudents'] as List<dynamic>? ?? const [];
    return GuardianPortalHomeData(
      linkedStudents: rawStudents
          .whereType<Map<String, dynamic>>()
          .map(GuardianLinkedStudent.fromJson)
          .toList(),
      selectedStudent: json['selectedStudent'] is Map<String, dynamic>
          ? GuardianLinkedStudent.fromJson(
              json['selectedStudent'] as Map<String, dynamic>,
            )
          : null,
      schedule: GuardianScheduleSnapshot.fromJson(
        json['schedule'] as Map<String, dynamic>? ?? const {},
      ),
      attendance: GuardianAttendanceData.fromJson(
        json['attendance'] as Map<String, dynamic>? ?? const {},
      ),
      activitiesSummary: GuardianActivitiesSummary.fromJson(
        json['activities'] is Map<String, dynamic>
            ? ((json['activities'] as Map<String, dynamic>)['summary']
                    as Map<String, dynamic>? ??
                const {})
            : const {},
      ),
    );
  }
}

class GuardianScheduleData {
  final List<GuardianLinkedStudent> linkedStudents;
  final GuardianLinkedStudent? selectedStudent;
  final GuardianScheduleSnapshot schedule;

  const GuardianScheduleData({
    required this.linkedStudents,
    required this.selectedStudent,
    required this.schedule,
  });

  factory GuardianScheduleData.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['linkedStudents'] as List<dynamic>? ?? const [];
    return GuardianScheduleData(
      linkedStudents: rawStudents
          .whereType<Map<String, dynamic>>()
          .map(GuardianLinkedStudent.fromJson)
          .toList(),
      selectedStudent: json['selectedStudent'] is Map<String, dynamic>
          ? GuardianLinkedStudent.fromJson(
              json['selectedStudent'] as Map<String, dynamic>,
            )
          : null,
      schedule: GuardianScheduleSnapshot.fromJson(
        json['schedule'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class GuardianAttendanceScreenData {
  final List<GuardianLinkedStudent> linkedStudents;
  final GuardianLinkedStudent? selectedStudent;
  final GuardianAttendanceData attendance;

  const GuardianAttendanceScreenData({
    required this.linkedStudents,
    required this.selectedStudent,
    required this.attendance,
  });

  factory GuardianAttendanceScreenData.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['linkedStudents'] as List<dynamic>? ?? const [];
    return GuardianAttendanceScreenData(
      linkedStudents: rawStudents
          .whereType<Map<String, dynamic>>()
          .map(GuardianLinkedStudent.fromJson)
          .toList(),
      selectedStudent: json['selectedStudent'] is Map<String, dynamic>
          ? GuardianLinkedStudent.fromJson(
              json['selectedStudent'] as Map<String, dynamic>,
            )
          : null,
      attendance: GuardianAttendanceData.fromJson(
        json['attendance'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class GuardianActivitiesScreenData {
  final List<GuardianLinkedStudent> linkedStudents;
  final GuardianLinkedStudent? selectedStudent;
  final GuardianActivitiesData activities;

  const GuardianActivitiesScreenData({
    required this.linkedStudents,
    required this.selectedStudent,
    required this.activities,
  });

  factory GuardianActivitiesScreenData.fromJson(Map<String, dynamic> json) {
    final rawStudents = json['linkedStudents'] as List<dynamic>? ?? const [];
    return GuardianActivitiesScreenData(
      linkedStudents: rawStudents
          .whereType<Map<String, dynamic>>()
          .map(GuardianLinkedStudent.fromJson)
          .toList(),
      selectedStudent: json['selectedStudent'] is Map<String, dynamic>
          ? GuardianLinkedStudent.fromJson(
              json['selectedStudent'] as Map<String, dynamic>,
            )
          : null,
      activities: GuardianActivitiesData.fromJson(
        json['activities'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}
