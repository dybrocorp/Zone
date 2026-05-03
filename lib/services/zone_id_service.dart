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
      // 1. Iniciar sesión anónima PRIMERO para obtener el rol "authenticated"
      // Esto es OBLIGATORIO porque configuramos RLS: TO authenticated en Supabase
      final response = await _supabase.auth.signInAnonymously();
      if (response.user == null) return false;

      // 2. Verificar que el ID existe en Supabase usando RPC (Bypass RLS)
      print('[ZoneIdService] Verificando ID: $zoneId');
      final result = await _supabase.rpc('verify_zone_id', params: {'p_zone_id': zoneId});
      
      if (result == null) {
        print('[ZoneIdService] ID no encontrado en DB: $zoneId');
        await _supabase.auth.signOut(); 
        return false;
      }

      print('[ZoneIdService] ID verificado con éxito: $zoneId');

      // 3. Guardar localmente y adueñarse de la row
      _zoneId = zoneId;
      _uid = response.user!.id; // El nuevo UID anónimo

      await _storage.write(key: _keyZoneId, value: _zoneId);
      await _storage.write(key: _keySupabaseSession, value: _uid);
      
      // 4. Actualizar la base de datos para que este dispositivo sea el nuevo "dueño" del ZONE-ID
      // Usamos RPC para saltarnos el bloqueo de RLS en el handover de ID
      await _supabase.rpc('claim_zone_id', params: {'p_zone_id': zoneId});
      
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
    try {
      // Auth anónimo (Supabase genera JWT sin email ni teléfono)
      final response = await _supabase.auth.signInAnonymously();
      final user = response.user;
      if (user == null) throw Exception('No se pudo iniciar sesión anónima en Supabase Auth');

      _uid = user.id;
      await _storage.write(key: _keySupabaseSession, value: _uid);

      // Generar par de claves E2EE
      final keyPair = await _e2ee.generateKeyPair();
      final publicKey = await keyPair.extractPublicKey();
      final publicKeyBase64 = _bytesToBase64(publicKey.bytes);

      print('[ZoneIdService] Registrando usuario en public.users: $_uid ($_zoneId)');
      
      // Guardar en Supabase (usamos upsert para evitar errores si ya existe)
      await _supabase.from('users').upsert({
        'id': _uid,
        'zone_id': _zoneId,
        'public_key': publicKeyBase64,
        'stealth_mode': false,
      });

      // Verificar que realmente se insertó
      final check = await _supabase.from('users').select().eq('id', _uid!).maybeSingle();
      if (check == null) {
        throw Exception('El registro en public.users falló. Verifica las políticas RLS o conexión.');
      }

      // Persistir clave pública localmente
      await _storage.write(key: 'public_key', value: publicKeyBase64);
      print('[ZoneIdService] Registro exitoso para $_zoneId');
    } catch (e) {
      print('[ZoneIdService] ERROR CRÍTICO EN REGISTRO: $e');
      rethrow;
    }
  }

  /// Asegura que el UID y la sesión de Auth estén listos.
  Future<void> _ensureAuth() async {
    final oldUid = await _storage.read(key: _keySupabaseSession);

    // 1. Verificar sesión de Supabase Auth
    final session = _supabase.auth.currentSession;
    String newUid;

    if (session == null) {
      // Intentar reconexión anónima
      final response = await _supabase.auth.signInAnonymously();
      if (response.user == null) {
        throw Exception('No se pudo establecer sesión anónima.');
      }
      newUid = response.user!.id;
    } else {
      newUid = session.user.id;
    }

    _uid = newUid;
    await _storage.write(key: _keySupabaseSession, value: _uid);

    final currentZoneId = _zoneId ?? await _storage.read(key: _keyZoneId);
    _zoneId = currentZoneId;

    // 2. Si tenemos un ZONE-ID, nos aseguramos de que el UID actual sea el dueño en Supabase.
    // Usamos el RPC claim_zone_id que es idempotente y seguro (Security Definer).
    if (currentZoneId != null) {
      try {
        await _supabase.rpc('claim_zone_id', params: {'p_zone_id': currentZoneId});
      } catch (e) {
        print('[ZoneIdService] Aviso: Error al reclamar Zone ID en el inicio: $e');
      }
    }
  }

  Future<void> _restoreSession() async {
    try {
      await _ensureAuth();
      await checkAndFixRegistration(); // Auto-sanación si falta la fila en DB
    } catch (e) {
      print('[ZoneIdService] Error al restaurar sesión: $e');
    }
  }

  /// Verifica si el usuario actual tiene su fila en la tabla 'users'.
  /// Si no existe (ej: borrado manual de DB o fallo previo), la intenta recrear.
  Future<void> checkAndFixRegistration() async {
    if (_uid == null || _zoneId == null) return;

    try {
      final res = await _supabase.from('users').select().eq('id', _uid!).maybeSingle();
      if (res == null) {
        print('[ZoneIdService] Alerta: Fila de usuario no encontrada. Recreando...');
        
        // Generar par de claves E2EE si no tenemos una guardada
        String? publicKeyBase64 = await _storage.read(key: 'public_key');
        if (publicKeyBase64 == null) {
          final keyPair = await _e2ee.generateKeyPair();
          final publicKey = await keyPair.extractPublicKey();
          publicKeyBase64 = _bytesToBase64(publicKey.bytes);
          await _storage.write(key: 'public_key', value: publicKeyBase64);
        }

        await _supabase.from('users').upsert({
          'id': _uid,
          'zone_id': _zoneId,
          'public_key': publicKeyBase64,
          'stealth_mode': false,
        });
        print('[ZoneIdService] Fila de usuario recreada con éxito.');
      }
    } catch (e) {
      print('[ZoneIdService] Error en checkAndFixRegistration: $e');
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
    // Entrar a asegurar la sesión
    await _ensureAuth();
    
    // Obtener la clave pública guardada localmente
    String? publicKey = await _storage.read(key: 'public_key');
    
    // Si no hay clave (caso extremo de pérdida local), generamos una nueva para no violar el NOT NULL
    if (publicKey == null) {
      final keyPair = await _e2ee.generateKeyPair();
      final pubKeyBytes = await keyPair.extractPublicKey();
      publicKey = _bytesToBase64(pubKeyBytes.bytes);
      await _storage.write(key: 'public_key', value: publicKey);
    }
    
    // Usamos UPSERT de forma defensiva por si el registro inicial en public.users falló.
    // Incluir public_key es obligatorio porque tiene restricción NOT NULL en la DB.
    await _supabase.from('users').upsert({
      'id': _uid,
      'zone_id': _zoneId,
      'display_name': displayName,
      'public_key': publicKey,
      'instagram_handle': instagram,
      'ig_visible': igVisible,
      'facebook_handle': facebook,
      'fb_visible': fbVisible,
      'tiktok_handle': tiktok,
      'tiktok_visible': tiktokVisible,
      'avatar_url': avatarUrl,
    });
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
    
    // 1. Eliminar archivos de almacenamiento (Storage API oficial)
    try {
      final userFolder = _uid!;
      // Listamos los archivos del usuario para borrarlos
      final files = await _supabase.storage.from('profiles').list(path: userFolder);
      if (files.isNotEmpty) {
        final pathsToDelete = files.map((f) => '$userFolder/${f.name}').toList();
        await _supabase.storage.from('profiles').remove(pathsToDelete);
      }
    } catch (e) {
      print('Aviso: Fallo borrando storage, continuando con el perfil... \$e');
    }

    // 2. Llamar a la función de borrado total en Supabase (RPC)
    // Esto borra datos en public (usuarios, chats, tokens) y auth.
    await _supabase.rpc('delete_own_account');
    
    // 2. Limpiar todo el estado local
    await clearAuth();
  }

  /// Limpia la sesión local y los chats mock.
  Future<void> clearAuth() async {
    await _storage.delete(key: _keyZoneId);
    await _storage.delete(key: _keySupabaseSession);
    await _supabase.auth.signOut();
    _zoneId = null;
    _uid = null;
  }
}
