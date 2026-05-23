import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';

/// Servicio para detectar el estado de la conexión a internet.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  
  bool _isOnline = true;
  bool get isOnline => _isOnline;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);
    
    _connectivity.onConnectivityChanged.listen((results) {
      // connectivity_plus 6.x devuelve una lista de ConnectivityResult
      _updateStatus(results);
    });
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // Si hay cualquier conexión que no sea 'none', consideramos que está online
    final currentlyOnline = !results.contains(ConnectivityResult.none);
    if (currentlyOnline != _isOnline) {
      _isOnline = currentlyOnline;
      _statusController.add(_isOnline);
      print('[ConnectivityService] Estado cambiado: ${currentlyOnline ? 'ONLINE' : 'OFFLINE'}');
    }
  }

  void dispose() {
    _statusController.close();
  }
}
