import 'package:flutter/foundation.dart';

/// Servicio de logging simple para reemplazar prints en producción.
class LoggerService {
  static final LoggerService _instance = LoggerService._internal();
  factory LoggerService() => _instance;
  LoggerService._internal();

  void debug(String message) {
    if (kDebugMode) {
      print('[DEBUG] $message');
    }
  }

  void info(String message) {
    if (kDebugMode) {
      print('[INFO] $message');
    }
  }

  void warning(String message) {
    if (kDebugMode) {
      print('[WARNING] $message');
    }
  }

  void error(String message) {
    if (kDebugMode) {
      print('[ERROR] $message');
    }
  }
}
