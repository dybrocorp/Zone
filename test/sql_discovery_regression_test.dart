import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard estático de las migraciones de diseño freemium (z214/z215).
///
/// Misma filosofía que `sql_security_regression_test.dart` (Fase A / Z-212):
/// leer los SQL reales del repo y fallar si se reintroduce una vulnerabilidad.
/// Las invariantes de este rediseño son:
///
///  - Z-214: tablas nacen con RLS; `discovery_presence` SIN policies
///    (deny-all); las RPC nuevas revocan anon/PUBLIC y otorgan a
///    authenticated; la firma de `discover_nearby_users` no devuelve lat/lng
///    de otros; definer con `search_path` fijado; TTL server en el ping.
///  - Z-215: `user_entitlements` nace con RLS y sin policies DML; ningún GRANT
///    de escritura de la tabla a authenticated; la RPC de lectura no expone
///    purchase_token.
void main() {
  late Directory root;
  late File z214;
  late File z215;
  late String z214Code;
  late String z215Code;

  setUpAll(() {
    root = _projectRoot();
    z214 =
        File('${root.path}/supabase_migrations/z214_discovery_geo.sql');
    z215 = File(
        '${root.path}/supabase_migrations/z215_user_entitlements.sql');
    z214Code = _stripComments(z214.readAsStringSync());
    z215Code = _stripComments(z215.readAsStringSync());
  });

  test('existen las migraciones z214/z215', () {
    expect(z214.existsSync(), isTrue, reason: 'Falta z214_discovery_geo.sql');
    expect(z215.existsSync(), isTrue, reason: 'Falta z215_user_entitlements.sql');
  });

  group('Z-214 — descubrimiento geográfico', () {
    test('S-01: las tablas nacen con ENABLE ROW LEVEL SECURITY', () {
      expect(z214Code, matches(_rlsOn('discovery_preferences')));
      expect(z214Code, matches(_rlsOn('discovery_presence')));
    });

    test('S-02: discovery_presence sin policies (deny-all por REST)', () {
      final policies = RegExp(
        r'CREATE\s+POLICY[^;]+ON\s+public\.discovery_presence',
      );
      expect(policies.hasMatch(z214Code), isFalse,
          reason: 'discovery_presence debe quedar deny-all: la lectura de '
              'coordenadas de otros usuarios va solo por RPC definer.');
    });

    test('S-03: RPCs nuevas revocadas a anon/PUBLIC + GRANT authenticated', () {
      for (final rpc in [
        'set_discovery_preference',
        'upsert_discovery_presence',
        'discover_nearby_users',
        'expire_my_presence',
        'get_discovery_preferences',
      ]) {
        expect(
          z214Code,
          matches(RegExp('REVOKE EXECUTE ON FUNCTION public\\.$rpc')),
          reason: '$rpc debe tener REVOKE explícito');
        expect(
          z214Code,
          matches(RegExp(
              'GRANT EXECUTE ON FUNCTION public\\.$rpc[^;]*TO authenticated, service_role')),
          reason: '$rpc debe otorgarse solo a authenticated/service_role');
      }
      // patrón común del canon: REVOKE ... FROM PUBLIC, anon, authenticated
      expect(
        z214Code,
        matches(RegExp(r'FROM PUBLIC, anon, authenticated')),
      );
    });

    test('S-04: SECURITY DEFINER con search_path fijado', () {
      final definers = RegExp(
        r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.\w+[\s\S]*?SECURITY\s+DEFINER',
      );
      expect(definers.allMatches(z214Code), isNotEmpty);
      expect(
        z214Code,
        matches(RegExp(r'SET\s+search_path\s+TO')),
        reason: 'Toda función definer debe fijar search_path.',
      );
    });

    test('S-06: la firma de discover_nearby_users no expone coordenadas', () {
      final inicioRpc = z214Code.indexOf(
          'CREATE OR REPLACE FUNCTION public.discover_nearby_users');
      final firma =
          z214Code.substring(inicioRpc, z214Code.indexOf('LANGUAGE', inicioRpc));
      // RETURNS TABLE solo con campos autorizados + distancia
      expect(firma, contains('RETURNS TABLE'));
      expect(firma, contains('distance_m'));
      expect(
        _extractReturnsTable(firma),
        isNot(contains('lat')),
        reason: 'RETURNS TABLE no puede contener lat',
      );
      expect(
        _extractReturnsTable(firma),
        isNot(contains('lng')),
        reason: 'RETURNS TABLE no puede contener lng',
      );
    });

    test('S-07: TTL server-side en el ping (30 minutos por el servidor)', () {
      expect(
        z214Code,
        matches(RegExp(r"INTERVAL\s+'30 minutes'")),
        reason: 'El TTL de presencia lo fija el servidor, no el cliente.',
      );
    });

    test('S-08: FK CASCADE hacia users en las tablas nuevas', () {
      for (final tabla in ['discovery_preferences', 'discovery_presence']) {
        final modulo = z214Code.substring(
            z214Code.indexOf('CREATE TABLE IF NOT EXISTS public.$tabla'));
        expect(modulo, matches(RegExp(r'user_id UUID PRIMARY KEY')),
            reason: '$tabla: user_id debe ser PK canónica');
        expect(modulo, matches(RegExp(r'ON DELETE CASCADE')),
            reason: '$tabla: el borrado de cuenta vacía sus datos geo');
      }
    });
  });

  group('Z-215 — entitlements', () {
    test('S-01: tabla nace con RLS', () {
      expect(z215Code, matches(_rlsOn('user_entitlements')));
    });

    test('S-02: sin policies DML (escritura solo service_role vía definer)', () {
      final policies = RegExp(
        r'CREATE\s+POLICY[^;]+ON\s+public\.user_entitlements',
      );
      expect(policies.hasMatch(z215Code), isFalse,
          reason: 'user_entitlements: ningún usuario autenticado puede '
              'escribir su entitlement por REST.');
    });

    test('S-05: sin GRANT de DML de tabla a authenticated', () {
      final grantsDml = RegExp(
        r'GRANT\s+(ALL|INSERT|UPDATE|DELETE)[^;]+ON\s+(public\.)?user_entitlements[^;]+TO\s+authenticated',
      );
      expect(grantsDml.hasMatch(z215Code), isFalse,
          reason: 'La escritura de entitlements es exclusiva de service_role.');
      expect(
        z215Code,
        matches(RegExp(
            r'REVOKE\s+ALL\s+ON\s+public\.user_entitlements\s+FROM\s+anon,\s*authenticated')),
      );
    });

    test('S-03: get_my_entitlements / has_bluetooth_premium revocadas a anon', () {
      expect(z215Code,
          matches(RegExp(r'REVOKE EXECUTE ON FUNCTION public\.get_my_entitlements')));
      expect(z215Code,
          matches(RegExp(r'REVOKE EXECUTE ON FUNCTION public\.has_bluetooth_premium')));
    });

    test('la RPC de lectura nunca expone purchase_token', () {
      final inicio = z215Code.indexOf(
          'CREATE OR REPLACE FUNCTION public.get_my_entitlements');
      final fin = z215Code.indexOf(r'$$;', inicio);
      final cuerpo = z215Code.substring(inicio, fin);
      expect(
        cuerpo,
        isNot(contains('purchase_token')),
        reason: 'El token de compra es sensible; la lectura del dueño no '
            'debe exponerlo.',
      );
    });
  });
}

