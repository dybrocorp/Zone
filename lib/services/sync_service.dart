import 'dart:async';
import 'supabase_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';

/// Servicio para sincronizar datos locales con Supabase cuando hay conexión.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _supabase = SupabaseService();
  final _isar = IsarService();
  final _connectivity = ConnectivityService();
  
  bool _isSyncing = false;
  Timer? _syncTimer;

  void initialize() {
    // Escuchar cambios de conectividad
    _connectivity.statusStream.listen((isOnline) {
      if (isOnline) {
        print('[SyncService] Detectado ONLINE: Iniciando sincronización...');
        syncNow();
      }
    });

    // Sincronización periódica cada 15 minutos (si hay conexión)
    _syncTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (_connectivity.isOnline) {
        syncNow();
      }
    });
  }

  Future<void> syncNow() async {
    if (_isSyncing || !_connectivity.isOnline) return;
    _isSyncing = true;
    print('[SyncService] Iniciando ciclo de sincronización...');

    try {
      await _syncEncounters();
      await _syncMessages();
      print('[SyncService] Sincronización completada con éxito.');
    } catch (e) {
      print('[SyncService] Error durante la sincronización: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncEncounters() async {
    final unsynced = await _isar.getUnsyncedEncounters();
    if (unsynced.isEmpty) return;

    print('[SyncService] Sincronizando ${unsynced.length} encuentros...');
    for (final enc in unsynced) {
      try {
        final userId = enc.userId;
        final otherZoneId = enc.otherZoneId;
        
        await _supabase.registerEncounter(userId, otherZoneId);
        await _isar.markEncounterSynced(enc.id);
      } catch (e) {
        print('[SyncService] Error sincronizando encuentro ${enc.id}: $e');
      }
    }
  }

  Future<void> _syncMessages() async {
    // TODO: Implementar lógica de sincronización de mensajes P2P hacia la nube
    // Por ahora el enfoque principal son los encuentros (radar).
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
