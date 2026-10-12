import 'dart:convert';
import 'dart:math';
import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../model/attendance_model.dart';
import '../model/class_model.dart';

class PendingAttendanceOperation {
  final String operationId;
  final String userId;
  final String schoolId;
  final String classId;
  final String date;
  final int baseVersion;
  final DateTime createdAt;
  final List<Map<String, dynamic>> records;
  final String state;
  final String? lastError;

  const PendingAttendanceOperation({
    required this.operationId,
    required this.userId,
    required this.schoolId,
    required this.classId,
    required this.date,
    required this.baseVersion,
    required this.createdAt,
    required this.records,
    this.state = 'pending',
    this.lastError,
  });

  factory PendingAttendanceOperation.fromJson(Map<String, dynamic> json) =>
      PendingAttendanceOperation(
        operationId: json['operationId'].toString(),
        userId: json['userId'].toString(),
        schoolId: json['schoolId'].toString(),
        classId: json['classId'].toString(),
        date: json['date'].toString(),
        baseVersion: int.tryParse(json['baseVersion'].toString()) ?? 0,
        createdAt: DateTime.parse(json['createdAt'].toString()),
        records: (json['records'] as List)
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList(),
        state: json['state']?.toString() ?? 'pending',
        lastError: json['lastError']?.toString(),
      );

  Map<String, dynamic> toJson() => {
        'operationId': operationId,
        'userId': userId,
        'schoolId': schoolId,
        'classId': classId,
        'date': date,
        'baseVersion': baseVersion,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'records': records,
        'state': state,
        if (lastError != null) 'lastError': lastError,
      };

  PendingAttendanceOperation withFailure(String error,
          {bool conflict = false}) =>
      PendingAttendanceOperation(
        operationId: operationId,
        userId: userId,
        schoolId: schoolId,
        classId: classId,
        date: date,
        baseVersion: baseVersion,
        createdAt: createdAt,
        records: records,
        state: conflict ? 'conflict' : 'pending',
        lastError: error,
      );
}

class OfflineAttendanceStore {
  OfflineAttendanceStore._();
  static final instance = OfflineAttendanceStore._();
  final StreamController<void> _queueChanges =
      StreamController<void>.broadcast();
  Stream<void> get queueChanges => _queueChanges.stream;

  String? _userId;
  String? _schoolId;
  String? get userId => _userId;
  String? get schoolId => _schoolId;
  bool get isActive => _userId != null && _schoolId != null;

  void activate({required String userId, required String schoolId}) {
    _userId = userId;
    _schoolId = schoolId;
  }

  void deactivate() {
    _userId = null;
    _schoolId = null;
  }

  String get _prefix {
    if (!isActive) throw StateError('Cache offline sem identidade ativa.');
    return 'attendance_offline_v1.${_schoolId!}.${_userId!}';
  }

  String _day(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  Future<void> saveClasses(
    List<ClassModel> classes, {
    String scope = 'all',
  }) async {
    if (!isActive) return;
    final key = '$_prefix.classes.${_safeScope(scope)}';
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode(classes
          .map((item) => {
                ...item.toJson(),
                '_id': item.id,
                'studentCount': item.studentCount,
              })
          .toList()),
    );
  }

  Future<List<ClassModel>> loadClasses({String scope = 'all'}) async {
    if (!isActive) return [];
    final prefix = _prefix;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$prefix.classes.${_safeScope(scope)}') ??
        (scope == 'all' ? prefs.getString('$prefix.classes') : null);
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) =>
              ClassModel.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _safeScope(String value) {
    final normalized = value.trim().replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    return normalized.isEmpty ? 'all' : normalized;
  }

  Future<void> saveSheet(AttendanceSheet sheet) async {
    if (!isActive) return;
    final prefs = await SharedPreferences.getInstance();
    final serialized = jsonEncode(sheet.toJson(includeLocal: true));
    await prefs.setString(
        '$_prefix.sheet.${sheet.classId}.${_day(sheet.date)}', serialized);
    await prefs.setString('$_prefix.roster.${sheet.classId}', serialized);
  }

  Future<AttendanceSheet?> loadSheet(String classId, DateTime date) async {
    if (!isActive) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix.sheet.$classId.${_day(date)}');
    if (raw == null) {
      final rosterRaw = prefs.getString('$_prefix.roster.$classId');
      if (rosterRaw == null) return null;
      try {
        final roster = Map<String, dynamic>.from(jsonDecode(rosterRaw));
        roster
          ..remove('_id')
          ..remove('updatedAt')
          ..['date'] = _day(date)
          ..['version'] = 0;
        roster['records'] = (roster['records'] as List).map((item) {
          final record = Map<String, dynamic>.from(item as Map);
          record['status'] = 'PRESENT';
          record['observation'] = '';
          return record;
        }).toList();
        return AttendanceSheet.fromJson(roster);
      } catch (_) {
        return null;
      }
    }
    try {
      return AttendanceSheet.fromJson(
          Map<String, dynamic>.from(jsonDecode(raw)));
    } catch (_) {
      return null;
    }
  }

  Future<PendingAttendanceOperation> enqueue(AttendanceSheet sheet) async {
    final items = await pendingOperations();
    final dateKey = _day(sheet.date);
    // Um novo envio desta chamada e a revisao explicita do conflito local.
    // A API ainda exige a baseVersion correta antes de aceitar a substituicao.
    items.removeWhere((item) =>
        item.classId == sheet.classId &&
        item.date == dateKey &&
        item.state == 'conflict');
    final queuedVersions = items
        .where(
          (item) =>
              item.classId == sheet.classId &&
              item.date == dateKey &&
              item.state != 'conflict',
        )
        .length;
    final operation = PendingAttendanceOperation(
      operationId: _newId(),
      userId: _userId!,
      schoolId: _schoolId!,
      classId: sheet.classId,
      date: dateKey,
      baseVersion: sheet.version + queuedVersions,
      createdAt: DateTime.now(),
      records: sheet.records.map((record) => record.toJson()).toList(),
    );
    items.add(operation);
    await _writeQueue(items);
    await saveSheet(sheet);
    return operation;
  }

  Future<List<PendingAttendanceOperation>> pendingOperations() async {
    if (!isActive) return [];
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_prefix.queue');
    if (raw == null) return [];
    try {
      return (jsonDecode(raw) as List)
          .map((item) => PendingAttendanceOperation.fromJson(
              Map<String, dynamic>.from(item as Map)))
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> removeOperation(String operationId) async {
    final items = await pendingOperations();
    items.removeWhere((item) => item.operationId == operationId);
    await _writeQueue(items);
  }

  Future<void> markFailure(String operationId, String error,
      {bool conflict = false}) async {
    final items = await pendingOperations();
    final index = items.indexWhere((item) => item.operationId == operationId);
    if (index >= 0) {
      items[index] = items[index].withFailure(error, conflict: conflict);
    }
    await _writeQueue(items);
  }

  Future<void> _writeQueue(List<PendingAttendanceOperation> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix.queue',
        jsonEncode(items.map((item) => item.toJson()).toList()));
    _queueChanges.add(null);
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return '${DateTime.now().microsecondsSinceEpoch}-${bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';
  }
}
