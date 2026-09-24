import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:zone/utils/friendly_errors.dart';

void main() {
  group('FriendlyErrors', () {
    test('errores de red → mensaje de conexión, sin detalles técnicos', () {
      final msg = FriendlyErrors.message(
        Exception('SocketException: failed to connect to 10.0.0.5:5432'),
      );
      expect(msg, contains('conexión'));
      expect(msg, isNot(contains('SocketException')));
    });

    test('errores de credenciales → mensaje de ID inválido', () {
      final msg = FriendlyErrors.message(
        Exception('AuthRetryableFetchException: invalid login credentials'),
      );
      expect(msg.toLowerCase(), contains('no son válidos'));
      expect(msg, isNot(contains('AuthRetryableFetch')));
    });

    test('permisos/RLS → mensaje de permiso, sin filtrar qual interno', () {
      final msg = FriendlyErrors.message(
        Exception('42501: permission denied for table users (select via rls)'),
      );
      expect(msg.toLowerCase(), contains('permiso'));
      expect(msg, isNot(contains('42501')));
    });

    test('PostgrestException → mensaje genérico de servidor', () {
      final msg = FriendlyErrors.message(
        PostgrestException(message: 'DB error: it happened', code: 'P0001'),
      );
      expect(msg.toLowerCase(), contains('servidor'));
      expect(msg, isNot(contains('P0001')));
    });

    test('desconocido → fallback sin exponer el error crudo', () {
      final msg = FriendlyErrors.message(
        StateError('zona secreta con stack interno'),
        fallback: 'No se pudo completar la operación.',
      );
      expect(msg, 'No se pudo completar la operación.');
      expect(msg, isNot(contains('zona secreta')));
    });
  });
}