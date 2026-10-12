import 'package:academyhub_mobile/model/dashboard_model.dart';
import 'package:academyhub_mobile/services/dashboard_service.dart';
import 'package:flutter/material.dart';
import 'package:academyhub_mobile/services/performance_trace.dart';

class DashboardProvider with ChangeNotifier {
  final DashboardService _service = DashboardService();

  DashboardData? _data;
  bool _isLoading = false;
  String? _error;

  DashboardData? get data => _data;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchDashboard(String token) async {
    // LÓGICA DE CACHE:
    // Só ativa o loading visual (tela branca) se NÃO tivermos dados salvos.
    // Se já tiver dados, o usuário vê a tela antiga enquanto atualizamos em background.
    if (_data == null) {
      _isLoading = true;
      notifyListeners();
    }

    try {
      // Busca os dados novos na API
      final newData = await PerformanceTrace.measure(
          'dashboard.staff.api', () => _service.getDashboardMetrics(token));

      // Atualiza os dados
      _data = newData;
      _error = null;

      // Não precisamos setar isLoading false aqui dentro, pois faremos no finally,
      // mas o notifyListeners aqui garante que a UI atualize assim que chegar o dado novo.
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      debugPrint("Erro DashboardProvider: $e");
    } finally {
      // Garante que o loading pare, seja sucesso ou erro
      _isLoading = false;
      notifyListeners();
    }
  }

  // Método opcional caso queira limpar o cache ao fazer logout
  void clearCache() {
    _data = null;
    _isLoading = false;
    _error = null;
    notifyListeners();
  }
}
