import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'chat_e2ee_service.dart';

/// Servicio que gestiona el ID único ZONE- del usuario.
/// Lo genera, persiste localmente y lo registra en Supabase.
class ZoneIdService {
  static final ZoneIdService _instance = ZoneIdService._internal();
  factory ZoneIdService() => _instance;
  ZoneIdService._internal();

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static const _keyZoneId = 'zone_id';
  static const _keySupabaseSession = 'supabase_uid';

  final _supabase = Supabase.instance.client;
  final _e2ee = ChatE2EEService();

  String? _zoneId;
  String? _uid;

  String? get zoneId => _zoneId;
  String? get uid => _uid;

  // ──────────────────────────────────────────────────────────
  //  Inicialización principal (llamar en main o AuthScreen)
  // ──────────────────────────────────────────────────────────

  /// Obtiene o crea el ID ZONE- del usuario.
  /// Si ya existe en local, lo restaura. Si no, genera uno nuevo
  /// y lo registra en Supabase de forma anónima.
  Future<String> getOrCreate() async {
    // 1. Intentar restaurar desde almacenamiento seguro local
    final storedId = await _storage.read(key: _keyZoneId);
    if (storedId != null && storedId.isNotEmpty) {
      _zoneId = storedId;
      // Restaurar sesión en Supabase si existe
      await _restoreSession();
      return _zoneId!;
    }

    // 2. No existe → crear nuevo
    _zoneId = _generateZoneId();
    await _storage.write(key: _keyZoneId, value: _zoneId);

    // 3. Registrar en Supabase anónimamente
    await _registerInSupabase();

    return _zoneId!;
  }

  // ──────────────────────────────────────────────────────────
  //  Registro en Supabase (auth anónimo + insert users)
  // ──────────────────────────────────────────────────────────

  Future<void> _registerInSupabase() async {
    try {
      // Auth anónimo (Supabase genera JWT sin email ni teléfono)
      final response = await _supabase.auth.signInAnonymously();
      final user = response.user;
      if (user == null) return;

      _uid = user.id;
      await _storage.write(key: _keySupabaseSession, value: _uid);

      // Generar par de claves E2EE
      final keyPair = await _e2ee.generateKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBase64 = _bytesToBase64(publicKey.bytes);

      // Guardar en Supabase
      await _supabase.from('users').insert({
        'id': _uid,
        'zone_id': _zoneId,
        'public_key': publicKeyBase64,
        'stealth_mode': false,
      });

      // Persistir clave pública localmente
      await _storage.write(key: 'public_key', value: publicKeyBase64);
    } catch (e) {
      print('[ZoneIdService] Error al registrar en Supabase: $e');
    }
  }

  Future<void> _restoreSession() async {
    try {
      // Si ya hay una sesión activa de Supabase, re-usarla
      final session = _supabase.auth.currentSession;
      if (session != null) {
        _uid = session.user.id;
        return;
      }

      // Si no, intentar recuperar usando el uid guardado
      final storedUid = await _storage.read(key: _keySupabaseSession);
      if (storedUid != null) {
        _uid = storedUid;
        // Reconectar llamando a signInAnonymously crea una nueva sesión
        // pero mantenemos el mismo zone_id en DB, no duplicamos usuario
      }
    } catch (e) {
      print('[ZoneIdService] Error al restaurar sesión: $e');
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Actualizar perfil
  // ──────────────────────────────────────────────────────────

  Future<void> updateProfile({
    required String displayName,
    String? instagram,
    bool igVisible = true,
    String? facebook,
    bool fbVisible = true,
    String? tiktok,
    bool tiktokVisible = true,
  }) async {
    if (_uid == null) return;
    try {
      await _supabase.from('users').update({
        'display_name': displayName,
        'instagram_handle': instagram,
        'ig_visible': igVisible,
        'facebook_handle': facebook,
        'fb_visible': fbVisible,
        'tiktok_handle': tiktok,
        'tiktok_visible': tiktokVisible,
      }).eq('id', _uid!);
    } catch (e) {
      print('[ZoneIdService] Error al actualizar perfil: $e');
    }
  }

  Future<void> setStealthMode(bool enabled) async {
    if (_uid == null) return;
    await _supabase.from('users').update({'stealth_mode': enabled}).eq('id', _uid!);
  }

  // ──────────────────────────────────────────────────────────
  //  Obtener perfil propio
  // ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMyProfile() async {
    if (_uid == null) return null;
    final res = await _supabase.from('users').select().eq('id', _uid!).single();
    return res;
  }

  // ──────────────────────────────────────────────────────────
  //  Generación del ID
  // ──────────────────────────────────────────────────────────

  String _generateZoneId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    String code = String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
    return 'ZONE-$code';
  }

  String _bytesToBase64(List<int> bytes) {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    final b = bytes;
    var result = '';
    for (var i = 0; i < b.length - 2; i += 3) {
      result += chars[(b[i] >> 2) & 0x3F];
      result += chars[((b[i] & 0x3) << 4) | ((b[i + 1] & 0xF0) >> 4)];
      result += chars[((b[i + 1] & 0xF) << 2) | ((b[i + 2] & 0xC0) >> 6)];
      result += chars[b[i + 2] & 0x3F];
    }
    if (b.length % 3 == 1) {
      result += chars[(b[b.length - 1] >> 2) & 0x3F];
      result += chars[(b[b.length - 1] & 0x3) << 4];
      result += '==';
    } else if (b.length % 3 == 2) {
      result += chars[(b[b.length - 2] >> 2) & 0x3F];
      result += chars[((b[b.length - 2] & 0x3) << 4) | ((b[b.length - 1] & 0xF0) >> 4)];
      result += chars[(b[b.length - 1] & 0xF) << 2];
      result += '=';
    }
    return result;
  }

  Future<void> clearLocalData() async {
    await _storage.deleteAll();
    await _supabase.auth.signOut();
    _zoneId = null;
    _uid = null;
  }
}
