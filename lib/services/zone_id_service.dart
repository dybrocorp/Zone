import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'chat_e2ee_service.dart';
import 'isar_service.dart';
import 'logger_service.dart';
import 'p2p_security_service.dart';

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
  static const _keyPrivateKey = 'private_key';
  static const _keyPublicKey = 'public_key';

  final _supabase = Supabase.instance.client;
  final _e2ee = ChatE2EEService();
  final _isar = IsarService();
  final _logger = LoggerService();

  String? _zoneId;
  String? _uid;

  String? get zoneId => _zoneId;
  String? get uid => _uid;

  // ──────────────────────────────────────────────────────────
  //  Inicialización principal (llamar en main o AuthScreen)
  // ──────────────────────────────────────────────────────────

  /// Verifica si ya existe un ID guardado localmente
  Future<bool> hasLocalID() async {
    final storedId = await _safeRead(_keyZoneId);
    return storedId != null && storedId.isNotEmpty;
  }

  /// Helper para leer de forma segura (evita BadPaddingException en algunos dispositivos)
  Future<String?> _safeRead(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (e) {
      _logger.debug('[ZoneIdService] Error leyendo $key: $e');
      // Si hay un error de cifrado (KeyStore corrupto), borramos la clave para permitir recuperación
      try {
        await _storage.delete(key: key);
      } catch (e2) {
        _logger.debug(
          '[ZoneIdService] Falló el borrado de clave corrupta: $e2',
        );
      }
      return null;
    }
  }

  /// Obtiene o crea el ID ZONE- del usuario.
  /// Se llama solo cuando estamos seguros de que queremos iniciar/restaurar.
  Future<String> getOrCreate() async {
    try {
      return await _getOrCreateInternal();
    } catch (e) {
      if (e.toString().contains('BadPaddingException') ||
          e.toString().contains('decryption')) {
        _logger.debug(
          '[ZoneIdService] Corrupción de almacenamiento detectada. Limpiando todo y reintentando...',
        );
        await _storage.deleteAll();
        return await _getOrCreateInternal();
      }
      rethrow;
    }
  }

  Future<String> _getOrCreateInternal() async {
    // 1. Intentar restaurar desde almacenamiento seguro local
    final storedId = await _safeRead(_keyZoneId);
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
      _logger.debug('[ZoneIdService] Error crítico en registro: $e');
      rethrow;
    }

    return _zoneId!;
  }

  /// Permite a un usuario con un ID existente (ej: en otro dispositivo)
  /// "iniciar sesión" y recuperar su perfil.
  Future<bool> loginWithExistingID(String zoneId) async {
    try {
      return await _loginWithExistingIDInternal(zoneId);
    } catch (e) {
      if (e.toString().contains('BadPaddingException') ||
          e.toString().contains('decryption')) {
        _logger.debug(
          '[ZoneIdService] Corrupción de almacenamiento detectada en login. Limpiando...',
        );
        await _storage.deleteAll();
        return await _loginWithExistingIDInternal(zoneId);
      }
      return false;
    }
  }

  Future<bool> _loginWithExistingIDInternal(String zoneId) async {
    try {
      // 1. Iniciar sesión anónima PRIMERO para obtener el rol "authenticated"
      // Esto es OBLIGATORIO porque configuramos RLS: TO authenticated en Supabase
      final response = await _supabase.auth.signInAnonymously();
      if (response.user == null) return false;

      // 3. Guardar localmente y adueñarse de la row
      _zoneId = zoneId;
      _uid = response.user!.id; // El nuevo UID anónimo

      await _storage.write(key: _keyZoneId, value: _zoneId);
      await _storage.write(key: _keySupabaseSession, value: _uid);

      // 4. Formato primero (el RPC valida igual server-side, pero evitamos
      //    trabajo y rate-limit innecesarios)
      if (!isValidZoneIdFormat(zoneId)) {
        _logger.debug('[ZoneIdService] Formato de ZONE-ID inválido en login.');
        return false;
      }

      // 5. Reclamar la propiedad del ZONE-ID (RPC endurecido por Z-001 Fase A).
      //    Z-002: claim_zone_id RETORNA el perfil completo tras migrar la fila a
      //    este UID, así el login NO relee 'users' (ahora self-scoped) y no
      //    reintroduce la fuga de perfiles. El RPC ya NO acepta p_public_key.
      final claimed = await _supabase.rpc(
        'claim_zone_id',
        params: {'p_zone_id': zoneId},
      );

      // 6. Persistir localmente el perfil recuperado (display_name, avatar, handles)
      if (claimed is Map) {
        final profileData = Map<String, dynamic>.from(claimed);
        _logger.debug(
          '[ZoneIdService] Perfil reclamado: nombre=${profileData['display_name']}, '
          'avatar=${profileData['avatar_url'] != null}',
        );
        await _isar.saveProfile({
          ...profileData,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      }

      // 7. ASEGURAR que las llaves E2EE se restauren o generen para esta nueva sesión
      await ensureAuth();

      return true;
    } catch (e) {
      _logger.debug('[ZoneIdService] Error en loginWithExistingID: $e');
      rethrow;
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
      if (user == null) {
        throw Exception('No se pudo iniciar sesión anónima en Supabase Auth');
      }

      _uid = user.id;
      await _storage.write(key: _keySupabaseSession, value: _uid);

      // Generar par de claves E2EE
      final keyPair = await _e2ee.generateKeyPair();
      final keyPairData = await keyPair.extract();
      final publicKeyBase64 = _bytesToBase64(keyPairData.publicKey.bytes);
      final privateKeyBase64 = _bytesToBase64(
        await keyPair.extractPrivateKeyBytes(),
      );

      _logger.debug(
        '[ZoneIdService] Registrando usuario en public.users: $_uid ($_zoneId)',
      );

      // Guardar en Supabase (usamos upsert para evitar errores si ya existe)
      await _supabase.from('users').upsert({
        'id': _uid,
        'zone_id': _zoneId,
        'public_key': publicKeyBase64,
        'stealth_mode': false,
      });

      // Verificar que realmente se insertó
      final check = await _supabase
          .from('users')
          .select()
          .eq('id', _uid!)
          .maybeSingle();
      if (check == null) {
        throw Exception(
          'El registro en public.users falló. Verifica las políticas RLS o conexión.',
        );
      }

      // Persistir claves localmente
      await _storage.write(key: _keyPublicKey, value: publicKeyBase64);
      await _storage.write(key: _keyPrivateKey, value: privateKeyBase64);
      _logger.debug('[ZoneIdService] Registro exitoso para $_zoneId');
    } catch (e) {
      _logger.debug('[ZoneIdService] ERROR CRÍTICO EN REGISTRO: $e');
      rethrow;
    }
  }

  /// Asegura que el UID y la sesión de Auth estén listos.
  Future<void> ensureAuth() async {
    await _safeRead(_keySupabaseSession);

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

    // Restaurar par de claves E2EE
    String? privateKeyBase64 = await _safeRead(_keyPrivateKey);

    // SI NO TENEMOS CLAVE LOCAL (usuario existente de antes de la persistencia o re-instalación)
    if (privateKeyBase64 == null) {
      _logger.debug(
        '[ZoneIdService] Clave privada no encontrada localmente. Generando una nueva...',
      );
      final keyPair = await _e2ee.generateKeyPair();
      final keyPairData = await keyPair.extract();
      privateKeyBase64 = _bytesToBase64(await keyPair.extractPrivateKeyBytes());

      final publicKeyBase64 = _bytesToBase64(keyPairData.publicKey.bytes);

      try {
        await _storage.write(key: _keyPrivateKey, value: privateKeyBase64);
        await _storage.write(key: _keyPublicKey, value: publicKeyBase64);
      } catch (e) {
        _logger.debug(
          '[ZoneIdService] Error escribiendo en keystore corrupto: $e. Forzando borrado.',
        );
        try {
          await _storage.deleteAll();
          await _storage.write(key: _keyPrivateKey, value: privateKeyBase64);
          await _storage.write(key: _keyPublicKey, value: publicKeyBase64);
        } catch (e2) {
          _logger.debug(
            '[ZoneIdService] No se pudo recuperar almacenamiento seguro: $e2',
          );
        }
      }

      // Marcar que necesitamos actualizar la pública en Supabase
    } else {
      await _e2ee.initFromPrivateBase64(privateKeyBase64);
    }

    // Z-207 (FASE 1.6): el claim del ZONE-ID NO se ejecuta en el arranque.
    // Reclamar el ID sin login explícito (con solo el ID local, visible en la
    // malla P2P) era la ventana de "cualquier reinicio re-autentica sin prueba
    // de posesión". El claim queda SOLO en el login explícito
    // (`loginWithExistingID` → RPC `claim_zone_id`), con formato + rate-limit.
  }

  Future<void> _restoreSession() async {
    try {
      await ensureAuth();
      await checkAndFixRegistration(); // Auto-sanación si falta la fila en DB
    } catch (e) {
      _logger.debug('[ZoneIdService] Error al restaurar sesión: $e');
    }
  }

  /// Verifica si el usuario actual tiene su fila en la tabla 'users'.
  /// Si no existe (ej: borrado manual de DB o fallo previo), la intenta recrear.
  /// SIEMPRE sincroniza la clave pública local con Supabase para evitar desincronización.
  Future<void> checkAndFixRegistration() async {
    if (_uid == null || _zoneId == null) return;

    try {
      final res = await _supabase
          .from('users')
          .select()
          .eq('id', _uid!)
          .maybeSingle();

      String? publicKeyBase64 = await _safeRead(_keyPublicKey);

      // Si no tenemos clave local, generamos una ahora
      if (publicKeyBase64 == null) {
        _logger.debug(
          '[ZoneIdService] Clave pública local no encontrada. Generando...',
        );
        final keyPair = await _e2ee.generateKeyPair();
        final keyPairData = await keyPair.extract();
        publicKeyBase64 = _bytesToBase64(keyPairData.publicKey.bytes);
        final privKey = _bytesToBase64(await keyPair.extractPrivateKeyBytes());

        await _storage.write(key: _keyPublicKey, value: publicKeyBase64);
        await _storage.write(key: _keyPrivateKey, value: privKey);
      }

      if (res == null) {
        _logger.debug(
          '[ZoneIdService] Alerta: Fila de usuario no encontrada. Recreando...',
        );
        await _supabase.from('users').upsert({
          'id': _uid,
          'zone_id': _zoneId,
          'public_key': publicKeyBase64,
          'stealth_mode': false,
        });
        _logger.debug('[ZoneIdService] Fila de usuario recreada con éxito.');
      } else {
        // Z-001 Fase A: la public_key archivada en Supabase ES la identidad E2EE.
        // NO se sobrescribe con la clave local sin prueba de posesión; la
        // rotación protegida llega en la Fase B (firma Ed25519 + códigos de
        // recuperación). La clave local de este dispositivo solo sirve para
        // el canal mesh actual.
        final dbKey = res['public_key']?.toString();
        _logger.debug(
          '[ZoneIdService] Clave en Supabase preservada '
          '(${dbKey?.substring(0, 8)}...). '
          'Rotación protegida pendiente de Z-001 Fase B.',
        );
      }
    } catch (e) {
      _logger.debug('[ZoneIdService] Error en checkAndFixRegistration: $e');
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
    bool avatarIsPublic = true,
    List<Map<String, dynamic>> galleryPhotos = const [],
  }) async {
    // Entrar a asegurar la sesión
    await ensureAuth();

    // Obtener la clave pública guardada localmente
    String? publicKey = await _safeRead(_keyPublicKey);

    // Si no hay clave (caso extremo de pérdida local), generamos una nueva para no violar el NOT NULL
    if (publicKey == null) {
      final keyPair = await _e2ee.generateKeyPair();
      final pubKeyBytes = await keyPair.extractPublicKey();
      publicKey = _bytesToBase64(pubKeyBytes.bytes);
      await _storage.write(key: 'public_key', value: publicKey);
    }

    // Z-001 Fase A: la public_key archivada en Supabase ES la identidad E2EE y
    // no debe sobrescribirse sin prueba de posesión. Si la fila ya existe,
    // se preserva la clave de la DB; la local solo aplica a filas nuevas.
    String pkToSend = publicKey;
    try {
      final existing = await _supabase
          .from('users')
          .select('public_key')
          .eq('id', _uid!)
          .maybeSingle();
      final dbKey = existing?['public_key']?.toString();
      if (dbKey != null && dbKey.isNotEmpty) {
        pkToSend = dbKey;
      }
    } catch (e) {
      _logger.debug('[ZoneIdService] No se pudo leer public_key previa: $e');
    }

    // Usamos UPSERT de forma defensiva por si el registro inicial en public.users falló.
    final profileData = {
      'id': _uid,
      'zone_id': _zoneId,
      'display_name': displayName,
      'public_key': pkToSend,
      'instagram_handle': instagram,
      'ig_visible': igVisible,
      'facebook_handle': facebook,
      'fb_visible': fbVisible,
      'tiktok_handle': tiktok,
      'tiktok_visible': tiktokVisible,
      'avatar_url': avatarUrl,
      'avatar_is_public': avatarIsPublic,
      'gallery_photos': galleryPhotos,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // La columna remota es updated_at (snake_case); Isar usa updatedAt (camelCase).
    // Enviar 'updatedAt' a Supabase devolvía 400 y dejaba el radar/pull-sync
    // sin marca de tiempo (Z-002 · alineación de esquema).
    final supabaseData = {
      ...profileData,
      'updated_at': DateTime.now().toIso8601String(),
    }..remove('updatedAt');

    await _supabase.from('users').upsert(supabaseData);
    await _isar.saveProfile(profileData);
  }

  Future<Map<String, dynamic>?> getMyLocalProfile() async {
    final currentZoneId = _zoneId ?? await _safeRead(_keyZoneId);
    if (currentZoneId == null || currentZoneId.isEmpty) return null;
    try {
      final profile = await _isar.getProfile(currentZoneId);
      if (profile == null) return null;
      return {
        'id': profile.userId,
        'zone_id': profile.zoneId,
        'display_name': profile.displayName,
        'avatar_url': profile.avatarUrl,
        'bio': profile.bio,
        'instagram_handle': profile.instagramHandle,
        'facebook_handle': profile.facebookHandle,
        'tiktok_handle': profile.tiktokHandle,
        'public_key': profile.publicKey,
      };
    } catch (e) {
      _logger.debug('[ZoneIdService] Error leyendo perfil local: $e');
      return null;
    }
  }

  /// Sube una imagen al bucket 'profiles' y devuelve la URL pública.
  Future<String> uploadProfilePicture(File file) async {
    await ensureAuth();

    final lastDot = file.path.lastIndexOf('.');
    final extension = lastDot == -1 ? '.jpg' : file.path.substring(lastDot);
    final fileName =
        '$_uid/avatar${DateTime.now().millisecondsSinceEpoch}$extension';

    // Subir archivo (sobrescribe si existe en la misma ruta, pero usamos timestamp para evitar cache)
    await _supabase.storage
        .from('profiles')
        .upload(
          fileName,
          file,
          fileOptions: const FileOptions(cacheControl: '3600', upsert: true),
        );

    // Obtener URL pública
    final String publicUrl = _supabase.storage
        .from('profiles')
        .getPublicUrl(fileName);
    return publicUrl;
  }

  Future<void> setStealthMode(bool enabled) async {
    if (_uid == null) return;
    await _supabase
        .from('users')
        .update({'stealth_mode': enabled})
        .eq('id', _uid!);
  }

  // ──────────────────────────────────────────────────────────
  //  Obtener perfil propio
  // ──────────────────────────────────────────────────────────

  Future<Map<String, dynamic>?> getMyProfile() async {
    try {
      await ensureAuth();
      // Asegurarse de que si el UID es nuevo o la fila falta, se intente recuperar/recrear
      await checkAndFixRegistration();

      if (_uid == null) return null;

      final res = await _supabase
          .from('users')
          .select()
          .eq('id', _uid!)
          .single();
      await _isar.saveProfile({
        ...res,
        'updatedAt': DateTime.now().toIso8601String(),
      });
      return res;
    } catch (e) {
      _logger.debug('[ZoneIdService] Error en getMyProfile: $e');
      return await getMyLocalProfile();
    }
  }

  Future<void> endRuntimeSession() async {
    try {
      await _supabase.auth.signOut();
    } catch (e) {
      _logger.debug('[ZoneIdService] Error cerrando sesiÃ³n runtime: $e');
    }
    await _storage.delete(key: _keySupabaseSession);
    _uid = null;
  }

  // ──────────────────────────────────────────────────────────
  //  Generación del ID
  // ──────────────────────────────────────────────────────────

  /// Valida el formato canónico de un ZONE-ID: `ZONE-` + 8×[A-Z0-9].
  /// Contrato compartido con el backend (claim_zone_id / verify_zone_id).
  static bool isValidZoneIdFormat(String? zoneId) {
    if (zoneId == null || zoneId.isEmpty) return false;
    return RegExp(r'^ZONE-[A-Z0-9]{8}$').hasMatch(zoneId);
  }

  String _generateZoneId() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final rnd = Random.secure();
    String code = String.fromCharCodes(
      Iterable.generate(8, (_) => chars.codeUnitAt(rnd.nextInt(chars.length))),
    );
    return 'ZONE-$code';
  }

  String _bytesToBase64(List<int> bytes) {
    return base64Encode(bytes);
  }

  Future<void> deleteAccount() async {
    await ensureAuth();
    if (_uid == null) return;

    // 1. Eliminar archivos de almacenamiento (Storage API oficial)
    try {
      final userFolder = _uid!;
      // Listamos los archivos del usuario para borrarlos
      final files = await _supabase.storage
          .from('profiles')
          .list(path: userFolder);
      if (files.isNotEmpty) {
        final pathsToDelete = files
            .map((f) => '$userFolder/${f.name}')
            .toList();
        await _supabase.storage.from('profiles').remove(pathsToDelete);
      }
    } catch (e) {
      _logger.debug(
        'Aviso: Fallo borrando storage, continuando con el perfil... $e',
      );
    }

    // 2. Llamar a la función de borrado total en Supabase (RPC)
    // Esto borra datos en public (usuarios, chats, tokens) y auth.
    await _supabase.rpc('delete_own_account');

    // 3. Limpiar toda la base de datos local (Isar)
    try {
      await _isar.clearAll();
    } catch (e) {
      _logger.debug('Aviso: Fallo limpiando Isar: $e');
    }

    // 4. Limpiar SharedPreferences
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
    } catch (e) {
      _logger.debug('Aviso: Fallo limpiando SharedPreferences: $e');
    }

    // 5. Limpiar todo el estado local (claves, sesión)
    await clearAuth();
  }

  /// Limpia la sesión local y los chats mock.
  Future<void> clearAuth() async {
    await _storage.delete(key: _keyZoneId);
    await _storage.delete(key: _keySupabaseSession);
    await _storage.delete(key: _keyPrivateKey);
    await _storage.delete(key: _keyPublicKey);

    // Limpiar todas las session keys almacenadas de forma segura
    try {
      await P2PSecurityService().deleteAllSessionKeys();
    } catch (e) {
      _logger.debug('[ZoneIdService] Error limpiando session keys: $e');
    }

    await _supabase.auth.signOut();
    _zoneId = null;
    _uid = null;
  }
}
