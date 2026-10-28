/// FASE 2.1 — Errores tipados de la fundación de identidad.
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Política (mandato §15): los fallos sensibles fallan cerrado y usan errores
/// tipados/dominio. NINGÚN mensaje de error expone material clave (seeds,
/// claves privadas, envelopes). Los errores incluyen solo identificadores y
/// causas técnicas genéricas.
library;

import 'keys.dart';

/// Base de todos los errores de la fundación.
sealed class IdentityFoundationError implements Exception {
  const IdentityFoundationError(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Clave solicitada ausente en el almacén seguro.
class SecureKeyMissingError extends IdentityFoundationError {
  const SecureKeyMissingError(String ref)
    : super(
        'Required secret is not present (ref: $ref). '
        'No replacement identity is generated automatically.',
      );
}

/// Entrada del almacén seguro corrupta: envelope inválido, Base64 inválido o
/// longitud de seed incorrecta.
class SecureKeyCorruptError extends IdentityFoundationError {
  const SecureKeyCorruptError(String ref, String cause)
    : super(
        'Stored secret failed integrity validation (ref: $ref, cause: $cause).',
      );
}

/// Versión del envelope del almacén seguro no soportada por esta fase.
class SecureKeyVersionMismatchError extends IdentityFoundationError {
  const SecureKeyVersionMismatchError(String ref, String found, String expected)
    : super(
        'Stored secret has unsupported envelope version '
        '(ref: $ref, found: $found, expected: $expected).',
      );
}

/// Longitud de seed fuera del contrato (32 bytes para Ed25519/X25519).
class InvalidSeedLengthError extends IdentityFoundationError {
  const InvalidSeedLengthError(int found)
    : super(
        'Invalid secret seed length ($found bytes); '
        'expected $kIdentitySeedLength bytes.',
      );
}

/// Algoritmo no soportado por la fundación.
class UnsupportedAlgorithmError extends IdentityFoundationError {
  const UnsupportedAlgorithmError(String algorithm)
    : super('Unsupported identity algorithm: $algorithm.');
}

/// Input inválido para un fingerprint (UUID mal formado, clave pública con
/// longitud incorrecta, etc.). Nunca contiene material secreto.
class InvalidFingerprintInputError extends IdentityFoundationError {
  const InvalidFingerprintInputError(String cause)
    : super('Invalid fingerprint input: $cause.');
}

/// Metadatos de identidad inválidos (UUID mal formado, base64 corrupto,
/// estado desconocido, versión no soportada).
class InvalidIdentityMetadataError extends IdentityFoundationError {
  const InvalidIdentityMetadataError(String cause)
    : super('Invalid identity metadata: $cause.');
}

/// Transición de estado de dispositivo no permitida por la máquina formal
/// (I-030 / BOOTSTRAP_POLICY §4).
class InvalidDeviceStateTransitionError extends IdentityFoundationError {
  const InvalidDeviceStateTransitionError(String from, String to)
    : super('Invalid device state transition: $from → $to.');
}

/// Intento de usar material con un propósito criptográfico distinto al
/// aprobado (p.ej. firmar con X25519 o cifrar con la identidad de cuenta).
class KeyPurposeMismatchError extends IdentityFoundationError {
  const KeyPurposeMismatchError(String purpose, String attempted)
    : super(
        'Key purpose mismatch: material of purpose `$purpose` '
        'cannot be used as `$attempted`.',
      );
}

/// No existe un registro de identidad (cuenta/dispositivo) en los metadatos
/// persistidos. Distinto de [SecureKeyMissingError] (ausencia de la seed en el
/// almacén seguro): este error indica ausencia del registro público.
class IdentityNotFoundError extends IdentityFoundationError {
  const IdentityNotFoundError(String kind, String id)
    : super('Identity record not found ($kind: $id).');
}

/// Registro duplicado en la persistencia de identidad (device/account duplicada).
class DuplicateIdentityRecordError extends IdentityFoundationError {
  const DuplicateIdentityRecordError(String kind, String id)
    : super('Duplicate identity record ($kind: $id).');
}

/// Estado parcial inconsistente entre el almacén seguro y los metadatos.
/// Se usa para NUNCA regenerar una identidad silenciosamente (mandato §15):
/// si el metadata existe pero la seed no (o viceversa), se lanza este error en
/// lugar de fabricar una identidad nueva.
class InconsistentIdentityStateError extends IdentityFoundationError {
  const InconsistentIdentityStateError(String cause)
    : super(
        'Inconsistent identity state detected: $cause. '
        'Refusing to regenerate a replacement identity.',
      );
}

/// Error de persistencia de metadatos (Isar).
class IdentityPersistenceError extends IdentityFoundationError {
  const IdentityPersistenceError(String cause)
    : super('Identity persistence error: $cause.');
}

/// Transición de la máquina de migración no permitida: cualquier salto hacia
/// delante prohibido, salida de estados terminales o evento no válido en el
/// estado actual. PHASE 2.2.1 (máquina de migración, `IDENTITY_MIGRATION_STATE_MACHINE.md`).
class InvalidMigrationStateTransitionError extends IdentityFoundationError {
  const InvalidMigrationStateTransitionError(String from, String to)
    : super('Invalid migration state transition: $from → $to.');
}

/// Intento de aplicar cualquier evento de migración cuando la migración ya
/// está `FINALIZED` (estado terminal, sin retorno).
class MigrationAlreadyFinalizedError extends IdentityFoundationError {
  const MigrationAlreadyFinalizedError()
    : super(
        'Migration is already FINALIZED. Finalized migrations are terminal '
        'and cannot be re-run or modified.',
      );
}

/// Rollback solicitado desde un estado distinto de `MIGRATION_FAILED`. El único
/// camino de retorno a `LEGACY` es `MIGRATION_FAILED → rollback` (protege contra
/// rollbacks abusivos desde etapas avanzadas, PHASE 2.1.1 §5).
class MigrationRollbackNotAllowedError extends IdentityFoundationError {
  const MigrationRollbackNotAllowedError(String from)
    : super(
        'Rollback only allowed from MIGRATION_FAILED (current: $from). '
        'A forward migration must fail explicitly before rollback.',
      );
}

/// Registro de migración persistido corrupto/inconsistente (estado, evento o
/// auditoría desconocidos). Fail-closed: no se materializa un estado inválido
/// ni se "repara" silenciosamente inventando un estado.
class MigrationRecordCorruptError extends IdentityFoundationError {
  const MigrationRecordCorruptError(String cause)
    : super('Corrupt persisted migration record: $cause.');
}
