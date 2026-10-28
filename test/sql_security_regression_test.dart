import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Guard de regresión estático de la Fase A / Z-212.
///
/// El defecto P0 original era `UPDATE public.users SET id = auth.uid()`, que
/// permitía account takeover sin prueba de posesión. Este test lee los SQL
/// reales (esquema canónico, deploy y TODAS las migraciones, incluidas las
/// históricas) y falla si una sentencia ejecutable vuelve a asignar `users.id`.
///
/// También comprueba que cada definición de `claim_zone_id` instala la
/// cuarentena fail-closed y que los controles Z-212 siguen presentes en el
/// esquema canónico y en el deploy.
void main() {
  late Directory root;
  late List<File> sqlFiles;

  setUpAll(() {
    root = _projectRoot();
    sqlFiles = _sqlFiles(root);
  });

  test('ningún SQL ejecutable reescribe users.id (Z-001/Z-212)', () {
    final offenders = <String>[];

    for (final file in sqlFiles) {
      final code = _stripSqlComments(file.readAsStringSync());
      for (final statement in _userUpdateStatements(code)) {
        final setClause = _setClause(statement);
        if (setClause != null && _assignsId(setClause)) {
          final firstLine = statement.trim().split('\n').first.trim();
          offenders.add('${_relative(root, file)}: $firstLine');
        }
      }
    }

    expect(
      offenders,
      isEmpty,
      reason: 'El claim inseguro no puede volver: users.id solo se migra con '
          'una prueba de posesión verificada server-side (Z-212). '
          'Sentencias ofensoras: $offenders',
    );
  });

  test('cada definición de claim_zone_id instala la cuarentena fail-closed',
      () {
    final definition = RegExp(
      r'CREATE\s+OR\s+REPLACE\s+FUNCTION\s+public\.claim_zone_id\s*\(',
      caseSensitive: false,
    );
    final definingFiles = <String>[];

    for (final file in sqlFiles) {
      final code = _stripSqlComments(file.readAsStringSync());
      if (!definition.hasMatch(code)) continue;

      final relative = _relative(root, file);
      definingFiles.add(relative);
      final body = _functionBody(code, definition);
      expect(body, isNotNull, reason: 'No se pudo extraer el cuerpo de claim_zone_id en $relative');
      expect(
        body,
        contains(
          'Reclamo de ZONE-ID deshabilitado temporalmente por seguridad (Z-212).',
        ),
        reason: 'claim_zone_id en $relative debe fallar cerrado (Z-212)',
      );
    }

    expect(
      definingFiles,
      containsAll(<String>[
        'supabase_schema.sql',
        'supabase_deploy.sql',
        'supabase_migrations/secure_claim_zone_id.sql',
        'supabase_migrations/z002_profile_visibility.sql',
        'supabase_migrations/z212_security_hardening.sql',
      ]),
      reason: 'El guard debe cubrir el esquema, el deploy y las migraciones '
          'históricas que redefinen el claim.',
    );
  });

  test('migraciones históricas no reintroducen políticas Z-212', () {
    final separator = Platform.pathSeparator;

    final radar = File(
      '${root.path}${separator}supabase_migrations${separator}fix_radar_bilateral.sql',
    );
    expect(radar.existsSync(), isTrue);
    final radarCode = _stripSqlComments(radar.readAsStringSync());
    expect(
      RegExp(r'CREATE\s+POLICY\s+"Resolver token BT"', caseSensitive: false)
          .hasMatch(radarCode),
      isFalse,
      reason: 'fix_radar_bilateral.sql no puede recrear la policy amplia de bt_tokens',
    );
    expect(
      radarCode,
      contains('auth.uid() IS NULL'),
      reason: 'resolve_bt_token debe exigir sesión al re-aplicarse',
    );
    expect(
      radarCode,
      contains('CASE WHEN u.avatar_is_public'),
      reason: 'resolve_bt_token debe filtrar avatar privado al re-aplicarse',
    );

    final z106 = File(
      '${root.path}${separator}supabase_migrations${separator}z106_z206_policies.sql',
    );
    expect(z106.existsSync(), isTrue);
    final z106Code = _stripSqlComments(z106.readAsStringSync());
    expect(
      RegExp(
        r'CREATE\s+POLICY\s+"Actualizar mensaje con match aceptado"',
        caseSensitive: false,
      ).hasMatch(z106Code),
      isFalse,
      reason: 'z106 no puede recrear el UPDATE directo de messages (Z-212)',
    );
    expect(
      z106Code,
      contains('DROP POLICY IF EXISTS "Actualizar mensaje con match aceptado"'),
      reason: 'z106 debe eliminar el UPDATE directo al re-aplicarse',
    );
  });

  test('controles Z-212 presentes en esquema canónico y deploy', () {
    for (final name in const <String>[
      'supabase_schema.sql',
      'supabase_deploy.sql',
    ]) {
      final file = File('${root.path}${Platform.pathSeparator}$name');
      expect(file.existsSync(), isTrue, reason: 'Falta $name');
      final code = _stripSqlComments(file.readAsStringSync());

      expect(
        code,
        contains('enforce_user_protected_columns'),
        reason: '$name debe proteger las columnas sensibles de users',
      );
      expect(
        code,
        contains('DROP POLICY IF EXISTS "Resolver token BT" ON public.bt_tokens;'),
        reason: '$name debe eliminar la política SELECT amplia de bt_tokens',
      );
      expect(
        code,
        contains(
          'DROP POLICY IF EXISTS "Actualizar mensaje con match aceptado" ON public.messages;',
        ),
        reason: '$name debe eliminar el UPDATE directo de messages',
      );
      expect(
        RegExp(
          r'CREATE\s+POLICY\s+"Aceptar o rechazar match"[\s\S]*?'
          r'WITH\s+CHECK\s*\(\s*auth\.uid\(\)\s*=\s*receiver_id\s*\)',
          caseSensitive: false,
        ).hasMatch(code),
        isTrue,
        reason: '$name debe mantener el WITH CHECK del receptor en matches',
      );
      expect(
        RegExp(
          r'CREATE\s+POLICY[^;]*ON\s+public\.messages[^;]*FOR\s+UPDATE',
          caseSensitive: false,
        ).hasMatch(code),
        isFalse,
        reason: '$name no puede reintroducir una política UPDATE en messages',
      );
    }
  });
}

