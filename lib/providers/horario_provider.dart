import 'package:academyhub_mobile/model/horario_model.dart';
import 'package:academyhub_mobile/services/horario_service.dart';
import 'package:flutter/foundation.dart';

class HorarioProvider with ChangeNotifier {
  final HorarioService _horarioService;

  HorarioProvider({HorarioService? horarioService})
      : _horarioService = horarioService ?? HorarioService();

  List<HorarioModel> _horarios = [];
  bool _isLoading = false;
  String? _error;
  bool _isInitialLoading = true;
  String? _canonicalTeacherId;
  int _fetchRequest = 0;

  List<HorarioModel> get horarios => List.unmodifiable(_horarios);
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isInitialLoading => _isInitialLoading;
  bool hasCanonicalTeacherSchedules(String teacherId) =>
      teacherId.isNotEmpty && _canonicalTeacherId == teacherId;

  void _setLoading(bool loading) {
    if (_isLoading != loading) {
      _isLoading = loading;
      notifyListeners();
    }
  }

  void _setError(String? errorMsg) {
    _error = errorMsg?.replaceAll('Exception: ', '');
    if (_error != null || errorMsg != null) notifyListeners();
  }

  void clearError() {
    if (_error != null) {
      _error = null;
      notifyListeners();
    }
  }

  void clear() {
    _fetchRequest++;
    debugPrint('🧹 [HorarioProvider] Cache limpo.');
    _horarios = [];
    _isInitialLoading = true;
    _isLoading = false;
    _error = null;
    _canonicalTeacherId = null;
    notifyListeners();
  }

  // --- MÉTODOS DE API ---

  Future<void> fetchHorarios(String token,
      {Map<String, String>? filter, String debugScreen = 'unknown'}) async {
    final request = ++_fetchRequest;
    if (_horarios.isEmpty) _isInitialLoading = true;
    _setLoading(true);
    _setError(null);

    try {
      final loaded = await _horarioService.getHorarios(
        token,
        filter: filter,
        debugScreen: debugScreen,
      );
      if (request != _fetchRequest) return;
      _horarios = loaded;
      final normalizedFilter = filter ?? const <String, String>{};
      _canonicalTeacherId = normalizedFilter.length == 1
          ? normalizedFilter['teacherId']?.trim()
          : null;
      notifyListeners();
    } catch (e) {
      if (request != _fetchRequest) return;
      _setError(e.toString());
    } finally {
      if (request == _fetchRequest) {
        if (_isInitialLoading) _isInitialLoading = false;
        _setLoading(false);
      }
    }
  }

  void addHorarioFromEvent(HorarioModel novoHorario) {
    if (!_horarios.any((h) => h.id == novoHorario.id)) {
      _horarios.add(novoHorario);
      notifyListeners();
      debugPrint("[HorarioProvider] Horário adicionado via WebSocket.");
    }
  }

  void updateHorarioFromEvent(HorarioModel horarioAtualizado) {
    final index = _horarios.indexWhere((h) => h.id == horarioAtualizado.id);
    if (index != -1) {
      _horarios[index] = horarioAtualizado;
      notifyListeners();
      debugPrint("[HorarioProvider] Horário atualizado via WebSocket.");
    } else {
      addHorarioFromEvent(horarioAtualizado);
    }
  }

  void removeHorarioById(String id) {
    final int removedCount = _horarios.length;
    _horarios.removeWhere((h) => h.id == id);
    if (_horarios.length < removedCount) {
      notifyListeners();
      debugPrint("[HorarioProvider] Horário ID $id removido via WebSocket.");
    }
  }
}
