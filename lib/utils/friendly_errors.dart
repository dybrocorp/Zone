import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Z-202 (FASE 1.7): mapeo de errores técnicos → mensajes amigables y SEGUROS.
///
/// La UI NUNCA debe renderizar `$e` (stack traces, mensajes internos, códigos de
/// API) directamente. Este helper convierte la excepción en un texto breve y
/// accionable, y en debug conserva el detalle vía [debugPrint] para el dev.
///
/// Reglas:
///  - Errores conocidos (auth, red, permisos, duplicados) → mensaje específico.
///  - Errores de RLS/permisos → "no tienes permiso" (sin filtrar internals).
///  - Todo lo demás → mensaje genérico + log en debug.
class FriendlyErrors {
  FriendlyErrors._();

  /// Devuelve un mensaje seguro para mostrar al usuario.
  static String message(Object? error, {String fallback = 'Algo salió mal. Intenta de nuevo.'}) {
    final text = error.toString();
    final lower = text.toLowerCase();

    // ── Sin conexión / timeouts ─────────────────────────────────────────
    if (lower.contains('socketexception') ||
        lower.contains('connection refused') ||
        lower.contains('timed out') ||
        lower.contains('network request failed') ||
        lower.contains('no connection')) {
      _log(error, 'Sin conexión');
      return 'Sin conexión. Revisa tu internet e intenta de nuevo.';
    }

    // ── Auth: credenciales ──────────────────────────────────────────────
    if (lower.contains('invalid login credentials') ||
        lower.contains('invalid_credentials') ||
        lower.contains('credentials')) {
      _log(error, 'Credenciales inválidas');
      return 'El ID de Zona o la clave no son válidos.';
    }
    if (error is AuthException && error.message.isNotEmpty) {
      final msg = error.message.toLowerCase();
      if (msg.contains('already registered') ||
          msg.contains('email taken') ||
          msg.contains('duplicate key')) {
        _log(error, 'Registro duplicado');
        return 'Esta cuenta ya está registrada. Inicia sesión.';
      }
      if (msg.contains('jwt')) {
        _log(error, 'Sesión expirada');
        return 'Tu sesión expiró. Vuelve a iniciar sesión.';
      }
    }

    // ── Permisos / RLS / RPC (sin filtrar el detalle) ────────────────────
    if (lower.contains('permission denied') ||
        lower.contains('rls') ||
        lower.contains('row-level security') ||
        lower.contains('policy')) {
      _log(error, 'Permiso denegado');
      return 'No tienes permiso para realizar esta acción.';
    }

    // ── Violaciones de restricciones de datos ─────────────────────────────
    if (lower.contains('violates foreign key') ||
        lower.contains('violates not-null constraint') ||
        lower.contains('check constraint')) {
      _log(error, 'Restricción de datos');
      return 'No se pudo guardar: el registro no es válido.';
    }

    // ── Postgrest genérico ────────────────────────────────────────────────
    if (error is PostgrestException) {
      _log(error, 'Postgrest ${error.code}');
      return 'No se pudo completar la operación en el servidor. Intenta de nuevo.';
    }

    // ── Desconocido: no exponer el texto técnico ─────────────────────────
    _log(error, 'Desconocido');
    return fallback;
  }

  static void _log(Object? error, String category) {
    // Solo en debug: el detalle técnico NO debe llegar a producción/UI.
    debugPrint('[FriendlyErrors:$category] $error');
  }
}