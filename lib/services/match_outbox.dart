/// PHASE 2.2.5 — Política pura del outbox de matches (sin I/O).
///
/// Contrato de identidad de operación (determinista, sin secretos — solo
/// UUIDs públicos de `users.id` y el id de match del servidor):
/// - request: `mr:<low>:<high>:<requester>:<receiver>` (la dirección importa:
///   RLS exige `auth.uid() == requester_id`; la convergencia A↔B opuesta la
///   resuelve el par canónico Phase 2.2.4 en el servidor, no el op-id).
/// - accept: `ma:<serverMatchId>:<actor>`.
/// - reject: `mj:<serverMatchId>:<actor>`.
/// Re-encolar la misma operación lógica reemplaza la fila (`putByOperationId`)
/// en lugar de duplicarla; el reintento conserva SIEMPRE el mismo
/// `operationId` (nunca un aleatorio por intento).
///
/// Backoff: 1,2,4,8,16,32,60,60… minutos, Tope `maxRetries` (8) → terminal.
/// Clasificación estructurada (tipos, no texto libre): red/timeout →
/// retryable; auth/RLS → terminal; malformado → terminal; resto → retryable
/// acotado. Los códigos persistidos son cortos y nunca texto de excepciones.
library;

import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'match_pair.dart';

/// Tipos de operación del outbox.
class MatchOpType {
  MatchOpType._();

  static const String request = 'request';
  static const String accept = 'accept';
  static const String reject = 'reject';

  static bool isValid(String t) =>
      t == request || t == accept || t == reject;
}

/// Estados de fila del outbox.
class MatchOpState {
  MatchOpState._();

  static const String pending = 'pending';
  static const String inflight = 'inflight';
  static const String failed = 'failed';

  static bool isValid(String s) =>
      s == pending || s == inflight || s == failed;
}

/// Códigos cortos de fallo (único contenido de `lastErrorCode`).
class MatchOpError {
  MatchOpError._();

  static const String network = 'network';
  static const String timeout = 'timeout';
  static const String server = 'server';
  static const String conflict = 'conflict';
  static const String auth = 'auth';
  static const String malformed = 'malformed';
  static const String missing = 'missing';
  static const String state = 'state';
  static const String unknown = 'unknown';

  /// Códigos terminales: reintentar es inútil o inseguro.
  static bool isTerminal(String code) =>
      code == auth ||
      code == malformed ||
      code == missing ||
      code == state;
}

/// Política del outbox (funciones puras, testeables sin plataforma).
class MatchOutboxPolicy {
  MatchOutboxPolicy._();

  static const int maxRetries = 8;

  /// Identidad determinista de una operación REQUEST.
  static String requestId({
    required String requester,
    required String receiver,
  }) {
    final low = MatchPair.canonicalLow(requester, receiver);
    final high = MatchPair.canonicalHigh(requester, receiver);
    return 'mr:$low:$high:${requester.trim()}:${receiver.trim()}';
  }

  /// Identidad determinista de un ACCEPT sobre un match del servidor.
  static String acceptId({required String serverMatchId, required String actor}) {
    final id = serverMatchId.trim();
    final me = actor.trim();
    if (id.isEmpty || me.isEmpty) {
      throw const InvalidMatchIdentityError('accept needs match id + actor');
    }
    return 'ma:$id:$me';
  }

  /// Identidad determinista de un REJECT sobre un match del servidor.
  static String rejectId({required String serverMatchId, required String actor}) {
    final id = serverMatchId.trim();
    final me = actor.trim();
    if (id.isEmpty || me.isEmpty) {
      throw const InvalidMatchIdentityError('reject needs match id + actor');
    }
    return 'mj:$id:$me';
  }

  /// Backoff antes del siguiente intento (minutos): 1,2,4,8,16,32,60,60…
  static Duration backoffForRetry(int retryCount) {
    final n = retryCount < 0 ? 0 : retryCount;
    final minutes = n >= 6 ? 60 : (1 << n);
    return Duration(minutes: minutes);
  }

  static DateTime nextAttemptAt({
    required int retryCount,
    required DateTime now,
  }) =>
      now.add(backoffForRetry(retryCount));

  /// Clasifica una excepción en un código corto (tipos estructurados;
  /// el texto del mensaje solo se usa como último recurso para RLS).
  static String classifyException(Object e) {
    if (e is SocketException || e is TimeoutException) {
      return e is TimeoutException ? MatchOpError.timeout : MatchOpError.network;
    }
    if (e is AuthException) return MatchOpError.auth;
    if (e is PostgrestException) {
      final code = e.code ?? '';
      if (code == '409' || code == '23505') return MatchOpError.conflict;
      if (code == '42501' || code == '401' || code == '403') {
        return MatchOpError.auth;
      }
      final msg = e.message.toLowerCase();
      if (msg.contains('row-level security') ||
          msg.contains('rls') ||
          msg.contains('not authorized') ||
          msg.contains('permission denied')) {
        return MatchOpError.auth;
      }
      if (code.startsWith('5') || code.startsWith('PGRST')) {
        return MatchOpError.server;
      }
      return MatchOpError.server;
    }
    if (e is FormatException || e is InvalidMatchIdentityError) {
      return MatchOpError.malformed;
    }
    return MatchOpError.unknown;
  }

  /// Validación fail-closed de una operación antes de encolar/reproducir.
  /// Retorna el código de error o null si es válida.
  static String? validateOp({
    required String operationType,
    required String canonicalLow,
    required String canonicalHigh,
    required String actorUserId,
    String? targetUserId,
    String? serverMatchId,
  }) {
    if (!MatchOpType.isValid(operationType)) return MatchOpError.malformed;
    if (actorUserId.trim().isEmpty) return MatchOpError.malformed;
    try {
      switch (operationType) {
        case MatchOpType.request:
          final target = (targetUserId ?? '').trim();
          if (target.isEmpty) return MatchOpError.malformed;
          // El par almacenado debe coincidir con el canónico real (anti-tamper).
          if (MatchPair.canonicalLow(actorUserId, target) !=
                  canonicalLow.trim() ||
              MatchPair.canonicalHigh(actorUserId, target) !=
                  canonicalHigh.trim()) {
            return MatchOpError.malformed;
          }
          return null;
        case MatchOpType.accept:
        case MatchOpType.reject:
          if ((serverMatchId ?? '').trim().isEmpty) {
            return MatchOpError.malformed;
          }
          if (canonicalLow.trim().isEmpty || canonicalHigh.trim().isEmpty) {
            return MatchOpError.malformed;
          }
          return null;
        default:
          return MatchOpError.malformed;
      }
    } on InvalidMatchIdentityError {
      return MatchOpError.malformed;
    }
  }
}
