import 'dart:async';
import 'dart:math';
import 'match_outbox_processor.dart';
import 'supabase_service.dart';
import 'isar_service.dart';
import 'connectivity_service.dart';
import 'logger_service.dart';

enum SyncState { idle, syncing, error }

class SyncStatus {
  final SyncState state;
  final int pendingMessages;
  final int pendingEncounters;
  final int pendingMatchOps;
  final int failedMatchOps;
  final String? error;
  final DateTime? lastSyncAt;

  const SyncStatus({
    this.state = SyncState.idle,
    this.pendingMessages = 0,
    this.pendingEncounters = 0,
    this.pendingMatchOps = 0,
    this.failedMatchOps = 0,
    this.error,
    this.lastSyncAt,
  });
}

/// Servicio para sincronizar datos locales con Supabase cuando hay conexión.
/// Z-307: el comentario previo afirmaba "sync bidireccional" — la
/// implementación real es: outbox de mensajes (push idempotente Z-007) +
/// backoff exponencial. La sincronización inversa (pull) vive en el chat
/// (abre directo desde `messages` de Supabase con merge Isar+server).
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
  StreamSubscription<bool>? _connectivitySub;
  int _consecutiveFailures = 0;
  static const int _maxBackoffMinutes = 30;

  final _statusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get statusStream => _statusController.stream;

  SyncStatus _currentStatus = const SyncStatus();
  SyncStatus get currentStatus => _currentStatus;

  void initialize() {
    _connectivitySub = _connectivity.statusStream.listen((isOnline) {
      if (isOnline) {
        _logger.debug('[SyncService] ONLINE detectado — sync inmediato');
        // PHASE 2.2.5: reconexión = señal fresca → el outbox ignora backoff.
        syncNow(urgent: true);
      }
    });

    _schedulePeriodicSync();
  }

  void _schedulePeriodicSync() {
    _syncTimer?.cancel();
    final baseInterval = const Duration(minutes: 15);
    final backoffMinutes = min(_consecutiveFailures * 5, _maxBackoffMinutes);
    final interval = baseInterval + Duration(minutes: backoffMinutes);
    _syncTimer = Timer.periodic(interval, (_) {
      if (_connectivity.isOnline) syncNow();
    });
  }

  Future<void> syncNow({bool urgent = false}) async {
    if (_isSyncing || !_connectivity.isOnline) return;
    _isSyncing = true;
    _emitStatus(state: SyncState.syncing);
    _logger.debug('[SyncService] Iniciando ciclo de sincronización...');

    try {
      await _flushPendingMessages();
      await _syncEncounters();
      // PHASE 2.2.5: replay convergente del outbox de matches (no regresa
      // encounters/mensajes; serie dentro del mismo ciclo, sin paralelismo).
      await _syncMatchOutbox(ignoreBackoff: urgent);
      await _pullRemoteProfiles();
      await _syncMessages();
      _consecutiveFailures = 0;
      _emitStatus(state: SyncState.idle, lastSyncAt: DateTime.now());
      _logger.debug('[SyncService] Sincronización completada con éxito.');
    } catch (e) {
      _consecutiveFailures++;
      _schedulePeriodicSync();
      _emitStatus(state: SyncState.error, error: '$e');
      _logger.debug('[SyncService] Error durante la sincronización: $e');
    } finally {
      _isSyncing = false;
    }
  }

  void _emitStatus({
    SyncState? state,
    String? error,
    DateTime? lastSyncAt,
  }) async {
    final pending = await _isar.getPendingMessages();
    final unsyncedEnc = await _isar.getUnsyncedEncounters();
    final store = IsarMatchOperationStore(_isar);
    _currentStatus = SyncStatus(
      state: state ?? _currentStatus.state,
      pendingMessages: pending.length,
      pendingEncounters: unsyncedEnc.length,
      pendingMatchOps: await store.pendingCount(),
      failedMatchOps: await store.failedCount(),
      error: error ?? (state == SyncState.error ? _currentStatus.error : null),
      lastSyncAt: lastSyncAt ?? _currentStatus.lastSyncAt,
    );
    _statusController.add(_currentStatus);
  }

  // ─── PUSH: Pending Messages (cola offline) ──────────────────────

  Future<void> _flushPendingMessages() async {
    final pending = await _isar.getPendingMessages();
    if (pending.isEmpty) return;

    _logger.debug('[SyncService] Enviando ${pending.length} mensajes offline...');
    final batch = pending.map((p) => {
      // Z-007: idempotencia del outbox — reutilizar el messageId ESTABLE que la
      // app generó UNA vez (PK remota). Si un reintento generara un id nuevo
      // aquí, duplicaría el mensaje en remoto. ON CONFLICT (id) → no-op.
      'id': p.messageId,
      'match_id': p.matchId,
      'sender_id': p.senderId,
      'encrypted_content': p.encryptedContent,
      'nonce': p.nonce,
      'mac': p.mac,
      'created_at': p.createdAt.toUtc().toIso8601String(),
    }).toList();

    final sentIds = await _supabase.sendMessagesBatch(batch);
    _logger.debug(
      '[SyncService] ${sentIds.length}/${pending.length} mensajes enviados',
    );

    for (final p in pending) {
      if (sentIds.contains(p.messageId)) {
        await _isar.deletePendingMessage(p.tempId);
      } else {
        await _isar.incrementRetryCount(p.tempId);
      }
    }
  }

  // ─── PUSH: Encounters ──────────────────────────────────────────

  Future<void> _syncEncounters() async {
    final unsynced = await _isar.getUnsyncedEncounters();
    if (unsynced.isEmpty) return;

    _logger.debug('[SyncService] Sincronizando ${unsynced.length} encuentros...');
    for (final enc in unsynced) {
      final ok = await _supabaseWithRetry(
        // PHASE 2.2.3 — la clave canónica viaja con la fila: el UPSERT remoto
        // sobre (user_id, encounter_key) converge sin duplicados aunque A
        // estuviera offline y B online. Filas históricas (clave nula) usan el
        // INSERT clásico, legibles como antes.
        () async {
          final accepted = await _supabase.registerEncounter(
            enc.userId,
            enc.otherZoneId,
            encounterKey: enc.encounterKey,
          );
          if (!accepted) {
            throw StateError('registerEncounter rechazado');
          }
        },
        label: 'encounter_${enc.id}',
      );
      if (ok) await _isar.markEncounterSynced(enc.id);
    }
  }

  // ─── PUSH: Match outbox (PHASE 2.2.5) ──────────────────────

  Future<void> _syncMatchOutbox({bool ignoreBackoff = false}) async {
    try {
      final summary = await MatchOutboxProcessor.processAll(
        store: IsarMatchOperationStore(_isar),
        backend: LiveMatchOutboxBackend(_supabase),
        isOnline: () async => _connectivity.isOnline,
        clock: DateTime.now,
        ignoreBackoff: ignoreBackoff,
      );
      if (summary.processed > 0) {
        _logger.debug(
          '[SyncService] Match outbox: ${summary.processed} procesadas, '
          '${summary.completed} completadas, ${summary.retried} reintentables, '
          '${summary.failedTerminal} terminales.',
        );
      }
    } catch (e) {
      _logger.debug('[SyncService] Error en match outbox: $e');
    }
  }

  // ─── PUSH: Messages (Isar → Supabase) ──────────────────────────

  Future<void> _syncMessages() async {
    final unsynced = await _isar.getUnsyncedMessages();
    if (unsynced.isEmpty) return;

    _logger.debug('[SyncService] Sincronizando ${unsynced.length} mensajes Isar...');
    for (final msg in unsynced) {
      if (msg.matchId.isEmpty) continue;
      final ok = await _supabaseWithRetry(
        () async {
          final accepted = await _supabase.sendMessageIdempotent(
            messageId: msg.messageId,
            matchId: msg.matchId,
            senderId: msg.senderId,
            encryptedContent: msg.encryptedContent,
            nonce: msg.nonce,
            mac: msg.mac,
          );
          if (!accepted) {
            throw StateError('sendMessageIdempotent rechazado');
          }
        },
        label: 'msg_${msg.id}',
      );
      if (ok) await _isar.markMessageSynced(msg.id);
    }
  }

  // ─── PULL: Remote profiles → Isar (CRDT LWW) ──────────────────

  Future<void> _pullRemoteProfiles() async {
    try {
      final recentProfiles = await _supabase.getRecentlyActiveProfiles();
      if (recentProfiles.isEmpty) return;

      _logger.debug('[SyncService] Pull ${recentProfiles.length} perfiles remotos...');
      int merged = 0;
      final now = DateTime.now().toUtc();
      final maxFuture = now.add(const Duration(minutes: 5));
      for (final profile in recentProfiles) {
        final local = await _isar.getProfileByUserId(profile['id']);
        final rawUpdated = profile['updated_at'] ?? profile['created_at'];
        var remoteUpdated = rawUpdated is String
            ? (DateTime.tryParse(rawUpdated)?.toUtc() ?? now)
            : now;
        // Un timestamp remoto futuro lejano no debe ganar el LWW para siempre.
        if (remoteUpdated.isAfter(maxFuture)) remoteUpdated = now;
        final localUpdated = local?.updatedAt.toUtc() ??
            DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

        if (remoteUpdated.isAfter(localUpdated)) {
          await _isar.saveProfile(profile);
          merged++;
        }
      }
      _logger.debug('[SyncService] $merged perfiles actualizados vía LWW');
    } catch (e) {
      _logger.debug('[SyncService] Error en pull de perfiles: $e');
    }
  }

  // ─── Helper: Retry con backoff exponencial ─────────────────────

  Future<bool> _supabaseWithRetry(
    Future<void> Function() operation, {
    int maxRetries = 3,
    String label = '',
  }) async {
    final random = Random();
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        await operation();
        return true;
      } catch (e) {
        if (attempt == maxRetries) {
          _logger.debug('[SyncService] $label: $maxRetries+1 intentos fallidos');
          return false;
        }
        final delay = Duration(
          milliseconds: 1000 * (1 << attempt) + random.nextInt(500),
        );
        await Future.delayed(delay);
      }
    }
    return false;
  }

  // ─── Utilities ─────────────────────────────────────────────────

  int get pendingCount => _currentStatus.pendingMessages + _currentStatus.pendingEncounters;

  void dispose() {
    _connectivitySub?.cancel();
    _syncTimer?.cancel();
    _statusController.close();
  }
}
