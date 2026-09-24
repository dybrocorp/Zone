import 'dart:math';

class RetryHelper {
  static const int _maxRetries = 5;
  static const int _baseDelayMs = 1000;
  static const int _maxDelayMs = 60000;

  /// Ejecuta una función con retry, exponential backoff y jitter.
  /// Retorna el resultado o null si todos los intentos fallan.
  static Future<T?> withRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = _maxRetries,
    String label = '',
  }) async {
    final random = Random();
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        return await operation();
      } catch (e) {
        if (attempt == maxRetries) return null;
        final baseDelay = min(_baseDelayMs * (1 << attempt), _maxDelayMs);
        final jitter = (baseDelay * 0.5 * random.nextDouble()).toInt();
        final delay = Duration(milliseconds: baseDelay + jitter);
        await Future.delayed(delay);
      }
    }
    return null;
  }
}
