import 'dart:async';
import 'supabase_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';
import 'logger_service.dart';

/// Servicio para sincronizar datos locales con Supabase cuando hay conexión.
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final _supabase = SupabaseService();
  final _isar = IsarService();
  final _connectivity = ConnectivityService();
  final _logger = LoggerService();
  
  bool _isSyncing = false;
  Timer? _syncTimer;

  void initialize() {
    // Escuchar cambios de conectividad
    _connectivity.statusStream.listen((isOnline) {
      if (isOnline) {
        _logger.debug('[SyncService] Detectado ONLINE: Iniciando sincronización...');
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
    _logger.debug('[SyncService] Iniciando ciclo de sincronización...');

    try {
      await _syncEncounters();
      await _syncMessages();
      _logger.debug('[SyncService] Sincronización completada con éxito.');
    } catch (e) {
      _logger.debug('[SyncService] Error durante la sincronización: $e');
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _syncEncounters() async {
    final unsynced = await _isar.getUnsyncedEncounters();
    if (unsynced.isEmpty) return;

    _logger.debug('[SyncService] Sincronizando ${unsynced.length} encuentros...');
    for (final enc in unsynced) {
      try {
        final userId = enc.userId;
        final otherZoneId = enc.otherZoneId;
        
        await _supabase.registerEncounter(userId, otherZoneId);
        await _isar.markEncounterSynced(enc.id);
      } catch (e) {
        _logger.debug('[SyncService] Error sincronizando encuentro ${enc.id}: $e');
      }
    }
  }

  Future<void> _syncMessages() async {
    final unsynced = await _isar.getUnsyncedMessages();
    if (unsynced.isEmpty) return;

    _logger.debug('[SyncService] Sincronizando ${unsynced.length} mensajes...');
    for (final msg in unsynced) {
      try {
        // Los mensajes P2P se sincronizan cuando hay conexión a Supabase
        // Se asume que hay un match_id válido en Supabase
        if (msg.matchId.isNotEmpty) {
          await _supabase.sendMessage(
            matchId: msg.matchId,
            senderId: msg.senderId,
            encryptedContent: msg.encryptedContent,
            nonce: msg.nonce,
            mac: msg.mac,
          );
          await _isar.markMessageSynced(msg.id);
        }
      } catch (e) {
        _logger.debug('[SyncService] Error sincronizando mensaje ${msg.id}: $e');
      }
    }
  }

  void dispose() {
    _syncTimer?.cancel();
  }
}
