/// PHASE G — Política de recuperación de login fail-closed (pura).
///
/// Este módulo concentra las DECISIONES sin efectos secundarios del flujo de
/// login de usuarios existentes (`ZoneIdService.loginWithExistingID`) y del
/// arranque (`getOrCreate`):
///
/// 1. ORDEN DE PASOS CONGELADO (`LoginRecoveryPolicy.loginSteps`):
///    policy guard → FORMAT validation → signIn (anónimo) → RPC claim →
///    persistencia local → ensureAuth/llaves.
///    Regla R-13: NINGÚN paso con efecto secundario puede ejecutarse antes de
///    que pasen los gates puros. En particular, el formato se valida ANTES de
///    `signInAnonymously` (antes, una entrada inválida quemaba una sesión
///    anónima + escrituras de almacenamiento — defecto R-13).
///
/// 2. CORRUPCIÓN DE ALMACENAMIENTO (regla R-05): los errores del keystore
///    seguro (BadPaddingException / mensajes de desencriptación de
///    `flutter_secure_storage`) NO generan limpieza destructiva. El servicio
///    debe re-lanzar [StorageCorruptionError] (tipado, sin `deleteAll()`):
///    borrar todo el almacenamiento destruye el anclaje de identidad
///    (ZONE-ID, uid, claves E2EE) ante un error TRANSITORIO del keystore.
///
/// 3. Mensajes UI-safe: los errores del módulo nunca contienen material
///    sensible (claves, seeds, tokens).
///
/// Módulo PURO: sin I/O, sin Supabase, sin storage — testeable en VM.
library;

/// Passos del login en orden congelado (contrato R-13). La implementación en
/// `ZoneIdService` debe respetar este orden; el test de regresión fuente
/// (`test/recovery/recovery_fail_closed_test.dart`) lo verifica.
class LoginRecoveryPolicy {
  LoginRecoveryPolicy._();

  /// Orden congelado del login existente (nombres para el contrato de
  /// regresión fuente; cada uno es un PASO, la implementación los mapea).
  static const List<String> loginSteps = [
    'policy_guard',
    'format_validation',
    'sign_in_anonymously',
    'rpc_claim',
    'persist_identity_and_profile',
    'ensure_auth_keys',
    'commit_in_memory_state',
  ];

  /// Valida el formato canónico de un ZONE-ID: `ZONE-` + 8×[A-Z0-9].
  /// Contrato compartido con el backend (claim_zone_id / verify_zone_id).
  static bool isValidZoneIdFormat(String? zoneId) {
    if (zoneId == null || zoneId.isEmpty) return false;
    return RegExp(r'^ZONE-[A-Z0-9]{8}$').hasMatch(zoneId);
  }

  /// Detecta si un error capturado es señal de keystore corrupto (los únicos
  /// casos clasificables SIN heurísticas agresivas; cualquier otra excepción
  /// se re-lanza como está).
  static bool isStorageCorruptionSignal(Object error) {
    final text = error.toString();
    return text.contains('BadPaddingException') ||
        text.contains('decryption');
  }

  /// Decide `true` si el flujo DEBE abortar fail-closed (anticorrupción):
  /// este módulo ya no considera la limpieza destructiva una recuperación
  /// válida (regla R-05). Siempre `true` ante señal de corrupción.
  static bool shouldFailClosedOnCorruption(Object error) =>
      isStorageCorruptionSignal(error);
}

/// Error tipado: keystore de almacenamiento seguro corrupto durante login /
/// arranque (regla R-05). NO dispara limpieza destructiva: el llamador debe
/// fallar cerrado. Mensaje UI-safe.
class StorageCorruptionError implements Exception {
  const StorageCorruptionError(this.context, {this.origin});

  final String context;
  final Object? origin;

  @override
  String toString() =>
      'StorageCorruptionError: el almacenamiento seguro está corrupto '
      '($context). No se destruyó ninguna identidad local; reinstalar la '
      'aplicación es la única recuperación manual aceptada.';
}

/// Error tipado: formato de ZONE-ID inválido en login (regla R-13: se
/// rechaza ANTES de consumir una sesión anónima). Mensaje UI-safe.
class LoginFormatError implements Exception {
  const LoginFormatError();

  @override
  String toString() =>
      'LoginFormatError: el código de cuenta no es válido. Debe tener la '
      'forma ZONE-XXXXXXXX (8 caracteres A-Z / 0-9).';
}
