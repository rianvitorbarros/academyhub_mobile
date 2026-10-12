import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class ReportCardFilterStore {
  static String _key(String userId, String schoolId) =>
      'report_cards.filters.v2.$schoolId.$userId';

  static Future<Map<String, String>> load({
    required String userId,
    required String schoolId,
  }) async {
    if (userId.isEmpty || schoolId.isEmpty) return const {};
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(userId, schoolId));
    if (raw == null) return const {};
    try {
      final values = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return values.map((key, value) => MapEntry(key, value.toString()));
    } catch (_) {
      return const {};
    }
  }

  static Future<void> save({
    required String userId,
    required String schoolId,
    required String year,
    required String term,
    required String classId,
    required String status,
  }) async {
    if (userId.isEmpty || schoolId.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key(userId, schoolId),
      jsonEncode({
        'year': year,
        'term': term,
        'classId': classId,
        'status': status,
      }),
    );
  }
}
