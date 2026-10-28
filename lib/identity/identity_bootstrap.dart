/// PHASE 2.2 — Bootstrap de la Identity Foundation en el runtime de Zone.
///
/// PRODUCT INTEGRATION SLICE (autorizado CTO 2026-09-25): ÚNICO punto de
/// inicialización de identidad del producto (SINGLE IDENTITY INITIALIZATION
/// PATH). No es parte de PHASE 2.2.2 (import X25519 legacy NO ejecutado), no
/// ejecuta eventos de migración (solo LEE el estado), no toca E2EE/Mesh/Auth
/// ni la base legacy `default.isar`.
///
/// Contratos:
/// - **Idempotente**: 1er arranque ⇒ CREATE (crea cuenta + device_1 `pending`);
///   arranques siguientes ⇒ LOAD (nunca regenera, nunca duplica devices).
/// - **Fail-closed**: cualquier inconsistencia entre el almacén seguro y los
///   metadatos ⇒ errores tipados (`InconsistentIdentityStateError` y amigos);
///   el bootstrap NUNCA fabrica una identidad alternativa.
/// - **Integridad**: verifica que las seeds del almacén seguro deriven las
///   mismas claves públicas que los metadatos persisten (validación clave↔seed).
/// - **Sin secretos en logs/contexto**: solo identificadores y estados públicos.
/// - **Persistencia dedicada**: instancia Isar `zone_identity` (NUNCA
///   `default.isar`); la migración queda intacta (sin registro ⇒ `legacy`).
library;

import 'dart:io';

import 'package:isar/isar.dart';

import 'identity_context.dart';
import 'identity_errors.dart';
import 'identity_persistence.dart';
import 'identity_registry.dart';
import 'migration_controller.dart';
import 'migration_persistence.dart';
import 'migration_state_machine.dart';
import 'models.dart';
import 'secure_key_store.dart';

/// Orquestador del bootstrap de identidad.
///
/// Construcción en producción: [IdentityBootstrap.initialize] (abre la instancia
/// `zone_identity` y monta almacén seguro + repositorios reales). En tests se
/// inyectan dobles en memoria (misma convención que `IdentityRegistry`).
class IdentityBootstrap {
  IdentityBootstrap({
    required this.registry,
    required this.migrationStateReader,
    Isar? isar,
    Future<void> Function()? onClose,
  }) : _isar = isar,
       _onClose = onClose ?? isar?.close;

  /// Registro de identidad de la fundación (cuenta + dispositivos + fingerprints).
  final IdentityRegistry registry;

  /// Lee el estado de migración SIN ejecutar eventos (fail-closed: ausencia de
  /// registro ⇒ `legacy`). PHASE 2.2.1 no se ejecuta en este slice.
  final Future<MigrationState> Function() migrationStateReader;

  final Isar? _isar;
  final Future<void> Function()? _onClose;

  /// Instancia Isar dedicada `zone_identity` (null en tests con dobles).
  Isar? get isar => _isar;

  /// Abre la instancia dedicada de identidad y monta las dependencias reales
  /// (`FlutterSecureStorageBackend` salvo inyección para tests).
  static Future<IdentityBootstrap> initialize({
    Directory? directory,
    KeyValueBackend? secretBackend,
    IdGenerator? generateId,
  }) async {
    final isar = await openIdentityIsar(directory: directory);
    final migration =
        MigrationController(repository: IsarMigrationRepository(isar));
    return IdentityBootstrap(
      registry: IdentityRegistry(
        keyStore: VersionedSecureKeyStore(
          secretBackend ?? FlutterSecureStorageBackend(),
        ),
        repository: IsarIdentityRepository(isar),
        generateId: generateId,
      ),
      migrationStateReader: migration.currentState,
      isar: isar,
    );
  }

  /// Ejecuta el bootstrap idempotente y devuelve el contexto público.
  ///
  /// 1. Cuenta: crea o carga (nunca regenera silenciosamente).
  /// 2. Dispositivo device_1: crea SOLO si no existe ningún device; si existe,
  ///    reutiliza el primario (más antiguo, desempate por deviceId).
  /// 3. Integridad: clave pública derivada de la seed == metadata persistido.
  /// 4. Fingerprints públicos + estado de migración (lectura, sin eventos).
  Future<IdentityContext> run() async {
    final accountCreated = await registry.loadAccountMetadata() == null;
    final account = await registry.ensureAccountIdentity();

    final devices = await registry.listDevices(account.accountId);
    final DeviceProfile device;
    final bool deviceCreated;
    if (devices.isEmpty) {
      device = await registry.registerDevice(accountId: account.accountId);
      deviceCreated = true;
    } else {
      device = _primaryDevice(devices);
      deviceCreated = false;
    }

    await _assertKeyMaterialMatches(account, device);

    final accountFingerprint = await registry.accountFingerprintText(
      account.accountId,
    );
    final deviceFingerprint = await registry.deviceFingerprintText(
      device.deviceId,
    );
    final migrationState = (await migrationStateReader()).statusId;

    return IdentityContext(
      accountId: account.accountId,
      deviceId: device.deviceId,
      deviceStatus: device.status.statusId,
      accountFingerprint: accountFingerprint,
      deviceFingerprint: deviceFingerprint,
      migrationState: migrationState,
      accountCreated: accountCreated,
      deviceCreated: deviceCreated,
    );
  }

  /// Cierra la instancia Isar dedicada si existe (no-op en tests con dobles).
  Future<void> close() async {
    final onClose = _onClose;
    if (onClose != null) {
      await onClose();
    }
  }

  /// Validación de integridad clave↔seed: las seeds del almacén seguro DEBEN
  /// derivar las mismas claves públicas que los metadatos persisten. Cualquier
  /// desajuste ⇒ [InconsistentIdentityStateError] (fail-closed, no regenera).
  Future<void> _assertKeyMaterialMatches(
    AccountIdentity account,
    DeviceProfile device,
  ) async {
    // La carga ya es fail-closed (IdentityNotFoundError / SecureKeyMissingError
    // / SecureKeyCorruptError); aquí se verifica la CONSISTENCIA.
    final accountMaterial = await registry.loadAccountKeyMaterial(
      account.accountId,
    );
    final derivedAccount = await accountMaterial.publicKeyBase64();
    if (derivedAccount != account.identityPublicKeyBase64) {
      throw InconsistentIdentityStateError(
        'account public key does not match secure store seed',
      );
    }

    final deviceMaterial = await registry.loadDeviceKeyMaterial(device.deviceId);
    final derivedDeviceSign = await deviceMaterial.devicePublicKeyBase64();
    final derivedDeviceEnc = await deviceMaterial.encryptionPublicKeyBase64();
    if (derivedDeviceSign != device.devicePublicKeyBase64 ||
        derivedDeviceEnc != device.deviceEncryptionPublicKeyBase64) {
      throw InconsistentIdentityStateError(
        'device public keys do not match secure store seeds',
      );
    }
  }

  /// Device primario determinista: el más antiguo (desempate lexicográfico por
  /// deviceId). Garantiza que arranques repetidos reutilicen device_1.
  static DeviceProfile _primaryDevice(List<DeviceProfile> devices) {
    final sorted = [...devices]
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0 ? byTime : a.deviceId.compareTo(b.deviceId);
      });
    return sorted.first;
  }
}