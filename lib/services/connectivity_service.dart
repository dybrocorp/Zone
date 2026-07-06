import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'logger_service.dart';

/// Servicio para detectar el estado de la conexión a internet.
/// Distingue entre conexión de red (WiFi/datos) y acceso real a internet.
class ConnectivityService {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  final _logger = LoggerService();
  
  bool _isOnline = true;
  bool _hasRealInternet = true;
  bool get isOnline => _isOnline;
  bool get hasRealInternet => _hasRealInternet;

  final _statusController = StreamController<bool>.broadcast();
  Stream<bool> get statusStream => _statusController.stream;

  Timer? _internetCheckTimer;

  Future<void> initialize() async {
    final result = await _connectivity.checkConnectivity();
    _updateStatus(result);
    
    _connectivity.onConnectivityChanged.listen((results) {
      // connectivity_plus 6.x devuelve una lista de ConnectivityResult
      _updateStatus(results);
    });

    // Verificar acceso real a internet periódicamente
    _internetCheckTimer = Timer.periodic(Duration(seconds: 30), (_) async {
      await _checkRealInternet();
    });
    
    // Verificar al inicio
    await _checkRealInternet();
  }

  Future<void> _checkRealInternet() async {
    try {
      // Intentar conectar a un servidor confiable
      final result = await InternetAddress.lookup('dns.google')
          .timeout(Duration(seconds: 5));
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        if (!_hasRealInternet) {
          _hasRealInternet = true;
          _logger.debug('[ConnectivityService] Internet real detectado');
        }
      }
    } catch (e) {
      if (_hasRealInternet) {
        _hasRealInternet = false;
        _logger.debug('[ConnectivityService] Sin acceso real a internet');
      }
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    // Si hay cualquier conexión que no sea 'none', consideramos que está online
    final currentlyOnline = !results.contains(ConnectivityResult.none);
    if (currentlyOnline != _isOnline) {
      _isOnline = currentlyOnline;
      _statusController.add(_isOnline);
      _logger.debug('[ConnectivityService] Estado de red cambiado: ${currentlyOnline ? 'ONLINE' : 'OFFLINE'}');
    }
  }

  void dispose() {
    _statusController.close();
    _internetCheckTimer?.cancel();
  }
}
