/// PHASE 2.2.1 — Persistencia de la migración de identidad (Isar).
///
/// NEW FOUNDATION EXTENSION — NOT YET INTEGRATED IN THE APP FLOW.
///
/// Registro SINGLETON (`kMigrationSingletonId`) en la instancia `zone_identity`
/// (dedicada, aislada de la base de mensajes legacy). Escrituras idempotentes
/// vía `putByMigrationId` (índice único + `replace: true`): reintentos o
/// re-aplicaciones no duplican. Fail-closed ante estado persistido corrupto:
/// nunca se materializa un estado ni un evento inventado.
library;

import 'package:isar/isar.dart';

import 'identity_errors.dart';
import 'migration_models.dart';
import 'migration_state_machine.dart';

/// Contrato del repositorio de migración. Permite inyectar un doble en memoria
/// en los tests de orquestación (los tests de Isar usan instancias temporales).
abstract class MigrationRepository {
  /// Registro actual de migración o null si nunca se persistió (⇒ LEGACY).
  Future<MigrationRecord?> load();

  /// Persiste el registro (singleton, upsert idempotente). Devuelve el valor
  /// persistido.
  Future<MigrationRecord> save(MigrationRecord record);
}

/// Implementación Isar del repositorio de migración.
class IsarMigrationRepository implements MigrationRepository {
  IsarMigrationRepository(this._isar);

  final Isar _isar;

  @override
  Future<MigrationRecord?> load() async {
    try {
      final dbo = await _isar.migrationDbos
          .filter()
          .migrationIdEqualTo(kMigrationSingletonId)
          .findFirst();
      return dbo == null ? null : _toRecord(dbo);
    } catch (e) {
      if (e is IdentityFoundationError) rethrow;
      throw IdentityPersistenceError('loadMigration failed: ${e.runtimeType}');
    }
  }

  @override
  Future<MigrationRecord> save(MigrationRecord record) async {
    try {
      final existing = await _isar.migrationDbos.where().findAll();
      final foreign = existing
          .where((d) => d.migrationId != kMigrationSingletonId)
          .toList();
      if (foreign.isNotEmpty) {
        // Nunca dos registros de migración por instalación.
        throw DuplicateIdentityRecordError(
          'migration',
          foreign.first.migrationId,
        );
      }
      final dbo = (existing.isEmpty ? MigrationDbo() : existing.first)
        ..migrationId = kMigrationSingletonId
        ..state = record.state.statusId
        ..createdAt = record.createdAt
        ..updatedAt = record.updatedAt
        ..lastEvent = record.lastEvent?.name
        ..attemptCount = record.attemptCount
        ..rollbackCount = record.rollbackCount
        ..legacyZoneId = record.legacyZoneId
        ..boundAccountId = record.boundAccountId
        ..boundDeviceId = record.boundDeviceId
        ..fingerprintAcc = record.fingerprintAcc
        ..fingerprintDev = record.fingerprintDev
        ..verificationChecksum = record.verificationChecksum
        ..failedCause = record.failedCause
        ..auditTrail = record.audit.join('\n');
      await _isar.writeTxn(() => _isar.migrationDbos.putByMigrationId(dbo));
      return record;
    } catch (e) {
      if (e is IdentityFoundationError) rethrow;
      throw IdentityPersistenceError('saveMigration failed: ${e.runtimeType}');
    }
  }

  static MigrationRecord _toRecord(MigrationDbo dbo) {
    final state = MigrationState.fromStatusId(dbo.state);
    final event = dbo.lastEvent == null
        ? null
        : _parseEvent(dbo.lastEvent!);
    final audit = (dbo.auditTrail == null || dbo.auditTrail!.isEmpty)
        ? const <String>[]
        : dbo.auditTrail!.split('\n');
    return MigrationRecord(
      state: state,
      lastEvent: event,
      attemptCount: dbo.attemptCount ?? 0,
      rollbackCount: dbo.rollbackCount ?? 0,
      legacyZoneId: dbo.legacyZoneId,
      boundAccountId: dbo.boundAccountId,
      boundDeviceId: dbo.boundDeviceId,
      fingerprintAcc: dbo.fingerprintAcc,
      fingerprintDev: dbo.fingerprintDev,
      verificationChecksum: dbo.verificationChecksum,
      failedCause: dbo.failedCause,
      audit: audit,
      createdAt: dbo.createdAt,
      updatedAt: dbo.updatedAt,
    );
  }

  /// Fail-closed: nombre de evento desconocido ⇒ [MigrationRecordCorruptError].
  static MigrationEvent? _parseEvent(String name) {
    for (final e in MigrationEvent.values) {
      if (e.name == name) return e;
    }
    throw MigrationRecordCorruptError('unknown migration event `$name`');
  }
}