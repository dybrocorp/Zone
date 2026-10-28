/// FASE 2.1 — Persistencia de metadatos de identidad (Isar).
///
/// NEW FOUNDATION — NOT YET INTEGRATED.
///
/// Interfaz [IdentityRepository] + implementación Isar en una instancia de
/// datos dedicada (`zone_identity`). Misma arquitectura y motor Isar que la
/// app (mandato §12), sin tocar la base de mensajes legacy. Ningún secreto se
/// persiste aquí (I-004).
library;

import 'dart:io';

import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';

import 'identity_errors.dart';
import 'identity_persistence_models.dart';
import 'keys.dart';
import 'migration_models.dart';
import 'models.dart';

/// Contrato del repositorio de metadatos de identidad. Permite inyectar un
/// doble en memoria en los tests (los tests de Isar usan instancias temporales).
abstract class IdentityRepository {
  Future<AccountIdentity?> loadAccount();

  Future<void> saveAccount(AccountIdentity account);

  Future<void> deleteAccount();

  Future<List<DeviceProfile>> loadDevices(String accountId);

  Future<DeviceProfile?> loadDevice(String deviceId);

  Future<void> saveDevice(DeviceProfile device);

  Future<void> deleteDevice(String deviceId);
}

/// Apertura de la instancia Isar de identidad.
///
/// [directory] se inyecta en tests; en producción usa el directorio de
/// documentos de la app (igual que `IsarService` legacy).
Future<Isar> openIdentityIsar({
  Directory? directory,
  String name = kIdentityIsarInstanceName,
}) async {
  final dir = directory ?? await getApplicationDocumentsDirectory();
  return Isar.open(
    [AccountIdentityDboSchema, DeviceDboSchema, MigrationDboSchema],
    directory: dir.path,
    name: name,
  );
}

/// Implementación Isar del repositorio de identidad.
class IsarIdentityRepository implements IdentityRepository {
  IsarIdentityRepository(this._isar);

  final Isar _isar;

  @override
  Future<AccountIdentity?> loadAccount() async {
    try {
      final dbo = await _isar.accountIdentityDbos.where().findFirst();
      return dbo == null ? null : _toAccountIdentity(dbo);
    } catch (e) {
      throw IdentityPersistenceError('loadAccount failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> saveAccount(AccountIdentity account) async {
    try {
      final current = await _isar.accountIdentityDbos.where().findFirst();
      if (current != null && current.accountId != account.accountId) {
        throw DuplicateIdentityRecordError('account', account.accountId);
      }
      final dbo = (current ?? AccountIdentityDbo())
        ..accountId = account.accountId
        ..zoneId = account.zoneId
        ..identityPublicKeyBase64 = account.identityPublicKeyBase64
        ..identityAlgorithm = account.identityAlgorithm.algorithmId
        ..identityVersion = account.identityVersion
        ..identityStatus = account.status.statusId
        ..createdAt = account.createdAt
        ..updatedAt = account.updatedAt;
      await _isar.writeTxn(() => _isar.accountIdentityDbos.putByAccountId(dbo));
    } catch (e) {
      if (e is IdentityFoundationError) rethrow;
      throw IdentityPersistenceError('saveAccount failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> deleteAccount() async {
    try {
      await _isar.writeTxn(() => _isar.accountIdentityDbos.clear());
    } catch (e) {
      throw IdentityPersistenceError('deleteAccount failed: ${e.runtimeType}');
    }
  }

  @override
  Future<List<DeviceProfile>> loadDevices(String accountId) async {
    try {
      final dbos = await _isar.deviceDbos
          .filter()
          .accountIdEqualTo(accountId)
          .findAll();
      return dbos.map(_toDeviceProfile).toList();
    } catch (e) {
      throw IdentityPersistenceError('loadDevices failed: ${e.runtimeType}');
    }
  }

  @override
  Future<DeviceProfile?> loadDevice(String deviceId) async {
    try {
      final dbo = await _isar.deviceDbos
          .filter()
          .deviceIdEqualTo(deviceId)
          .findFirst();
      return dbo == null ? null : _toDeviceProfile(dbo);
    } catch (e) {
      throw IdentityPersistenceError('loadDevice failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> saveDevice(DeviceProfile device) async {
    try {
      final existing = await _isar.deviceDbos
          .filter()
          .deviceIdEqualTo(device.deviceId)
          .findFirst();
      if (existing != null && existing.accountId != device.accountId) {
        throw DuplicateIdentityRecordError('device', device.deviceId);
      }
      final dbo = (existing ?? DeviceDbo())
        ..deviceId = device.deviceId
        ..accountId = device.accountId
        ..devicePublicKeyBase64 = device.devicePublicKeyBase64
        ..deviceEncryptionPublicKeyBase64 =
            device.deviceEncryptionPublicKeyBase64
        ..encryptionKeyVersion = device.encryptionKeyVersion
        ..status = device.status.statusId
        ..createdAt = device.createdAt
        ..updatedAt = device.updatedAt
        ..revokedAt = device.revokedAt
        ..revocationReason = device.revocationReason;
      await _isar.writeTxn(() => _isar.deviceDbos.putByDeviceId(dbo));
    } catch (e) {
      if (e is IdentityFoundationError) rethrow;
      throw IdentityPersistenceError('saveDevice failed: ${e.runtimeType}');
    }
  }

  @override
  Future<void> deleteDevice(String deviceId) async {
    try {
      final dbo = await _isar.deviceDbos
          .filter()
          .deviceIdEqualTo(deviceId)
          .findFirst();
      if (dbo != null) {
        await _isar.writeTxn(() => _isar.deviceDbos.delete(dbo.isarId));
      }
    } catch (e) {
      throw IdentityPersistenceError('deleteDevice failed: ${e.runtimeType}');
    }
  }

  static AccountIdentity _toAccountIdentity(AccountIdentityDbo dbo) {
    final algorithm = IdentityKeyAlgorithm.fromAlgorithmId(
      dbo.identityAlgorithm,
    );
    final status = AccountIdentityStatus.fromStatusId(dbo.identityStatus);
    return AccountIdentity(
      accountId: dbo.accountId,
      zoneId: dbo.zoneId,
      identityPublicKeyBase64: dbo.identityPublicKeyBase64,
      identityAlgorithm: algorithm,
      identityVersion: dbo.identityVersion,
      status: status,
      createdAt: dbo.createdAt,
      updatedAt: dbo.updatedAt,
    );
  }

  static DeviceProfile _toDeviceProfile(DeviceDbo dbo) {
    return DeviceProfile(
      deviceId: dbo.deviceId,
      accountId: dbo.accountId,
      devicePublicKeyBase64: dbo.devicePublicKeyBase64,
      deviceEncryptionPublicKeyBase64: dbo.deviceEncryptionPublicKeyBase64,
      encryptionKeyVersion: dbo.encryptionKeyVersion,
      status: DeviceStatus.fromStatusId(dbo.status),
      createdAt: dbo.createdAt,
      updatedAt: dbo.updatedAt,
      revokedAt: dbo.revokedAt,
      revocationReason: dbo.revocationReason,
    );
  }
}