// ─────────────────────────── Helpers ───────────────────────────

/// Extrae el contenido de "RETURNS TABLE(...)" de una firma SQL.
String _extractReturnsTable(String firma) {
  final abrir = firma.indexOf('RETURNS TABLE');
  if (abrir < 0) return '';
  final cerrar = firma.indexOf(')', abrir);
  return firma.substring(abrir, cerrar < 0 ? firma.length : cerrar);
}

RegExp _rlsOn(String table) => RegExp(
    'ALTER TABLE public\\.$table\\s+ENABLE\\s+ROW\\s+LEVEL\\s+SECURITY');

Directory _projectRoot() {
  var dir = Directory.current;
  while (!File('${dir.path}/pubspec.yaml').existsSync()) {
    final parent = dir.parent;
    if (parent.path == dir.path) {
      throw StateError('No se encontró el root del proyecto (pubspec.yaml)');
    }
    dir = parent;
  }
  return dir;
}

/// Elimina comentarios SQL (-- línea y /* bloque */) para que los guards solo
/// examinen código ejecutable.
String _stripComments(String source) {
  final sinBloque = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  final buffer = StringBuffer();
  for (final line in sinBloque.split('\n')) {
    final cut = line.indexOf('--');
    buffer.writeln(cut >= 0 ? line.substring(0, cut) : line);
  }
  return buffer.toString();
}
