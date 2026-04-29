import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'chat_e2ee_service.dart';
import 'package:path/path.dart' as p;

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

  /// Verifica si ya existe un ID guardado localmente
  Future<bool> hasLocalID() async {
    final storedId = await _storage.read(key: _keyZoneId);
    return storedId != null && storedId.isNotEmpty;
  }

  /// Obtiene o crea el ID ZONE- del usuario.
  /// Se llama solo cuando estamos seguros de que queremos iniciar/restaurar.
  Future<String> getOrCreate() async {
    // 1. Intentar restaurar desde almacenamiento seguro local
    final storedId = await _storage.read(key: _keyZoneId);
    if (storedId != null && storedId.isNotEmpty) {
      _zoneId = storedId;
      await _restoreSession();
      return _zoneId!;
    }

    // 2. No existe → crear nuevo
    _zoneId = _generateZoneId();
    await _storage.write(key: _keyZoneId, value: _zoneId);

    // 3. Registrar en Supabase anónimamente
    try {
      await _registerInSupabase();
    } catch (e) {
      print('[ZoneIdService] Error crítico en registro: $e');
      rethrow;
    }

    return _zoneId!;
  }

  /// Permite a un usuario con un ID existente (ej: en otro dispositivo)
  /// "iniciar sesión" y recuperar su perfil.
  Future<bool> loginWithExistingID(String zoneId) async {
    try {
      // 1. Verificar que el ID existe en Supabase
      final profile = await _supabase.from('users').select().eq('zone_id', zoneId).maybeSingle();
      if (profile == null) return false;

      // 2. Guardar localmente
      _zoneId = zoneId;
      _uid = profile['id'];
      await _storage.write(key: _keyZoneId, value: _zoneId);
      await _storage.write(key: _keySupabaseSession, value: _uid);
      
      // 3. Iniciar sesión anónima en Supabase para obtener JWT fresco
      // Nota: Dado que es anónimo, el nuevo UID podría diferir si no lo forzamos.
      // Sin embargo, para este modelo de ZONE-, el UID de Auth suele estar ligado al dispositivo.
      // Si el usuario cambia de dispositivo, se le asigna un nuevo UID de Auth.
      // Pero el `users.id` (PK) debe coincidir con el `auth.uid()`.
      
      final response = await _supabase.auth.signInAnonymously();
      if (response.user != null) {
         // Si el UID cambió, actualizamos la tabla users para que este dispositivo sea el nuevo "dueño"
         // (O podrías usar un sistema de tokens compartido, pero simplificamos para el demo)
         final newUid = response.user!.id;
         await _supabase.from('users').update({'id': newUid}).eq('zone_id', zoneId);
         _uid = newUid;
         await _storage.write(key: _keySupabaseSession, value: _uid);
      }
      
      return true;
    } catch (e) {
      print('[ZoneIdService] Error en loginWithExistingID: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────
  //  Registro en Supabase (auth anónimo + insert users)
  // ──────────────────────────────────────────────────────────

  Future<void> _registerInSupabase() async {
    // Auth anónimo (Supabase genera JWT sin email ni teléfono)
    final response = await _supabase.auth.signInAnonymously();
    final user = response.user;
    if (user == null) throw Exception('No se pudo iniciar sesión anónima');

    _uid = user.id;
    await _storage.write(key: _keySupabaseSession, value: _uid);

    // Generar par de claves E2EE
    final keyPair = await _e2ee.generateKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    final publicKeyBase64 = _bytesToBase64(publicKey.bytes);

    // Guardar en Supabase (usamos upsert para evitar errores si ya existe)
    await _supabase.from('users').upsert({
      'id': _uid,
      'zone_id': _zoneId,
      'public_key': publicKeyBase64,
      'stealth_mode': false,
    });

    // Verificar que realmente se insertó (opcional pero seguro)
    final check = await _supabase.from('users').select().eq('id', _uid!).maybeSingle();
    if (check == null) throw Exception('No se pudo crear el registro de usuario en la base de datos');

    // Persistir clave pública localmente
    await _storage.write(key: 'public_key', value: publicKeyBase64);
  }

  /// Asegura que el UID y la sesión de Auth estén listos.
  Future<void> _ensureAuth() async {
    // 1. Si no hay UID en memoria, intentar restaurar desde almacenamiento
    if (_uid == null) {
      final storedUid = await _storage.read(key: _keySupabaseSession);
      _uid = storedUid;
    }

    // 2. Verificar sesión de Supabase Auth
    final session = _supabase.auth.currentSession;
    if (session == null) {
      // Intentar reconexión anónima (esto mantiene el mismo UID si ya existía uno en Auth)
      final response = await _supabase.auth.signInAnonymously();
      if (response.user != null) {
        _uid = response.user!.id;
        await _storage.write(key: _keySupabaseSession, value: _uid);
      }
    } else {
      _uid = session.user.id;
    }

    if (_uid == null) {
      throw Exception('No se pudo establecer una sesión válida. Por favor, reinicia la app.');
    }
  }

  Future<void> _restoreSession() async {
    try {
      await _ensureAuth();
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
    String? avatarUrl,
  }) async {
    await _ensureAuth();
    
    await _supabase.from('users').update({
      'display_name': displayName,
      'instagram_handle': instagram,
      'ig_visible': igVisible,
      'facebook_handle': facebook,
      'fb_visible': fbVisible,
      'tiktok_handle': tiktok,
      'tiktok_visible': tiktokVisible,
      'avatar_url': avatarUrl,
    }).eq('id', _uid!);
  }

  /// Sube una imagen al bucket 'profiles' y devuelve la URL pública.
  Future<String> uploadProfilePicture(File file) async {
    await _ensureAuth();
    
    final extension = p.extension(file.path);
    final fileName = '$_uid/avatar${DateTime.now().millisecondsSinceEpoch}$extension';
    
    // Subir archivo (sobrescribe si existe en la misma ruta, pero usamos timestamp para evitar cache)
    await _supabase.storage.from('profiles').upload(
      fileName,
      file,
      fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
    );
    
    // Obtener URL pública
    final String publicUrl = _supabase.storage.from('profiles').getPublicUrl(fileName);
    return publicUrl;
  }

  Future<void> setStealthMode(bool enabled) async {
    if (_uid == null) return;
    await _supabase.from('users').update({'stealth_mode': enabled}).eq('id', _uid!);
  }

  // ──────────────────────────────────────────────────────────
  //  Obtener perfil propio
  // ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      await _ensureAuth();
      if (_uid == null) return null;
      
      final res = await _supabase.from('users').select().eq('id', _uid!).single();
      return res;
    } catch (e) {
      print('[ZoneIdService] Error en getMyProfile: $e');
      return null;
    }
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

  Future<void> deleteAccount() async {
    await _ensureAuth();
    if (_uid == null) return;
    
    // 1. Llamar a la función de borrado total en Supabase (RPC)
    // Esto borra datos en public, storage y auth.
    await _supabase.rpc('delete_own_account');
    
    // 2. Limpiar todo el estado local
    await clearAuth();
  }

  Future<void> clearAuth() async {
    await _storage.deleteAll();
    await _supabase.auth.signOut();
    _zoneId = null;
    _uid = null;
  }
}