Directory _projectRoot() {
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    final manifest = File(
      '${dir.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (manifest.existsSync()) return dir;
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  fail('No se encontró pubspec.yaml desde ${Directory.current.path}');
}

List<File> _sqlFiles(Directory root) {
  final separator = Platform.pathSeparator;
  final files = <File>[
    File('${root.path}${separator}supabase_schema.sql'),
    File('${root.path}${separator}supabase_deploy.sql'),
  ];

  final migrations = Directory(
    '${root.path}${separator}supabase_migrations',
  );
  if (migrations.existsSync()) {
    files.addAll(
      migrations
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.sql')),
    );
  }

  return files.where((file) => file.existsSync()).toList(growable: false);
}

String _relative(Directory root, File file) {
  final prefix = '${root.path}${Platform.pathSeparator}';
  return file.path.startsWith(prefix)
      ? file.path.substring(prefix.length).replaceAll('\\', '/')
      : file.path;
}

/// Elimina comentarios SQL para que la documentación histórica (que menciona
/// el UPDATE vulnerable) no dispare falsos positivos.
String _stripSqlComments(String sql) {
  return sql
      .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), ' ')
      .replaceAll(RegExp(r'--[^\n]*'), ' ');
}

/// Devuelve el fragmento posterior a cada `UPDATE ... users` hasta el `;`.
Iterable<String> _userUpdateStatements(String code) sync* {
  final pattern = RegExp(
    r'\bUPDATE\s+(?:public\.)?users\b',
    caseSensitive: false,
  );
  for (final match in pattern.allMatches(code)) {
    final rest = code.substring(match.end);
    final semicolon = rest.indexOf(';');
    yield semicolon == -1 ? rest : rest.substring(0, semicolon);
  }
}

/// Extrae la lista SET (sin WHERE/RETURNING) de una sentencia UPDATE.
String? _setClause(String statement) {
  final setMatch = RegExp(r'\bSET\b', caseSensitive: false).firstMatch(statement);
  if (setMatch == null) return null;

  final afterSet = statement.substring(setMatch.end);
  final endMatch = RegExp(
    r'\b(?:WHERE|RETURNING)\b',
    caseSensitive: false,
  ).firstMatch(afterSet);
  return endMatch == null ? afterSet : afterSet.substring(0, endMatch.start);
}

/// Detecta `id = ...` como destino de asignación dentro del SET.
bool _assignsId(String setClause) {
  return RegExp(
    r'(?:^|,)\s*(?:\w+\.)?id\s*=',
    caseSensitive: false,
    multiLine: true,
  ).hasMatch(setClause);
}

/// Extrae el cuerpo dollar-quoted de la primera definición que coincida.
String? _functionBody(String code, RegExp definition) {
  final match = definition.firstMatch(code);
  if (match == null) return null;

  final rest = code.substring(match.end);
  final asMatch = RegExp(
    r'\bAS\s+\$([A-Za-z_]*)\$',
    caseSensitive: false,
  ).firstMatch(rest);
  if (asMatch == null) return null;

  final tag = asMatch.group(1) ?? '';
  final closing = '\$$tag\$;';
  final bodyEnd = rest.indexOf(closing, asMatch.end);
  if (bodyEnd == -1) return null;

  return rest.substring(asMatch.end, bodyEnd);
}
