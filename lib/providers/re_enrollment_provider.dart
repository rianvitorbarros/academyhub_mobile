import 'package:academyhub_mobile/model/re_enrollment_model.dart';
import 'package:academyhub_mobile/services/re_enrollment_service.dart';
import 'package:flutter/material.dart';

class ReEnrollmentProvider with ChangeNotifier {
  final ReEnrollmentService _service = ReEnrollmentService();
  GuardianReEnrollmentEligibility? _eligibility;
  bool _loading = false;
  String? _error;
  GuardianReEnrollmentEligibility? get eligibility => _eligibility;
  bool get loading => _loading;
  String? get error => _error;
  Future<void> load(String token) async {
    _loading = true; _error = null; notifyListeners();
    try { _eligibility = await _service.getEligibility(token); } catch (e) { _error = e.toString().replaceFirst('Exception: ', ''); }
    _loading = false; notifyListeners();
  }
  Future<void> request({required String token, required String studentId}) async { await _service.createRequest(token: token, studentId: studentId); await load(token); }
  void clear() { _eligibility = null; _error = null; _loading = false; notifyListeners(); }
}
